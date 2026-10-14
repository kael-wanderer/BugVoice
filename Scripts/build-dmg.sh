#!/usr/bin/env bash
#
# Build build/BugVoice-<version>-<build>.dmg: the signed app plus an
# Applications shortcut for drag-to-install.
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

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
echo "Built $DMG ($VERSION build $BUILD)"
