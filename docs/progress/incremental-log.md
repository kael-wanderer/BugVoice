# Incremental transcription — Phase 1 execution log

## Built

- Task 1: streaming pause chunker, 8 specified tests passing. Full suite:
  1,281 VoiceCore, 30 MCPKit, 114 BugVoiceMac (1,425 total).
- Task 2: virtual-clock simulation, silent-part skipping, transcript cleanup,
  previous-part prompts and exact audio boundaries. 7 specified simulation tests
  passing; 15 chunker/simulation tests combined. Full suite: 1,288 VoiceCore,
  30 MCPKit, 114 BugVoiceMac (1,432 total).
- Both tasks first failed to compile because their implementation types were
  absent, then passed targeted tests and the full suite before commit.
- Task 3: medians, least-squares fit, clip grouping and deterministic gate
  failures. All 8 specified tests passed after the expected missing-type compile
  failure. Full suite: 1,296 VoiceCore, 30 MCPKit, 114 BugVoiceMac
  (1,440 total), all passed on the full rerun.
- Initial Task 3 full run: VoiceCore and MCPKit passed; existing macOS test
  `recoveryDropsUncheckpointedJournalTail` failed its 4-byte journal assertion.
  It passed in isolation and the unchanged full suite then passed. No change
  made to the journal test or implementation.

- Time-threshold review fix: the two supplied boundary tests failed first, then
  all 10 gate tests passed with the same 1e-9 tolerance as WER. Full suite:
  1,298 VoiceCore, 30 MCPKit, 114 BugVoiceMac (1,442 total), all passed.

- Task 4: default-on VAD chunking option. Supplied test failed to compile
  before implementation. Full suite: 1,299 VoiceCore, 30 MCPKit,
  114 BugVoiceMac (1,443 total), all passed. `swift build` succeeded.

- Task 5: six-section latency bench, 36-combination cached sweep, preview
  contention and automatic-language comparison. Release product build passed.
  Full suite: 1,299 VoiceCore, 30 MCPKit, 114 BugVoiceMac (1,443 total), all passed.

- Task 6: 18 additional corpus filenames and recording instructions, smoke
  results, owner-run command and key-document link. Full suite: 1,299 VoiceCore,
  30 MCPKit, 114 BugVoiceMac (1,443 total), all passed before the docs commit.
  Owner corpus, final gate decision and any Phase 2 plan remain pending.

- Fixed-cost fit review fix: removed the 1 s preset slice. Release rebuild
  and four-clip smoke rerun passed. Full suite: 1,299 VoiceCore, 30 MCPKit,
  114 BugVoiceMac (1,443 total), all passed before commit.

## Decisions

- Owner review: Section 1 uses 2, 4, 8, 15, 25 s slices and the whole clip.
  Drop the 1 s slice: WhisperKit's default 1 s clip window skips inference
  at that length, dragging the fitted fixed cost downward. Task 5's plan
  matches this change. The whole clip remains included as requested.

- Task 5 extends the planned file list with a cached-folder initializer in
  `WhisperKitTranscriber` and an offline inference boundary in `stt-bench.sh`.
  The latency runner resolves compiled models under `AppPaths.standard().models`
  and existing local tokenizer folders, validates tokenizers before loading,
  and never calls the model-download API. Missing assets fail the run.
- The latency script builds first, then executes inference with macOS
  `sandbox-exec` denying all network access. Wrapping SwiftPM itself failed
  because its manifest sandbox cannot nest; that attempt ran no inference.
- Fixed-cost slice lengths are deduplicated when the whole clip equals a
  listed slice, and the fit uses every per-clip median measurement.
- Full-clip text/WER comes from the median-timed run of each three-pass set.
  Complete ties between sweep combinations retain the first enumerated row.
- The preview model is prepared and warmed before contention timing. Each
  clip has a separate preview loop on its last 15 s, cancelled and drained
  before the next clip. Automatic-language baseline timing is measured anew.
- Other decoding options tried: none. Only the planned VAD lever is compared.

- Task 4: WhisperKit 1.1.1 declares `chunkingStrategy` optional; no chunking
  uses `nil`, per the plan. The app retains the default `vadChunking: true`.

- Owner correction to Task 3: buckets overlap deliberately. Every clip at least
  30 s is also in the 15 s+ bucket. The corrected `savingThresholds` fixture sets
  both English long-clip savings to 0.4 s, so both savings thresholds fail while
  Vietnamese remains passing. Updated the test and plan together; the gate
  rule and all other Task 3 test values are unchanged.
- WER and time comparisons use the owner-approved 1e-9 tolerance at limits.
- Least-squares fit returns (0, 0) for empty input and (mean y, 0) when all x
  values match; mismatched input lengths are a programmer precondition failure.

- Owner correction: pause midpoint uses integer division of pause frames;
  0.5 s gives 25 frames, half 12 frames, offset 3,840 samples. Task 1's plan
  and test updated together.
- Pause detection uses complete frames. Pause frames are
  `Int(pause * 16_000) / 320`, as directed by the owner.
- Forced-cut windows are scored by the sum of their ten frame RMS values;
  equal scores choose the earliest window. This gives deterministic streaming
  and batch results.
- Simulation keeps the last pass duration separate when calculating latency:
  `max(0, (start - release) + seconds)`. This is algebraically end minus release,
  while preserving the specified exact 1.2 s value for a tail starting at release.

## Smoke run

2026-10-24: `Scripts/stt-bench.sh --latency > /tmp/latency-smoke.md` exited 0
in 259.106496 s with network denied to inference. Four 15 s clips; all six
sections and 36 sweep rows present. Section 1 starts at 2 s; no 1 s slice
is timed or included in the fit. A distinctive reference word and all
five-word reference phrases have zero matches in stdout.

