#!/usr/bin/env bash
#
# Download the pinned llama.cpp macOS arm64 build into build/cache/, verify its
# SHA-256 against Scripts/llama-server.env, and unpack it to
# build/cache/llama-$LLAMA_TAG/. A file that fails the hash is deleted.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=llama-server.env
source Scripts/llama-server.env
: "${LLAMA_TAG:?}" "${LLAMA_ASSET:?}" "${LLAMA_ZIP_SHA256:?}"

CACHE=build/cache
ARCHIVE="$CACHE/$LLAMA_ASSET"
DEST="$CACHE/llama-$LLAMA_TAG"
URL="https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_TAG/$LLAMA_ASSET"
mkdir -p "$CACHE"

verify() { [[ "$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)" == "$LLAMA_ZIP_SHA256" ]]; }

if [[ -f "$ARCHIVE" ]] && ! verify; then
    echo "Cached archive does not match the pinned hash; downloading again." >&2
    rm -f "$ARCHIVE"
fi
if [[ ! -f "$ARCHIVE" ]]; then
    curl -fsSL --proto '=https' --tlsv1.2 -o "$ARCHIVE.part" "$URL"
    mv "$ARCHIVE.part" "$ARCHIVE"
    if ! verify; then
        rm -f "$ARCHIVE"
        echo "SHA-256 mismatch for $LLAMA_ASSET. File deleted." >&2
        exit 1
    fi
fi

# Refuse archives with absolute paths or parent-directory entries.
if tar -tzf "$ARCHIVE" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    echo "Archive contains unsafe paths. Not unpacking." >&2
    exit 1
fi
WORK="$(mktemp -d "$CACHE/unpack.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
tar -xzf "$ARCHIVE" -C "$WORK"
[[ -x "$WORK/llama-$LLAMA_TAG/llama-server" ]] || { echo "llama-server missing from archive." >&2; exit 1; }
rm -rf "$DEST"
mv "$WORK/llama-$LLAMA_TAG" "$DEST"
echo "$DEST/llama-server"
