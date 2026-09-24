#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/verify-extracted/CaptionGrab.app"
test -x "$APP/Contents/MacOS/CaptionGrab"
open -n "$APP"
for attempt in {1..10}; do
    if pgrep -x CaptionGrab >/dev/null; then
        pkill -x CaptionGrab || true
        printf 'Launch smoke test passed.\n'
        exit 0
    fi
    sleep 1
done
printf 'CaptionGrab did not appear as a running process after launch.\n' >&2
exit 1
