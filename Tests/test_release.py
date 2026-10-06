import hashlib
from contextlib import redirect_stdout
import io
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from artifacts import verify_artifacts  # noqa: E402

spec = importlib.util.spec_from_file_location("publisher", ROOT / "scripts/publish-release.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gazelift-release-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.work = self.root / "work"
        shutil.copytree(ROOT, self.work, ignore=shutil.ignore_patterns(".git", "build", "dist", "__pycache__"))
        self.remote = self.root / "remote.git"
        self.env = os.environ.copy()
        for key in ["VERSION", "RELEASE_TAG", "ARTIFACT_DIR", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"]:
            self.env.pop(key, None)
        self.env.update({"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0"})
        self.command("git", "init", "--bare", "--initial-branch=main", str(self.remote))
        self.git("init", "--initial-branch=main")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "release-test@example.invalid")
        self.git("add", ".")
        self.git("commit", "-m", "Initial implementation")
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "-u", "origin", "main")

    def command(self, *args, check=True, env=None):
        return subprocess.run(args, cwd=self.work, text=True, capture_output=True, check=check, env=env or self.env)

    def git(self, *args):
        return self.command("git", *args).stdout.strip()

    def release(self, version=None):
        env = dict(self.env)
        if version is not None:
            env["VERSION"] = version
        return self.command("make", "release", check=False, env=env)

    def commit_change(self):
        (self.work / "feature.txt").write_text("A useful new feature\n")
        self.git("add", ".")
        self.git("commit", "-m", "Add a feature")

    def test_first_release_uses_current_version_and_preserves_notes(self):
        notes = (self.work / "docs/releases/v0.1.0.md").read_text()
        result = self.release()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("cat-file", "-t", "v0.1.0"), "tag")
        self.assertEqual(self.git("log", "-1", "--format=%s"), "Release v0.1.0")
        self.assertTrue(self.git("ls-remote", "origin", "refs/tags/v0.1.0"))
        self.assertEqual(notes, (self.work / "docs/releases/v0.1.0.md").read_text())
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_next_release_bumps_patch_and_build_and_generates_notes(self):
        self.assertEqual(self.release().returncode, 0)
        self.commit_change()
        result = self.release()
        self.assertEqual(result.returncode, 0, result.stderr)
        info = plistlib.loads((self.work / "GazeLift/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleShortVersionString"], "0.1.1")
        self.assertEqual(info["CFBundleVersion"], "2")
        self.assertIn("Add a feature", (self.work / "docs/releases/v0.1.1.md").read_text())

    def test_explicit_version(self):
        result = self.release("0.2.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.git("ls-remote", "origin", "refs/tags/v0.2.0"))

    def test_invalid_or_older_version_does_not_edit_sources(self):
        for version in ["v0.2.0", "0.2.0-rc.1", "0.01.0", "0.0.9", "0.2.0\nmalicious"]:
            with self.subTest(version=version):
                self.assertNotEqual(self.release(version).returncode, 0)
                self.assertEqual(self.git("status", "--porcelain"), "")
                self.assertEqual(self.git("tag"), "")

    def test_dirty_worktree_and_wrong_branch_stop(self):
        (self.work / "uncommitted.txt").write_text("keep me")
        self.assertNotEqual(self.release().returncode, 0)
        self.assertEqual((self.work / "uncommitted.txt").read_text(), "keep me")
        self.git("add", ".")
        self.git("commit", "-m", "Keep local changes")
        self.git("switch", "-c", "feature")
        self.assertNotEqual(self.release().returncode, 0)
        self.assertEqual(self.git("tag"), "")

    def test_local_tag_conflict_stops(self):
        self.git("tag", "v0.2.0")
        result = self.release("0.2.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_remote_ahead_stops_without_edits(self):
        self.commit_change()
        self.git("push", "origin", "main")
        self.git("reset", "--hard", "HEAD~1")
        before = self.git("rev-parse", "HEAD")
        result = self.release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Remote main", result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), before)
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_remote_tag_conflict_is_fetched_before_edits(self):
        self.git("tag", "v0.2.0")
        self.git("push", "origin", "refs/tags/v0.2.0")
        self.git("tag", "-d", "v0.2.0")
        self.assertNotEqual(self.release("0.2.0").returncode, 0)
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_rejected_atomic_push_keeps_release_and_can_retry(self):
        previous = self.git("rev-parse", "HEAD")
        hook = self.remote / "hooks/pre-receive"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)
        result = self.release()
        self.assertNotEqual(result.returncode, 0)
        retry = "git push --atomic origin HEAD:refs/heads/main refs/tags/v0.1.0"
        self.assertIn(retry, result.stderr)
        self.assertEqual(self.git("cat-file", "-t", "v0.1.0"), "tag")
        self.assertIn(previous, self.git("ls-remote", "origin", "refs/heads/main"))
        self.assertEqual(self.git("ls-remote", "origin", "refs/tags/v0.1.0"), "")
        self.assertNotEqual(self.release().returncode, 0)
        self.assertEqual(self.git("tag"), "v0.1.0")
        hook.unlink()
        self.command(*retry.split())
        self.assertTrue(self.git("ls-remote", "origin", "refs/tags/v0.1.0"))

    def test_no_changes_prevents_redundant_release(self):
        self.assertEqual(self.release().returncode, 0)
        self.assertNotEqual(self.release().returncode, 0)
        self.assertEqual(self.git("tag"), "v0.1.0")


class ArtifactAndPublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gazelift-artifacts-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.names = ["GazeLift-0.1.0-macos-universal.dmg", "GazeLift-0.1.0-macos-universal.zip"]
        entries = []
        for name in self.names:
            data = (name + " test fixture").encode()
            (self.directory / name).write_bytes(data)
            entries.append(f"{hashlib.sha256(data).hexdigest()}  {name}")
        (self.directory / "SHA256SUMS").write_text("\n".join(entries) + "\n")

    def test_checksum_and_exact_asset_set(self):
        self.assertEqual(len(verify_artifacts(self.directory, "0.1.0")), 3)
        (self.directory / self.names[0]).write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
            verify_artifacts(self.directory, "0.1.0")

    def test_manifest_rejects_duplicate_missing_and_path_traversal_entries(self):
        manifest = self.directory / "SHA256SUMS"
        content = manifest.read_text()
        for value in [content.splitlines()[0] + "\n", content + content.splitlines()[0] + "\n",
                      content.replace(self.names[0], "../" + self.names[0])]:
            manifest.write_text(value)
            with self.assertRaises(ValueError):
                verify_artifacts(self.directory, "0.1.0")

    def test_extra_or_missing_installer_rejected(self):
        extra = self.directory / "GazeLift-0.0.1-macos-universal.zip"
        extra.write_bytes(b"stale")
        with self.assertRaises(ValueError):
            verify_artifacts(self.directory, "0.1.0")
        extra.unlink()
        (self.directory / self.names[0]).unlink()
        with self.assertRaises(ValueError):
            verify_artifacts(self.directory, "0.1.0")

    def publish(self, state="missing", fail_upload=False):
        calls = []

        def fake_gh(*args, check=True):
            calls.append(args)
            if args[0] == "api":
                if state == "missing":
                    return subprocess.CompletedProcess(args, 1, "", "gh: Not Found (HTTP 404)")
                if state == "unauthorized":
                    return subprocess.CompletedProcess(args, 1, "", "gh: Bad credentials (HTTP 401)")
                return subprocess.CompletedProcess(args, 0, json.dumps({"draft": state == "draft"}), "")
            if args[:2] == ("release", "upload") and fail_upload:
                raise subprocess.CalledProcessError(1, args, stderr="Upload failed")
            return subprocess.CompletedProcess(args, 0, "", "")

        with patch.object(publisher, "gh", side_effect=fake_gh), patch.object(publisher.subprocess, "run"), redirect_stdout(io.StringIO()):
            try:
                publisher.publish("v0.1.0", self.directory, "laixintao/gazelift")
            except (RuntimeError, subprocess.CalledProcessError):
                if state != "unauthorized" and not fail_upload:
                    raise
        return calls

    def test_public_release_is_immutable(self):
        calls = self.publish("public")
        self.assertEqual(len(calls), 1)

    def test_missing_release_is_drafted_uploaded_then_published(self):
        calls = self.publish()
        self.assertIn("--draft", calls[1])
        self.assertEqual(calls[-2][:2], ("release", "upload"))
        self.assertIn("--draft=false", calls[-1])

    def test_existing_draft_is_resumed(self):
        calls = self.publish("draft")
        self.assertFalse(any(call[:2] == ("release", "create") for call in calls))
        self.assertIn("--draft=false", calls[-1])

    def test_upload_failure_keeps_draft(self):
        calls = self.publish(fail_upload=True)
        self.assertFalse(any("--draft=false" in call for call in calls))

    def test_auth_failure_is_not_treated_as_missing_release(self):
        self.assertEqual(len(self.publish("unauthorized")), 1)


if __name__ == "__main__":
    unittest.main()
