#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_REF:-}" != "refs/heads/main" ]]; then
  printf '%s\n' 'Refusing capture: only workflow_dispatch on main is allowed.' >&2
  exit 2
fi
: "${RUNNER_TEMP:?RUNNER_TEMP must be set by GitHub Actions}"
: "${CAPTIONGRAB_VIDEO_URL:?Provide a public synthetic English-captioned YouTube video URL}"

unset GH_TOKEN GITHUB_TOKEN

RELEASE_TAG='v1.2.17'
RELEASE_COMMIT='ab7c032d26988dd249e2ae6a535eac6aa16f00f2'
EXPECTED_SHA256='58cf95c311c02e316e80141ad7437f300ac58f5f3fedfd7985ca694cc8efe8a7'
RELEASE_BASE='https://github.com/9phfr6dsw4-dotcom/captiongrab/releases/download/v1.2.17'
API_BASE='https://api.github.com/repos/9phfr6dsw4-dotcom/captiongrab'

TEMP_ROOT="$(cd "$RUNNER_TEMP" && pwd -P)"
CAPTURE_ROOT="$TEMP_ROOT/captiongrab-readme"
if [[ -L "$CAPTURE_ROOT" ]]; then
  printf '%s\n' 'Refusing to write through a symlink in RUNNER_TEMP.' >&2
  exit 2
fi
rm -rf "$CAPTURE_ROOT"
mkdir -p "$CAPTURE_ROOT/download" "$CAPTURE_ROOT/extracted" "$CAPTURE_ROOT/home/Library" "$CAPTURE_ROOT/cache"
export HOME="$CAPTURE_ROOT/home"
export XDG_CACHE_HOME="$CAPTURE_ROOT/cache"

VIDEO_URL="$(python3 Scripts/validate_youtube_video_url.py)"
unset CAPTIONGRAB_VIDEO_URL
VIDEO_ID="${VIDEO_URL##*v=}"

printf '%s\n' 'Verifying the public v1.2.17 release commit and downloading its pinned assets.'
curl --fail --location --silent --show-error \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2022-11-28' \
  "$API_BASE/commits/$RELEASE_TAG" \
  --output "$CAPTURE_ROOT/release-commit.json"
python3 - "$CAPTURE_ROOT/release-commit.json" "$RELEASE_COMMIT" <<'PY'
import json
import sys
from pathlib import Path

actual = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")).get("sha")
if actual != sys.argv[2]:
    raise SystemExit("Release tag does not resolve to the expected v1.2.17 commit.")
PY

curl --fail --location --silent --show-error --retry 2 \
  "$RELEASE_BASE/CaptionGrab.zip" \
  --output "$CAPTURE_ROOT/download/CaptionGrab.zip"
curl --fail --location --silent --show-error --retry 2 \
  "$RELEASE_BASE/CaptionGrab.zip.sha256" \
  --output "$CAPTURE_ROOT/download/CaptionGrab.zip.sha256"
printf '%s  CaptionGrab.zip\n' "$EXPECTED_SHA256" > "$CAPTURE_ROOT/expected.sha256"
cmp -s "$CAPTURE_ROOT/expected.sha256" "$CAPTURE_ROOT/download/CaptionGrab.zip.sha256"
(
  cd "$CAPTURE_ROOT/download"
  shasum -a 256 -c CaptionGrab.zip.sha256
)
ACTUAL_SHA256="$(shasum -a 256 "$CAPTURE_ROOT/download/CaptionGrab.zip" | cut -d ' ' -f 1)"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  printf '%s\n' 'Downloaded release ZIP does not match the pinned SHA-256.' >&2
  exit 1
fi

ditto -x -k "$CAPTURE_ROOT/download/CaptionGrab.zip" "$CAPTURE_ROOT/extracted"
APP_PATH="$CAPTURE_ROOT/extracted/CaptionGrab.app"
[[ -d "$APP_PATH" ]]
[[ -x "$APP_PATH/Contents/MacOS/CaptionGrab" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")" == 'com.captiongrab.app' ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")" == '1.2.17' ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")" == '21' ]]
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP_PATH/Contents/Info.plist")"
[[ "$ICON_NAME" == *.icns ]] || ICON_NAME="$ICON_NAME.icns"
[[ -s "$APP_PATH/Contents/Resources/$ICON_NAME" ]]
codesign --verify --deep --strict "$APP_PATH"
swiftc Scripts/verify-and-capture-readme-window.swift \
  -framework AppKit \
  -framework CoreGraphics \
  -framework ImageIO \
  -framework Vision \
  -o "$CAPTURE_ROOT/verify-window"

printf '%s\n' 'Launching the verified release app and submitting the public video URL with Return.'
unset GH_TOKEN GITHUB_TOKEN
open "$APP_PATH"
sleep 3
osascript Scripts/submit-readme-video.applescript "$VIDEO_URL"

ACCESSIBILITY_TEXT="$(osascript Scripts/wait-for-readme-transcript.applescript "$VIDEO_ID")"
printf '%s' "$ACCESSIBILITY_TEXT" | python3 Scripts/verify_transcript_accessibility.py "$VIDEO_ID"
unset ACCESSIBILITY_TEXT

"$CAPTURE_ROOT/verify-window" \
  "$APP_PATH" \
  "$VIDEO_ID" \
  "$CAPTURE_ROOT/captiongrab-window.png"

[[ -s "$CAPTURE_ROOT/captiongrab-window.png" ]]
file "$CAPTURE_ROOT/captiongrab-window.png"
printf 'Fresh app-window capture saved to %s\n' "$CAPTURE_ROOT/captiongrab-window.png"
