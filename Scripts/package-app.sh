#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/CaptionGrab.app"
ZIP="dist/CaptionGrab.zip"
EXTRACTED="dist/verify-extracted"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXTRACTED"

MACOSX_DEPLOYMENT_TARGET=26.0 swift build -c release --product CaptionGrab
install -m 755 .build/release/CaptionGrab "$APP/Contents/MacOS/CaptionGrab"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift Scripts/generate_icon.swift "$APP/Contents/Resources/CaptionGrab.iconset"
iconutil -c icns "$APP/Contents/Resources/CaptionGrab.iconset" -o "$APP/Contents/Resources/CaptionGrab.icns"
rm -rf "$APP/Contents/Resources/CaptionGrab.iconset"

plutil -lint "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist" | grep -Fx '26.0'
codesign --force --deep --sign - --entitlements Resources/CaptionGrab.entitlements "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
ditto -x -k "$ZIP" "$EXTRACTED"
EXTRACTED_APP="$EXTRACTED/CaptionGrab.app"
test -x "$EXTRACTED_APP/Contents/MacOS/CaptionGrab"
plutil -lint "$EXTRACTED_APP/Contents/Info.plist"
codesign --verify --deep --strict "$EXTRACTED_APP"
unzip -t "$ZIP"
HASH="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
printf '%s  CaptionGrab.zip\n' "$HASH" > "$ZIP.sha256"
printf 'Packaged and verified: %s\n' "$ZIP"
