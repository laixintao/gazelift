#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-Release}"
architecture="${2:-native}"
case "$configuration" in
  Release) flags=(-O) ;;
  Debug) flags=(-Onone -g -D DEBUG) ;;
  *) echo 'Expected Debug or Release' >&2; exit 1 ;;
esac
case "$architecture" in
  native) architectures=("$(uname -m)") ;;
  universal) architectures=(arm64 x86_64) ;;
  arm64|x86_64) architectures=("$architecture") ;;
  *) echo 'Expected native, universal, arm64, or x86_64' >&2; exit 1 ;;
esac
build="build/$configuration-$architecture"
mkdir -p "$build" build/ModuleCache build/Resources
stage="$(mktemp -d "$build/.stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/GazeLift.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
sdk="$(xcrun --show-sdk-path)"
binaries=()
for arch in "${architectures[@]}"; do
  xcrun swiftc -swift-version 6 -warnings-as-errors -parse-as-library \
    -target "$arch-apple-macosx14.0" -sdk "$sdk" -module-cache-path build/ModuleCache \
    -module-name GazeLift "${flags[@]}" GazeLift/*.swift -o "$stage/GazeLift-$arch"
  binaries+=("$stage/GazeLift-$arch")
done
xcrun lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/GazeLift"
cp GazeLift/Info.plist "$app/Contents/Info.plist"
cp -R GazeLift/Resources/. "$app/Contents/Resources/"
if [[ ! -s build/Resources/GazeLift.icns || scripts/MakeIcon.swift -nt build/Resources/GazeLift.icns ]]; then
  xcrun swift -module-cache-path build/ModuleCache scripts/MakeIcon.swift "$stage/GazeLift.iconset"
  iconutil -c icns "$stage/GazeLift.iconset" -o build/Resources/GazeLift.icns
fi
cp build/Resources/GazeLift.icns LICENSE "$app/Contents/Resources/"
plutil -lint "$app/Contents/Info.plist" "$app"/Contents/Resources/*.lproj/Localizable.strings
codesign --force --sign - "$app"
codesign --verify --strict --all-architectures "$app"
# Replace only our generated build product after a successful staged build.
if [[ -d "$build/GazeLift.app" ]]; then rm -rf "$build/GazeLift.app"; fi
mv "$app" "$build/GazeLift.app"
echo "Built: $build/GazeLift.app"
