#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="build/Release-universal/GazeLift.app"
[[ -d "$app" ]] || { echo 'Build the universal app before packaging' >&2; exit 1; }
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo 'Invalid bundle version' >&2; exit 1; }
out="${ARTIFACT_DIR:-dist/releases}"
mkdir -p "$out"
stage="$(mktemp -d "$out/.package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
name="GazeLift-$version-macos-universal"
mkdir "$stage/image"
ditto "$app" "$stage/image/GazeLift.app"
ln -s /Applications "$stage/image/Applications"
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$name.zip"
hdiutil create -quiet -volname GazeLift -srcfolder "$stage/image" -format UDZO -fs HFS+ "$stage/$name.dmg"
(cd "$stage" && shasum -a 256 "$name.dmg" "$name.zip" > SHA256SUMS)
for old in "$out"/GazeLift-*-macos-universal.dmg "$out"/GazeLift-*-macos-universal.zip; do
  if [[ -f "$old" ]]; then rm -f "$old"; fi
done
mv "$stage/$name.dmg" "$stage/$name.zip" "$stage/SHA256SUMS" "$out/"
echo "Packaged: $out/$name.dmg"
