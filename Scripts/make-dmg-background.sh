#!/usr/bin/env bash
#
# Regenerate App/DMG/background.png (660x420) and background@2x.png (1320x840)
# from App/DMG/background.svg. Needs Google Chrome (headless render), like
# Scripts/make-app-icon.sh.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/bg.html" <<HTML
<!doctype html><html><body style="margin:0;background:#f6f6f8">
<img src="file://$PWD/App/DMG/background.svg" width="660" height="420" style="display:block">
</body></html>
HTML
render() { # scale output
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor="$1" \
        --window-size=660,420 --screenshot="$2" "file://$WORK/bg.html" >/dev/null 2>&1
}
render 1 "$PWD/App/DMG/background.png"
render 2 "$PWD/App/DMG/background@2x.png"
# Finder pairs the two by name; mark the 1x at 72 dpi and the 2x at 144 dpi.
sips -s dpiWidth 72 -s dpiHeight 72 App/DMG/background.png >/dev/null
sips -s dpiWidth 144 -s dpiHeight 144 App/DMG/background@2x.png >/dev/null
echo "Wrote App/DMG/background.png and background@2x.png"
