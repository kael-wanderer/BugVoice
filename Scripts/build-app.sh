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
# App Intents metadata requires full Xcode; the app still packages without it.
XCODE_DEVELOPER="${BUGVOICE_XCODE_DEVELOPER:-/Applications/Xcode.app/Contents/Developer}"
if PROCESSOR="$(DEVELOPER_DIR="$XCODE_DEVELOPER" xcrun --find appintentsmetadataprocessor 2>/dev/null)"; then
    METADATA_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bugvoice-appintents.XXXXXX")"
    trap 'rm -rf "$METADATA_TEMP"' EXIT
    rg --files "$ROOT/Sources/BugVoice" -g '*.swift' | sort > "$METADATA_TEMP/sources.txt"
    # Match only this product, configuration and architecture, excluding tests
    # and stale sanitizer outputs from other builds.
    { rg --files --hidden --no-ignore "$ROOT/.build/out/Intermediates.noindex/BugVoice.build" -g '*.swiftconstvalues' || [[ $? == 1 ]]; } |
        awk -F/ -v config="$CONFIGURATION" '
            tolower($(NF-4)) == tolower(config) && $(NF-3) == "BugVoice-p.build" &&
            $(NF-2) == "Objects-normal" && $(NF-1) == "arm64" { print }
        ' > "$METADATA_TEMP/const-values.txt"
    if [[ ! -s "$METADATA_TEMP/const-values.txt" ]]; then
        echo "error: no BugVoice .swiftconstvalues files found for $CONFIGURATION (arm64)" >&2
        exit 1
    fi
    SDK_ROOT="$(DEVELOPER_DIR="$XCODE_DEVELOPER" xcrun --sdk macosx --show-sdk-path)"
    XCODE_VERSION="$(DEVELOPER_DIR="$XCODE_DEVELOPER" xcodebuild -version | awk '/Build version/ { print $3 }')"
    "$PROCESSOR" --output "$METADATA_TEMP/output" \
        --toolchain-dir "$XCODE_DEVELOPER/Toolchains/XcodeDefault.xctoolchain" \
        --module-name "$APP_NAME" --sdk-root "$SDK_ROOT" --xcode-version "$XCODE_VERSION" \
        --platform-family macOS --deployment-target 15.0 --target-triple arm64-apple-macos15.0 \
        --source-file-list "$METADATA_TEMP/sources.txt" --swift-const-vals-list "$METADATA_TEMP/const-values.txt" \
        --binary-file "$BIN/$APP_NAME"
    cp -R "$METADATA_TEMP/output/Metadata.appintents" "$CONTENTS/Resources/"
    rm -rf "$METADATA_TEMP"
    trap - EXIT
else
    echo "Skipping Shortcuts metadata: Xcode not found"
fi
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
