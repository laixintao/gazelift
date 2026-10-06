#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/Tests build/ModuleCache
flags=(-swift-version 6 -warnings-as-errors -parse-as-library -Onone -g -D DEBUG
       -target "$(uname -m)-apple-macosx14.0" -sdk "$(xcrun --show-sdk-path)" -module-cache-path build/ModuleCache)
xcrun swiftc "${flags[@]}" GazeLift/UsageEngine.swift Tests/UsageEngineTests.swift -o build/Tests/UsageEngineTests
build/Tests/UsageEngineTests
app=build/Tests/GazeLiftTests.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp GazeLift/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier io.xbin.gazelift.tests' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable GazeLiftTests' "$app/Contents/Info.plist"
cp -R GazeLift/Resources/. "$app/Contents/Resources/"
sources=()
for source in GazeLift/*.swift; do
  [[ "$source" == GazeLift/Main.swift ]] || sources+=("$source")
done
xcrun swiftc "${flags[@]}" "${sources[@]}" Tests/UITests.swift -o "$app/Contents/MacOS/GazeLiftTests"
codesign --force --sign - "$app"
"$app/Contents/MacOS/GazeLiftTests" -AppleLanguages '(en)'
"$app/Contents/MacOS/GazeLiftTests" -AppleLanguages '(zh-Hans)'
