#!/usr/bin/env python3
"""Verify an exact, complete release asset set before using its checksums."""
import hashlib
from pathlib import Path
import re
import sys


def verify_artifacts(directory, version):
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", version):
        raise ValueError("Invalid version")
    directory = Path(directory)
    names = {f"GazeLift-{version}-macos-universal.{extension}" for extension in ("dmg", "zip")}
    present = {p.name for p in directory.iterdir() if p.suffix in (".dmg", ".zip")}
    if names != present:
        raise ValueError("Expected exactly the current version's universal DMG and ZIP")
    hashes = {}
    for line in (directory / "SHA256SUMS").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([^/\\]+)", line)
        if not match or match[2] not in names or match[2] in hashes:
            raise ValueError("Invalid, duplicate, or unexpected checksum entry")
        hashes[match[2]] = match[1]
    if set(hashes) != names:
        raise ValueError("Checksum manifest is incomplete")
    for name, expected in hashes.items():
        path = directory / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"Invalid artifact: {name}")
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != expected:
            raise ValueError(f"Checksum mismatch: {name}")
    return [directory / name for name in sorted(names)] + [directory / "SHA256SUMS"]


if __name__ == "__main__":
    try:
        verify_artifacts(sys.argv[1], sys.argv[2])
        print("PASS: complete release assets and SHA256SUMS")
    except (ValueError, OSError, IndexError) as error:
        sys.exit(str(error))