Existing clips en-1 and vi-1 are known unusable (docs/bench/2026-10-14-stt-bench.md); smoke numbers test plumbing only.

Only 1 of the 4 clips has a reference. The other 3 are excluded from WER.
The incomplete corpus and unusable clips cannot establish performance or
accuracy gates for Phase 2.

| Slice s | Median STT s | Clip measurements |
|---:|---:|---:|
| 2.000000 | 2.117195 | 4 |
| 4.000000 | 1.514146 | 4 |
| 8.000000 | 1.691622 | 4 |
| 15.000000 | 2.142076 | 4 |

fixed 1.729686 s + 0.019902 s per audio second

| Group | VAD | Clips | Median STT s | Mean WER |
|---|---|---:|---:|---:|
| en | on | 1 | 1.164331 | 1.000000 |
| vi | on | 1 | 1.833758 | – |
| mix | on | 2 | 2.855286 | – |
| en | off | 1 | 1.207751 | 1.000000 |
| vi | off | 1 | 1.788490 | – |
| mix | off | 2 | 2.603693 | – |

Other options tried: none

Best combination: Pause 0.300000 s; shortest 2.000000 s; longest 25.000000 s; previous text off.

Without preview (9 gate failures):

- en: missingBucket — no clips under 8 s
- en: missingBucket — no clips 30 s+
- en: saving too small, 15 s+: -1.980283 s
- vi: missingBucket — no clips under 8 s
- vi: missingBucket — no clips 30 s+
- vi: saving too small, 15 s+: 0.102417 s
- mix: missingBucket — no clips under 8 s
- mix: missingBucket — no clips 30 s+
- mix: saving too small, 15 s+: -1.778849 s

With preview (9 gate failures):

- en: missingBucket — no clips under 8 s
- en: missingBucket — no clips 30 s+
- en: saving too small, 15 s+: -0.057584 s
- vi: missingBucket — no clips under 8 s
- vi: missingBucket — no clips 30 s+
- vi: saving too small, 15 s+: -0.201277 s
- mix: missingBucket — no clips under 8 s
- mix: missingBucket — no clips 30 s+
- mix: saving too small, 15 s+: -0.286442 s

Automatic language is informational; gate not applied. Would-fail count: 9.

The complete report remains local at `/tmp/latency-smoke.md`; no transcript
text was printed, copied into this log, or committed.

## Synthetic run (2026-10-24, Claude, owner away)

The owner asked Claude to run the bench. Claude cannot record the owner's voice,
so the 18 clips were generated locally with macOS `say` (Ava Premium for English,
Linh for Vietnamese and mixed, 0.5 s silence between sentences), converted to
16 kHz mono with ffmpeg, with the spoken text as the reference. Generator:
`Scripts/make-synthetic-clips.py`. Old clips moved to `bench/clips/old-2026-10-14/`
(not read by the bench). Durations: 4.2–6.1 s (2 per group), 16.4–18.4 s (2 per
group), 32.1–36.9 s (2 per group). No microphone, app launch or paste.

    Scripts/stt-bench.sh --latency > docs/bench/2026-10-24-incremental-bench.md

Exit 0, 1,950 s. Report: `docs/bench/2026-10-24-incremental-bench.md`.

- Fixed cost: 1.17 s + 0.032 s per audio second.
- VAD lever: off is no faster (en 1.54 vs 1.54 s, vi 1.77 vs 1.76, mix 1.90 vs
  1.87) and WER is worse in every group. Does not ship.
- Best combination: pause 0.5 s, shortest part 2 s, longest 15 s, previous text
  off. Previous text in the prompt is worse in every combination.
- Tail after release stays about 1.1–1.4 s whatever the length.

| Group | under 8 s saving | 15 s+ saving | 30 s+ saving | 15 s+ WER change |
|---|---:|---:|---:|---:|
| en | 0.03 s | 0.59 s | **0.85 s** | +0.012 |
| vi | 0.04 s | 0.85 s | 1.18 s | +0.005 |
| mix | 0.15 s | 0.62 s | **0.88 s** | +0.015 |

With the preview model loop: en 30 s+ 0.97 s, mix 30 s+ **0.47 s** (mix-7 became
0.2 s slower than baseline), vi 1.21 s. Automatic language: savings similar, mixed
WER worse (+0.04 at 15 s+), 6 would-fail rows.

## Gate result

**Fails, narrowly, on synthetic speech.** Two failures without preview load
(en and mix 30 s+ save 0.85 and 0.88 s; the gate needs 1.0 s), two with it
(en 0.97 s, mix 0.47 s). Every other check passes: short dictations are not
slower, 15 s+ saves 0.59–0.85 s, WER within +0.02 per group and +0.05 per clip.

Caveats: synthetic speech has regular, clean pauses and no hesitation; real
dictation pauses less regularly. Six clips per group. Contention with the preview
model is uneven (one mixed clip lost its whole saving).

## Decision

Owner (2026-10-24): rerun on recorded clips first; if en and mix 30 s+ save at
least 0.8 s, lower that threshold to 0.8 s and plan Phase 2. Recording deferred
(`Scripts/record-bench-clips.sh`). Background: the 1.0 s threshold was Claude's (the owner skipped the design
questions). Options: drop as the spec says; rerun on owner-recorded clips; or
lower the 30 s+ threshold, accepting about 0.6–1.2 s saved on 15 s+ dictations
and a preview-contention risk that Phase 2 would need to handle.
