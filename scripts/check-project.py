#!/usr/bin/env python3
"""Cross-platform validation of the public release contract."""
import argparse
import plistlib
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
SEMVER = r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"


def check(tag=None):
    info = plistlib.loads((ROOT / "GazeLift/Info.plist").read_bytes())
    version = info.get("CFBundleShortVersionString", "")
    errors = []
    if not re.fullmatch(SEMVER, version):
        errors.append("Expected a stable SemVer bundle version")
    if tag is not None and tag != f"v{version}":
        errors.append("Release tag must exactly match the bundle version")
    for key, value in {"CFBundleIdentifier": "io.xbin.gazelift", "CFBundleExecutable": "GazeLift",
                       "LSMinimumSystemVersion": "14.0", "LSUIElement": True}.items():
        if info.get(key) != value:
            errors.append(f"Invalid {key}")
    if not str(info.get("CFBundleVersion", "")).isdigit():
        errors.append("Expected an integer bundle build number")
    for name in ["README.md", "LICENSE", "CHANGELOG.md", "Makefile", "scripts/MakeIcon.swift",
                 ".github/workflows/ci.yml", ".github/workflows/build.yml", ".github/workflows/release.yml"]:
        if not (ROOT / name).is_file():
            errors.append(f"Missing {name}")
    notes = ROOT / f"docs/releases/v{version}.md"
    if not notes.is_file() or not notes.read_text().strip():
        errors.append(f"Missing release notes for {version}")
    if not re.search(rf"^## {re.escape(version)}(?:\s|$)", (ROOT / "CHANGELOG.md").read_text(), re.M):
        errors.append(f"Missing changelog entry for {version}")
    localizations = []
    for language in ["en", "zh-Hans"]:
        path = ROOT / f"GazeLift/Resources/{language}.lproj/Localizable.strings"
        keys = []
        for line in path.read_text().splitlines():
            if not line.strip():
                continue
            match = re.fullmatch(r'"([^"]+)"\s*=\s*"(?:\\.|[^"\\])*";', line)
            if not match:
                errors.append(f"Invalid localized string: {path.name}: {line}")
            else:
                keys.append(match[1])
        if len(keys) != len(set(keys)):
            errors.append(f"Duplicate localization keys in {language}")
        localizations.append(set(keys))
    if localizations[0] != localizations[1]:
        errors.append("English and Chinese localization keys must match")
    for workflow in (ROOT / ".github/workflows").glob("*.yml"):
        for action in re.findall(r"uses:\s*([^\s#]+)", workflow.read_text()):
            if not action.startswith("./") and not re.fullmatch(r"[^@]+@[0-9a-f]{40}", action):
                errors.append(f"Action not pinned to a full SHA: {action}")
    if errors:
        raise ValueError("\n".join(errors))
    print(f"PASS: project metadata and bilingual resources for GazeLift {version}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-tag")
    try:
        check(parser.parse_args().release_tag)
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        sys.exit(str(error))
