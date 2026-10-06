#!/usr/bin/env python3
"""Publish verified artifacts via a resumable draft; public releases are immutable."""
import json
import os
from pathlib import Path
import subprocess
import sys

from artifacts import verify_artifacts

ROOT = Path(__file__).resolve().parent.parent


def gh(*args, check=True):
    return subprocess.run(["gh", *args], cwd=ROOT, text=True, capture_output=True, check=check)


def publish(tag, directory, repository):
    subprocess.run([sys.executable, "scripts/check-project.py", "--release-tag", tag], cwd=ROOT, check=True)
    assets = verify_artifacts(directory, tag[1:])
    result = gh("api", f"repos/{repository}/releases/tags/{tag}", check=False)
    if result.returncode == 0:
        existing = json.loads(result.stdout)
        if not existing["draft"]:
            print(f"{tag} is already public; no assets or metadata changed.")
            return
    elif "HTTP 404" not in result.stderr:
        raise RuntimeError(f"Could not check existing release: {result.stderr.strip()}")
    else:
        gh("release", "create", tag, "--repo", repository, "--verify-tag", "--draft",
           "--title", f"GazeLift {tag[1:]}", "--notes-file", f"docs/releases/{tag}.md")
    gh("release", "edit", tag, "--repo", repository, "--title", f"GazeLift {tag[1:]}",
       "--notes-file", f"docs/releases/{tag}.md")
    gh("release", "upload", tag, "--repo", repository, *[str(path) for path in assets], "--clobber")
    gh("release", "edit", tag, "--repo", repository, "--draft=false", "--latest")
    print(f"Published https://github.com/{repository}/releases/tag/{tag}")


if __name__ == "__main__":
    try:
        publish(os.environ["RELEASE_TAG"], Path(os.environ.get("ARTIFACT_DIR") or "dist/releases").resolve(),
                os.environ["GH_REPO"])
    except (KeyError, ValueError, OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Publication stopped: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr, file=sys.stderr)
        sys.exit(1)
