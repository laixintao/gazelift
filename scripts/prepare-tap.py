#!/usr/bin/env python3
"""Generate a cask from actual release artifacts; never modify the live tap."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import shutil

from artifacts import verify_artifacts

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--artifact-dir", type=Path, default=ROOT / "dist/releases")
parser.add_argument("--output", type=Path, default=ROOT / "dist/tap")
args = parser.parse_args()
version = plistlib.loads((ROOT / "GazeLift/Info.plist").read_bytes())["CFBundleShortVersionString"]
files = verify_artifacts(args.artifact_dir, version)
dmg = next(path for path in files if path.suffix == ".dmg")
digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
template = (ROOT / "packaging/homebrew/gazelift.rb.in").read_text()
args.output.mkdir(parents=True, exist_ok=True)
(args.output / "Casks").mkdir(exist_ok=True)
(args.output / "Casks/gazelift.rb").write_text(template.replace("@VERSION@", version).replace("@SHA256@", digest).rstrip() + "\n")
shutil.copy2(ROOT / "packaging/homebrew/packages-entry.json", args.output / "packages-entry.json")
print(f"Generated {args.output / 'Casks/gazelift.rb'} using the actual DMG checksum.")
print("Onboard only after these exact artifacts have been published; see packaging/homebrew/README.md.")
