#!/usr/bin/env bash
# Records the owner reading the long bench clips (en-6, en-7, vi-6, vi-7, mix-7, mix-8).
# Each clip's text is its existing reference bench/clips/<name>.txt; the
# recording replaces bench/clips/<name>.wav (the synthetic copy is kept in
# bench/clips/synthetic/). Run in your own terminal: the first run asks for
# microphone access. Local only; clips stay gitignored.
# Usage: Scripts/record-bench-clips.sh [names...]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../bench/clips"
names=("$@")
[[ ${#names[@]} -gt 0 ]] || names=(en-6 en-7 vi-6 vi-7 mix-7 mix-8)
mkdir -p synthetic
i=0
while (( i < ${#names[@]} )); do
    name=${names[i]}
    [[ -f "$name.txt" ]] || { echo "Missing $name.txt; run Scripts/make-synthetic-clips.py first." >&2; exit 1; }
    [[ -f "$name.wav" && ! -f "synthetic/$name.wav" ]] && cp "$name.wav" "synthetic/$name.wav"
    clear
    echo "== $name =="
    echo
    fold -s -w 80 "$name.txt"
    echo
    echo "Read at your normal dictation pace, pausing where you naturally would."
    read -r -p "Press Enter to start recording… "
    ffmpeg -loglevel error -y -f avfoundation -i ":0" -ac 1 -ar 16000 -c:a pcm_s16le "$name.recording.wav" &
    pid=$!
    read -r -p "Recording. Press Enter when you finish… "
    kill -INT "$pid"; wait "$pid" || true
    mv "$name.recording.wav" "$name.wav"
    printf "Saved %s.wav (%.1f s)\n" "$name" "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$name.wav")"
    read -r -p "Enter for the next clip, r + Enter to redo this one… " again
    [[ "$again" == "r" ]] || i=$((i + 1))
done
echo "Done. Tell Claude to run the bench."
