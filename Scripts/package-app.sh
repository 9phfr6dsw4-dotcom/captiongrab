#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/CaptionGrab.app"
ZIP="dist/CaptionGrab.zip"
EXTRACTED="dist/verify-extracted"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Resources/ChromeExtension" "$EXTRACTED"

MACOSX_DEPLOYMENT_TARGET=26.0 swift build -c release --product CaptionGrab
MACOSX_DEPLOYMENT_TARGET=26.0 swift build -c release --product CaptionGrabNativeHost
install -m 755 .build/release/CaptionGrab "$APP/Contents/MacOS/CaptionGrab"
install -m 755 .build/release/CaptionGrabNativeHost "$APP/Contents/MacOS/CaptionGrabNativeHost"
cp -R ChromeExtension/. "$APP/Contents/Resources/ChromeExtension/"
python3 Scripts/test-native-host.py "$APP/Contents/MacOS/CaptionGrabNativeHost"
test -x "$APP/Contents/MacOS/CaptionGrabNativeHost"
test -f "$APP/Contents/Resources/ChromeExtension/manifest.json"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift Scripts/generate_icon.swift "$APP/Contents/Resources/CaptionGrab.iconset"
iconutil -c icns "$APP/Contents/Resources/CaptionGrab.iconset" -o "$APP/Contents/Resources/CaptionGrab.icns"
rm -rf "$APP/Contents/Resources/CaptionGrab.iconset"

plutil -lint "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist" | grep -Fx '26.0'
codesign --force --sign - "$APP/Contents/MacOS/CaptionGrabNativeHost"
codesign --force --sign - --entitlements Resources/CaptionGrab.entitlements "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
ditto -x -k "$ZIP" "$EXTRACTED"
EXTRACTED_APP="$EXTRACTED/CaptionGrab.app"
test -x "$EXTRACTED_APP/Contents/MacOS/CaptionGrab"
test -x "$EXTRACTED_APP/Contents/MacOS/CaptionGrabNativeHost"
test -f "$EXTRACTED_APP/Contents/Resources/ChromeExtension/manifest.json"
diff -qr ChromeExtension "$EXTRACTED_APP/Contents/Resources/ChromeExtension"
plutil -lint "$EXTRACTED_APP/Contents/Info.plist"
codesign --verify --deep --strict "$EXTRACTED_APP"
codesign --verify --strict "$EXTRACTED_APP/Contents/MacOS/CaptionGrabNativeHost"
unzip -t "$ZIP"
HASH="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
printf '%s  CaptionGrab.zip\n' "$HASH" > "$ZIP.sha256"
printf 'Packaged and verified: %s\n' "$ZIP"
