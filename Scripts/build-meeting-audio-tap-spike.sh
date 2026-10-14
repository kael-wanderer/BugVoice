#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/.build/MeetingAudioTapSpike.app"
CONTENTS="$APP_DIR/Contents"
EXECUTABLE="$CONTENTS/MacOS/MeetingAudioTapSpike"
SIGNING_NAME="Bugler Local Dev"
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' -v name="$SIGNING_NAME" '$2 == name {print $2; exit}')}"

if [[ -z "$IDENTITY" ]]; then
    echo "Signing identity '$SIGNING_NAME' was not found; refusing to sign ad hoc." >&2
    exit 1
fi

mkdir -p "$CONTENTS/MacOS"
swiftc "$ROOT/Scripts/meeting-audio-tap-spike.swift" -o "$EXECUTABLE" -framework CoreAudio -framework Foundation
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MeetingAudioTapSpike</string>
    <key>CFBundleIdentifier</key><string>com.bugvoice.meeting-audio-tap-spike</string>
    <key>CFBundleName</key><string>Meeting Audio Tap Spike</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    <key>NSAudioCaptureUsageDescription</key>
    <string>BugVoice tests system audio capture for meeting recording.</string>
</dict>
</plist>
PLIST
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP_DIR"
codesign --verify --strict "$APP_DIR"
echo "Built and signed $APP_DIR with $IDENTITY. It has not been launched."
