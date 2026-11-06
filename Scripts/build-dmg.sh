#!/usr/bin/env bash
#
# Build build/BugVoice-<version>-<build>.dmg: the signed app, an Applications
# shortcut, "Read Me First.pdf", and a Finder window laid out with the drag
# arrow and the two ways past the "Not Opened" block (App/DMG/).
#
# The layout is set through Finder AppleScript on a read-write image, so the
# first run may ask to allow Terminal under Privacy & Security > Automation.
#
# Version and build number come from App/Info.plist
# (CFBundleShortVersionString and CFBundleVersion); bump them there.
# SKIP_BUILD=1 packages the existing build/BugVoice.app without rebuilding.
#
# The app is signed with the local "Bugler Local Dev" identity, not an Apple
# Developer ID, so Gatekeeper blocks it on other Macs until the user allows it.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"

APP_NAME="BugVoice"
APP="$ROOT/build/$APP_NAME.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT/App/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$ROOT/App/Info.plist")"
DMG="$ROOT/build/$APP_NAME-$VERSION-$BUILD.dmg"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    "$ROOT/Scripts/build-app.sh"
fi
if [[ ! -d "$APP" ]]; then
    echo "error: $APP not found. Run Scripts/build-app.sh first." >&2
    exit 1
fi

# The bundle must carry the version this DMG is named after.
APP_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
APP_BUILD="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")"
if [[ "$APP_VERSION" != "$VERSION" || "$APP_BUILD" != "$BUILD" ]]; then
    echo "error: $APP is $APP_VERSION ($APP_BUILD), App/Info.plist says $VERSION ($BUILD). Rebuild without SKIP_BUILD." >&2
    exit 1
fi
codesign --verify --strict "$APP"

VOLNAME="$APP_NAME $VERSION"
DMG_ASSETS="$ROOT/App/DMG"
for f in background.png "background@2x.png" "Read Me First.pdf"; do
    [[ -f "$DMG_ASSETS/$f" ]] || { echo "error: $DMG_ASSETS/$f missing. Run Scripts/make-dmg-background.sh and Scripts/make-dmg-readme.sh." >&2; exit 1; }
done

WORK="$(mktemp -d)"
STAGING="$WORK/staging"
RW="$WORK/rw.dmg"
MOUNT=""
cleanup() {
    if [[ -n "$MOUNT" ]]; then
        hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || hdiutil detach "$MOUNT" -force -quiet >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$STAGING/.background"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp "$DMG_ASSETS/Read Me First.pdf" "$STAGING/"
# One TIFF holds the 1x and 2x pictures so Finder picks the sharp one on Retina.
tiffutil -cathidpicheck "$DMG_ASSETS/background.png" "$DMG_ASSETS/background@2x.png" \
    -out "$STAGING/.background/background.tiff" >/dev/null 2>&1

# Read-write image with headroom: Finder writes .DS_Store when the layout is set.
SIZE_MB=$(( $(du -sk "$STAGING" | cut -f1) / 1024 + 30 ))
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -size "${SIZE_MB}m" -ov "$RW" >/dev/null 2>&1
ATTACH="$(hdiutil attach "$RW" -readwrite -noverify -noautoopen)"
MOUNT="$(printf '%s\n' "$ATTACH" | awk -F'\t' '/\/Volumes\//{print $NF}' | head -n1)"
if [[ -z "$MOUNT" || ! -d "$MOUNT" ]]; then
    echo "error: could not mount the read-write image." >&2
    exit 1
fi
chflags hidden "$MOUNT/.background" 2>/dev/null || true

# Window content is 660x420 (the background size); bounds add the 28pt title bar.
if ! osascript >/dev/null 2>&1 <<OSA
tell application "Finder"
    tell disk "$VOLNAME"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 568}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 96
        set text size of opts to 12
        set background picture of opts to file ".background:background.tiff"
        set position of item "$APP_NAME.app" of container window to {165, 150}
        set position of item "Applications" of container window to {495, 150}
        set position of item "Read Me First.pdf" of container window to {330, 330}
        update without registering applications
        delay 2
        close
    end tell
end tell
OSA
then
    echo "Finder automation is needed to lay out the DMG. Allow Terminal under Privacy & Security › Automation." >&2
    exit 1
fi

sync
hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || { sleep 2; hdiutil detach "$MOUNT" -force -quiet >/dev/null; }
MOUNT=""

rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null 2>&1
hdiutil verify "$DMG" >/dev/null
echo "Built $DMG ($VERSION build $BUILD)"
