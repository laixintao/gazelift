#!/usr/bin/env python3
"""Prepare a release from clean main; atomically push main and its annotated tag."""
from datetime import date
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def run(*args, check=True):
    return subprocess.run(args, cwd=ROOT, text=True, capture_output=True, check=check)


def git(*args):
    return run("git", *args).stdout.strip()


def version_tuple(value):
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", value):
        raise ValueError("Use a stable SemVer such as 0.2.0, without a v prefix.")
    return tuple(map(int, value.split(".")))


def main():
    if git("status", "--porcelain"):
        raise ValueError("Commit or stash changes before releasing; the worktree must be clean.")
    if git("branch", "--show-current") != "main":
        raise ValueError("Release from main.")
    requested = os.environ.get("VERSION") or None
    if requested:
        version_tuple(requested)
    git("remote", "get-url", "origin")
    remote_main = git("ls-remote", "origin", "refs/heads/main")
    if remote_main:
        git("fetch", "--quiet", "origin", "refs/heads/main", "--tags")
        remote_head = git("rev-parse", "FETCH_HEAD")
        if run("git", "merge-base", "--is-ancestor", remote_head, "HEAD", check=False).returncode:
            raise ValueError("Remote main has changes you do not have. Pull or rebase first.")
    else:
        git("fetch", "--quiet", "origin", "--tags")

    info_path = ROOT / "GazeLift/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    current = info["CFBundleShortVersionString"]
    current_tuple = version_tuple(current)
    tags = [tag for tag in git("tag", "--list", "v*").splitlines()
            if re.fullmatch(r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", tag)]
    if tags and current_tuple < max(version_tuple(tag[1:]) for tag in tags):
        raise ValueError("Bundle version is behind an existing release tag.")
    first = not tags
    major, minor, patch = current_tuple
    version = requested or (current if first else f"{major}.{minor}.{patch + 1}")
    if version_tuple(version) < current_tuple or (not first and version_tuple(version) <= current_tuple):
        raise ValueError("The next release must have a newer version.")
    tag = f"v{version}"
    if run("git", "show-ref", "--verify", "--quiet", f"refs/tags/{tag}", check=False).returncode == 0:
        raise ValueError(f"{tag} already exists locally. Retry its push instead of releasing again.")
    if git("ls-remote", "origin", f"refs/tags/{tag}"):
        raise ValueError(f"{tag} already exists on origin.")
    # A failed atomic push must be retried, not silently bumped into another release.
    if tags:
        latest = max(tags, key=lambda item: version_tuple(item[1:]))
        if not git("ls-remote", "origin", f"refs/tags/{latest}"):
            raise ValueError(f"Local release {latest} is not on origin. Retry its atomic push before releasing again.")
    merged = [tag for tag in git("tag", "--merged", "HEAD").splitlines() if tag in tags]
    base = max(merged, key=lambda item: version_tuple(item[1:])) if merged else None
    revision = f"{base}..HEAD" if base else "HEAD"
    commits = git("log", "--no-merges", "--format=%h%x09%s", revision)
    if not commits:
        raise ValueError("There are no new commits since the previous release.")
    changes = []
    for line in commits.splitlines():
        sha, subject = line.split("\t", 1)
        subject = re.sub(r"([\\`*_\[\]<>])", r"\\\1", subject)
        changes.append(f"- {subject} (`{sha}`)")
    change_text = "\n".join(changes)

    # Everything above is a preflight: no source files have been changed.
    if version != current:
        text = info_path.read_text()
        for key, value in (("CFBundleShortVersionString", version),
                           ("CFBundleVersion", str(int(info["CFBundleVersion"]) + 1))):
            text, count = re.subn(rf"(<key>{key}</key>\s*<string>)[^<]*(</string>)",
                                  lambda match: match[1] + value + match[2], text)
            if count != 1:
                raise ValueError(f"Expected one {key} in Info.plist")
        info_path.write_text(text)
    notes = ROOT / f"docs/releases/{tag}.md"
    notes.parent.mkdir(parents=True, exist_ok=True)
    if not notes.exists():
        notes.write_text(f"# GazeLift {version}\n\n## Changes\n\n{change_text}\n\n"
                         f"Download `GazeLift-{version}-macos-universal.dmg` or the matching ZIP. "
                         "Requires macOS 14+ on Apple Silicon or Intel.\n\n"
                         "Ad-hoc signed, not notarized. If blocked, use System Settings → Privacy & Security → Open Anyway. "
                         "Checksums: `SHA256SUMS`.\n")
    changelog = ROOT / "CHANGELOG.md"
    content = changelog.read_text()
    if not re.search(rf"^## {re.escape(version)}(?:\s|$)", content, re.M):
        heading, _, remainder = content.partition("\n")
        changelog.write_text(f"{heading}\n\n## {version} — {date.today().isoformat()}\n\n{change_text}\n\n{remainder.lstrip()}")
    subprocess.run([sys.executable, "scripts/check-project.py", "--release-tag", tag], cwd=ROOT, check=True)
    git("add", "--", "GazeLift/Info.plist", "CHANGELOG.md", f"docs/releases/{tag}.md")
    git("commit", "--allow-empty", "-m", f"Release {tag}")
    git("tag", "-a", tag, "-m", f"GazeLift {version}")
    pushed = run("git", "push", "--atomic", "origin", "HEAD:refs/heads/main", f"refs/tags/{tag}", check=False)
    if pushed.returncode:
        print(pushed.stderr, file=sys.stderr)
        print(f"Release commit and tag retained. Retry exactly:\n"
              f"  git push --atomic origin HEAD:refs/heads/main refs/tags/{tag}\n"
              "Do not run make release again for this version.", file=sys.stderr)
        return 1
    print(f"Pushed {tag}. CI will build and publish the release.\n"
          "https://github.com/laixintao/gazelift/actions/workflows/release.yml")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        sys.exit(1)
