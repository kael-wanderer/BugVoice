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
    find "$ROOT/Sources/BugVoice" -name '*.swift' -type f | sort > "$METADATA_TEMP/sources.txt"
    # Match only this product, configuration and architecture, excluding tests
    # and stale sanitizer outputs from other builds.
    { find "$ROOT/.build/out/Intermediates.noindex/BugVoice.build" -name '*.swiftconstvalues' -type f 2>/dev/null || true; } |
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
# Pinned llama.cpp server for the built-in cleanup model. Only llama-server and
# the dylibs it links (all @rpath, resolved through its @loader_path rpath) go in.
LLAMA_DIR="$("$ROOT/Scripts/fetch-llama-server.sh" | tail -n 1)"
LLAMA_DIR="$ROOT/$(dirname "$LLAMA_DIR")"
HELPERS="$CONTENTS/Helpers"
mkdir -p "$HELPERS"
cp "$LLAMA_DIR/llama-server" "$HELPERS/llama-server"
for lib in libllama-server-impl.dylib libllama-common.0.dylib libmtmd.0.dylib libllama.0.dylib \
           libggml.0.dylib libggml-cpu.0.dylib libggml-blas.0.dylib libggml-metal.0.dylib \
           libggml-rpc.0.dylib libggml-base.0.dylib; do
    cp -L "$LLAMA_DIR/$lib" "$HELPERS/$lib"   # -L: the .0 names are symlinks to versioned files
done
# The list above is fixed: fail if the helper or a copied dylib links an
# @rpath library that is not in Helpers (a new llama.cpp release may add one).
MISSING_LIBS=""
for item in "$HELPERS/llama-server" "$HELPERS"/*.dylib; do
    DEPS="$(otool -L "$item" | awk 'NR > 1 && $1 ~ /^@rpath\// { print $1 }')"
    while IFS= read -r dep; do
        [[ -n "$dep" ]] || continue
        name="${dep#@rpath/}"
        [[ -f "$HELPERS/$name" ]] || MISSING_LIBS="$MISSING_LIBS $name (linked by $(basename "$item"))"
    done <<< "$DEPS"
done
if [[ -n "$MISSING_LIBS" ]]; then
    echo "error: Contents/Helpers lacks libraries llama-server needs:$MISSING_LIBS" >&2
    echo "Add them to the dylib list in Scripts/build-app.sh." >&2
    exit 1
fi
xattr -cr "$HELPERS"
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
    # No --options runtime here: with it, library validation rejects the dylibs
    # ("different Team IDs", the identity has no Team ID) and llama-server fails to start.
    for item in "$HELPERS"/*.dylib "$HELPERS/llama-server"; do
        codesign --force --timestamp=none --sign "$IDENTITY" "$item"
    done
    codesign --force --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP_DIR"
    echo "Signed with: $IDENTITY"
else
    codesign --force --sign - "$CONTENTS/MacOS/bugvoice-mcp"
    for item in "$HELPERS"/*.dylib "$HELPERS/llama-server"; do codesign --force --sign - "$item"; done
    codesign --force --entitlements "$ENTITLEMENTS" --sign - "$APP_DIR"
    echo "ALLOW_ADHOC=1: signed ad hoc. Permissions will be asked again after each build."
fi
codesign --verify --strict "$APP_DIR"
echo "Built $APP_DIR"
