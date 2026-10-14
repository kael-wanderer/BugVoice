#!/usr/bin/env bash
#
# Regenerate App/AppIcon.icns from App/Icon/AppIcon.svg.
# Needs Google Chrome (headless render) plus the built-in sips and iconutil.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/icon.html" <<HTML
<!doctype html><html><body style="margin:0;background:transparent">
<img src="file://$PWD/App/Icon/AppIcon.svg" width="1024" height="1024" style="display:block">
</body></html>
HTML
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color=00000000 --window-size=1024,1024 \
    --screenshot="$WORK/icon_1024.png" "file://$WORK/icon.html" >/dev/null 2>&1

SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$WORK/icon_1024.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$WORK/icon_1024.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o App/AppIcon.icns
echo "Wrote App/AppIcon.icns"
