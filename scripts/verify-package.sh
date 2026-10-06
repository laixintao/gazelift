#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' GazeLift/Info.plist)"
if [[ -n "${RELEASE_TAG:-}" && "$RELEASE_TAG" != "v$version" ]]; then
  echo 'Release tag and source version differ' >&2; exit 1
fi
out="${ARTIFACT_DIR:-dist/releases}"
out="$(cd "$out" && pwd)"
name="GazeLift-$version-macos-universal"
python3 scripts/artifacts.py "$out" "$version"

mkdir -p build/Verification
stage="$(mktemp -d build/Verification/package.XXXXXX)"
stage="$(cd "$stage" && pwd)"
mounted=false
cleanup() {
  if [[ "$mounted" == true ]]; then hdiutil detach -quiet "$stage/mounted" || true; fi
  rm -rf "$stage"
}
trap cleanup EXIT
verify_app() {
  local app="$1"
  codesign --verify --strict --all-architectures "$app"
  xcrun lipo "$app/Contents/MacOS/GazeLift" -verify_arch arm64 x86_64
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' GazeLift/Info.plist)" ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == io.xbin.gazelift ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")" == 14.0 ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app/Contents/Info.plist")" == true ]]
  [[ -s "$app/Contents/Resources/GazeLift.icns" ]]
  cmp LICENSE "$app/Contents/Resources/LICENSE"
  plutil -lint "$app"/Contents/Resources/*.lproj/Localizable.strings
}
ditto -x -k "$out/$name.zip" "$stage/unzipped"
verify_app "$stage/unzipped/GazeLift.app"
hdiutil verify -quiet "$out/$name.dmg"
mkdir "$stage/mounted"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$stage/mounted" "$out/$name.dmg"
mounted=true
verify_app "$stage/mounted/GazeLift.app"
[[ "$(readlink "$stage/mounted/Applications")" == /Applications ]]
diff -qr "$stage/unzipped/GazeLift.app" "$stage/mounted/GazeLift.app"
"$stage/unzipped/GazeLift.app/Contents/MacOS/GazeLift" --smoke-test
"$stage/unzipped/GazeLift.app/Contents/MacOS/GazeLift" --smoke-test -AppleLanguages '(zh-Hans)'
echo 'PASS: packaged native launch, architectures, signatures, metadata, resources and DMG/ZIP equality'
