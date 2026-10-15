#!/usr/bin/env bash
#
# Restart build/BugVoice.app for a development run.
#
# With two displays its windows open on the one that is not primary (the
# display with the menu bar), so agents' runs stay off the owner's work; with
# one display they open as usual. BUGVOICE_DEV_SCREEN=primary keeps them on
# the primary display. Build first with Scripts/build-app.sh.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
APP="$PWD/build/BugVoice.app"

if [[ ! -d "$APP" ]]; then
    echo "error: $APP not found. Run Scripts/build-app.sh first." >&2
    exit 1
fi

pkill -f "BugVoice.app/Contents/MacOS/BugVoice" || true
# Wait for the old process to exit so `open` launches a new one with the env.
for _ in {1..50}; do
    pgrep -f "BugVoice.app/Contents/MacOS/BugVoice" >/dev/null || break
    sleep 0.1
done
open --env "BUGVOICE_DEV_SCREEN=${BUGVOICE_DEV_SCREEN:-second}" "$APP"
