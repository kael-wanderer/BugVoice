# Benchmark clips

Recordings here are personal and gitignored. Put ~6 clips here:

| File | Content |
|---|---|
| `en-1.wav`, `en-2.wav` | English, 8–15 s each, one technical (a prompt for a coding agent) |
| `vi-1.wav`, `vi-2.wav` | Vietnamese, 8–15 s each |
| `mix-1.wav`, `mix-2.wav` | Vietnamese with English technical words, 8–15 s each |

For each clip write the exact words you said in `name.txt` (same name).

Record from the default microphone (Ctrl-C to stop early):

    ffmpeg -f avfoundation -i ":0" -ac 1 -ar 16000 -t 15 bench/clips/en-1.wav

Then run `Scripts/stt-bench.sh > docs/bench/$(date +%F)-stt-bench.md`.
