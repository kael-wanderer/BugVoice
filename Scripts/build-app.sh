#!/usr/bin/env bash
#
# Assemble build/BugVoice.app from the Swift package and sign it.
#
# Signing uses the stable "Bugler Local Dev" identity. macOS ties Microphone,
# Accessibility and Input Monitoring grants to the signature, so an ad hoc
# signature (new every build) would ask for all three again each time. If the
# identity is missing the build fails; set ALLOW_ADHOC=1 to sign ad hoc anyway.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"

CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="BugVoice"
APP_DIR="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
SIGNING_NAME="Bugler Local Dev"

# Resolve the identity before building so a missing one fails fast.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' -v name="$SIGNING_NAME" '$2 == name {print $2; exit}')}"
if [[ -z "$IDENTITY" && "${ALLOW_ADHOC:-0}" != "1" ]]; then
    echo "error: signing identity \"$SIGNING_NAME\" not found in the keychain." >&2
    echo "       An ad hoc signature resets Microphone, Accessibility and Input Monitoring grants on every build." >&2
    echo "       Install the identity, set CODESIGN_IDENTITY, or rerun with ALLOW_ADHOC=1 to sign ad hoc." >&2
    exit 1
fi

FLAGS=()
if [ "$CONFIGURATION" = "release" ]; then
    # Apple and WhisperKit callbacks can arrive off the executor their
    # declarations promise; the dynamic check traps instead of recovering.
    # `swift build`/`swift test` keep it on to catch our own mistakes.
    FLAGS+=(-Xswiftc -disable-dynamic-actor-isolation)
fi

swift build -c "$CONFIGURATION" --arch arm64 "${FLAGS[@]+"${FLAGS[@]}"}" --product "$APP_NAME"
swift build -c "$CONFIGURATION" --arch arm64 "${FLAGS[@]+"${FLAGS[@]}"}" --product bugvoice-mcp
BIN="$(swift build -c "$CONFIGURATION" --arch arm64 "${FLAGS[@]+"${FLAGS[@]}"}" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
# The MCP bridge agents start; it finds the app three folders up from itself.
cp "$BIN/bugvoice-mcp" "$CONTENTS/MacOS/bugvoice-mcp"
cp "$ROOT/App/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/App/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
for resource in Icons MenuBarIcons Fonts; do
    if [[ -d "$ROOT/App/$resource" ]]; then
        cp -R "$ROOT/App/$resource" "$CONTENTS/Resources/"
    fi
done
printf 'APPL????'  > "$CONTENTS/PkgInfo"
for bundle in "$BIN"/*.bundle; do
    if [[ -d "$bundle" ]]; then cp -R "$bundle" "$CONTENTS/Resources/"; fi
done

ENTITLEMENTS="$ROOT/App/$APP_NAME.entitlements"
# Nested code is signed before the bundle so the bundle signature covers it.
if [[ -n "$IDENTITY" ]]; then
    codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$CONTENTS/MacOS/bugvoice-mcp"
    codesign --force --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP_DIR"
    echo "Signed with: $IDENTITY"
else
    codesign --force --sign - "$CONTENTS/MacOS/bugvoice-mcp"
    codesign --force --entitlements "$ENTITLEMENTS" --sign - "$APP_DIR"
    echo "ALLOW_ADHOC=1: signed ad hoc. Permissions will be asked again after each build."
fi
codesign --verify --strict "$APP_DIR"
echo "Built $APP_DIR"
