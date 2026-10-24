# Benchmark clips

Recordings and their `.txt` references are personal and gitignored. The existing
four clips are `en-1.wav`, `vi-1.wav`, `mix-1.wav`, and `mix-2.wav` (15 s each).
Keep those and record these 18 additional clips for the incremental latency gate:

| Group | Target length | New files |
|---|---:|---|
| English | 6 s | `en-2.wav`, `en-3.wav` |
| English | 15 s | `en-4.wav`, `en-5.wav` |
| English | 40 s | `en-6.wav`, `en-7.wav` |
| Vietnamese | 6 s | `vi-2.wav`, `vi-3.wav` |
| Vietnamese | 15 s | `vi-4.wav`, `vi-5.wav` |
| Vietnamese | 40 s | `vi-6.wav`, `vi-7.wav` |
| Mixed Vietnamese and English | 6 s | `mix-3.wav`, `mix-4.wav` |
| Mixed Vietnamese and English | 15 s | `mix-5.wav`, `mix-6.wav` |
| Mixed Vietnamese and English | 40 s | `mix-7.wav`, `mix-8.wav` |

Speak naturally, including pauses. In each group, at least one 40 s clip must be
a prompt for a coding agent with paths and identifiers. For every clip write the
exact words spoken in `name.txt`, matching the audio file's stem. Missing
references are timed but excluded from WER checks.

Record from the default microphone (Ctrl-C to stop early; use 6 or 15 for shorter
clips):

    ffmpeg -f avfoundation -i ":0" -ac 1 -ar 16000 -t 40 bench/clips/en-6.wav

Run the latency bench after recording; the main turbo and preview base models
and their tokenizers must already be cached. The script denies network access
to latency inference and does not download missing assets:

    Scripts/stt-bench.sh --latency > docs/bench/$(date +%F)-incremental-bench.md

The report uses each clip's actual duration. Buckets overlap: every 30 s+ clip
also counts in 15 s+. Each language group needs clips under 8 s, at least 15 s,
and at least 30 s. The four existing clips alone cannot pass the corpus gate.

Latency stdout contains metrics only. `--show-text` explicitly sends baseline
and incremental transcripts to stderr; keep that output local and uncommitted.
The owner reviews the complete-corpus gate with and without preview load before
any Phase 2 plan.

The original full speech-to-text and cleanup bench remains available:

    Scripts/stt-bench.sh > docs/bench/$(date +%F)-stt-bench.md

That original mode includes transcripts in its report; keep it local.

No time to record? `Scripts/make-synthetic-clips.py` generates the 18 clips with macOS `say` (timing evidence only; WER is optimistic).
