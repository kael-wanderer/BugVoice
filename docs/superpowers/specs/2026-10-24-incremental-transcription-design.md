# Incremental transcription

Date: 2026-10-24. Status: draft for owner review.
Mockup: `docs/design/proposal-incremental.html`.
Follows: `docs/research/2026-10-24-feature-review.md` item 1 (Faster final
dictation through incremental transcription), picked by the owner on
2026-10-24. The owner skipped the design questions; every choice below not
stated by the owner or the review is marked **(my call)**.

## Why

After the owner releases the hotkey, BugVoice transcribes the whole
recording with the main Whisper model, then cleans it, then pastes. Speech
to text is the biggest part of the wait. The owner's local history
(17 dictations on 2026-10-24, durations and timings only):

| Recording | Dictations | Speech to text, median |
|---|---:|---:|
| under 5 s | 6 | 1.26 s |
| 5–10 s | 4 | 1.34 s |
| 10–20 s | 3 | 1.48 s |
| 20–40 s | 3 | 1.72 s |
| 40 s and longer | 1 | 3.04 s |

Median recording is about 10 s. Two things follow:

1. **Most of the wait does not depend on length.** A 2 s clip already costs
   about 1.2 s. Whisper pads every clip to a 30 s window and runs the encoder
   on the whole window, so a short tail pass after release likely pays most
   of that fixed cost too. If so, transcribing early parts while the owner
   speaks saves only the length-dependent part: roughly 0.2 s on a median
   dictation, 0.5 s at 20–40 s, and close to 2 s past 30 s (a second
   window).
2. **Long dictations are where it pays.** Prompts for coding agents and
   Notion paragraphs are the long ones, and the wait grows with them.

So this spec has two phases. Phase 1 measures, with no app change, where
the 1.2 s goes and what incremental transcription would really save, next
to cheaper changes. Phase 2 builds incremental transcription only if
Phase 1 passes the gate below. The review asked for exactly this: measure
tail latency and English, Vietnamese and mixed accuracy before choosing a
design.

## Goal

Paste long dictations sooner without making the text worse.

Success looks like:

1. On dictations of 15 s or more, release to transcript drops by at least
   0.5 s at the median, and on 30 s or more by at least 1.0 s.
2. Word error rate (WER) on the bench corpus gets worse by at most 0.02
   in each language group (English, Vietnamese, mixed), and no single clip
   gets worse by more than 0.05.
3. Dictations under 8 s are no slower than today (within 0.05 s).

## Non-goals

- Changing the live preview. It stays display-only on its own
  `openai_whisper-base` model. Showing main-model text in the preview card
  is a possible follow-up, not part of this.
- Streaming the cleanup model. Cleanup runs once on the whole transcript
  after release, as today.
- Command mode (its instructions are short), Ask AI, meetings (they already
  transcribe in chunks), and the OpenAI-compatible speech engine.
- A new dependency or a WhisperKit upgrade. WhisperKit stays pinned at
  1.1.1.
- WhisperKit's `AudioStreamTranscriber`. It owns the microphone and
  confirms segments by timestamps. WhisperKit 1.1.1 returns empty text when
  a forced language is combined with timestamps
  (`WhisperKitTranscriber.transcribe`), and dictation forces the language.

## Anti-goals

The feature fails, even if it works, when:

- The final text gets worse in Vietnamese or mixed speech: diacritics lost,
  English technical words split or misheard at a cut.
- Words at a cut point are dropped or doubled.
- Short dictations get slower: they are most of the use.
- The owner's other work slows down: fans, a laggy Mac, or a live preview
  that stutters because both models compete for the GPU.
- Dictated text goes anywhere new. Bench reports and Diagnostics carry
  numbers, never words.

## Phase 1: measure

A new bench mode, `bugvoice-bench --latency --clips bench/clips`, in
`Sources/BugVoiceBench`. It runs on the owner's Mac against local clips and
the cached `large-v3-v20240930_turbo` model. No microphone, no app launch,
no paste, nothing sent off the Mac.

### Corpus

The four existing clips (`en-1`, `mix-1`, `mix-2`, `vi-1`, 15 s each) are
too few and too short. The owner records 18 more into `bench/clips`
(gitignored), each with a `name.txt` reference:

| Group | 6 s | 15 s | 40 s |
|---|---|---|---|
| English (`en-`) | 2 | 2 | 2 |
| Vietnamese (`vi-`) | 2 | 2 | 2 |
| Mixed (`mix-`) | 2 | 2 | 2 |

Spoken the way the owner dictates: natural pauses, at least one long clip
per group as a prompt for a coding agent with paths and identifiers.
`bench/clips/README.md` gets the list and the ffmpeg line with `-t 40`.
Length buckets in the report come from each clip's real duration, not its
name.

### Measurement 1: where the fixed cost goes

For every clip, transcribe slices of the first 1, 2, 4, 8, 15, 25 s and the
whole clip, three runs each after a warm-up, forced language from the file
prefix. Report the median time per slice length and a straight-line fit
(fixed seconds plus seconds per audio second). This answers how much a tail
pass after release costs.

### Measurement 2: cheap levers

Each run on the full clips, reporting median STT time and WER per group,
compared with today's options:

1. `chunkingStrategy` `.vad` (today) versus none, for clips under 30 s.
2. Any other `DecodingOptions` change the builder finds in WhisperKit 1.1.1
   that skips work for single-window clips. The builder lists what was
   tried.

A lever that saves 0.3 s or more at every length with no WER loss ships on
its own as a small change, before or instead of Phase 2.

### Measurement 3: simulated incremental transcription

The bench replays each clip as if it were being recorded, on a virtual
clock, with the real model:

- The **chunker** (below) reads the clip's audio frame by frame and closes
  a part at each cut point it finds.
- Each closed part is transcribed as soon as the previous pass finished
  and the part was closed: `start = max(partClosedAt, previousPassEnd)`,
  measured duration added. Passes run one at a time, as on the shared main
  model.
- Release happens at the end of the clip. The open tail is transcribed
  after `max(release, lastPassEnd)`.
- **Release to transcript** = (end of tail pass) minus release.
  **Baseline** = time of one full-clip pass, as today.
- Final text = parts joined with one space, then `HallucinationFilter`
  and placeholder stripping as `DictationPipeline` does today.

The report table, per clip and then per group and length bucket: audio
seconds, parts, baseline seconds, incremental seconds, saving, baseline
WER, incremental WER. Text goes to stderr only with `--show-text`. The
committed report (`docs/bench/2026-10-xx-incremental-bench.md`) carries
numbers only. **(my call)**

Parameter sweep, every combination, best row per group reported:

| Parameter | Values |
|---|---|
| Pause that allows a cut | 0.3, 0.5, 0.8 s |
| Shortest part | 2, 4, 6 s |
| Longest part before a forced cut | 15, 25 s |
| Previous part's text in the Whisper prompt | on, off |

Plus one run of the best combination with a concurrent loop transcribing
the same audio on `openai_whisper-base` every 0.6 s, to measure contention
with the live preview.

### Gate

Phase 2 starts only when the best parameter combination meets all three
success criteria under *Goal* on the bench corpus, with and without the
concurrent preview loop. The owner sees the report and agrees before a plan
is written.

If it fails, the result goes into `docs/progress/incremental-log.md` and
`docs/ROADMAP.md` (dropped, with numbers), and any cheap lever that passed
ships alone.

## Phase 2: build (only after the gate)

### How it works

While the hotkey is held, BugVoice cuts the recording at natural pauses
and transcribes each finished part on the main model in the background.
On release it waits for a running pass to finish, transcribes only the
remaining audio, and joins the parts. Cleanup, the fidelity check and paste
run on the joined transcript exactly as today.

Why cut at pauses **(my call)**: it needs no timestamps (which forced
language breaks in WhisperKit 1.1.1), a pause is where a sentence or phrase
ends so cuts rarely split a word, and each part is transcribed once. The
rejected alternative, re-transcribing the growing recording and keeping the
words two passes agree on, needs word timestamps to know where the agreed
audio ends.

Why wait for a running pass on release instead of cancelling it: Core ML
cannot stop mid-pass (measured 2026-10-19: 0.9–1.8 s from cancel to stop),
and a part is a few seconds, so its pass ends sooner than a cancel would.

### The chunker

`VoiceCore/SpeechChunker.swift`, pure, Foundation only, TDD:

- Input: 16 kHz mono samples as they arrive (or 20 ms frame RMS values).
- A frame is silent below `max(0.003, 0.25 × median RMS of voiced frames so
  far)`. **(my call; the sweep may change the factor)**
- A cut is allowed once a pause of at least *pause* seconds follows at
  least *shortest part* seconds of audio since the last cut. The cut point
  is the middle of the pause.
- With no pause by *longest part*, cut at the quietest 200 ms window in the
  last 3 s.
- Output: cut sample indices. Values for the three thresholds come from the
  Phase 1 sweep and are constants in `SpeechChunker`.

### The session

`VoiceCore/IncrementalTranscription.swift`: an actor created at hotkey
press for one recording. It conforms to `Transcriber`, so
`DictationPipeline.run` keeps calling `transcriber.transcribe(clip,
options:)` unchanged **(my call)**:

- During the hold, the controller feeds it sample snapshots (the recorder's
  thread-safe tail copy used by the live preview). Each closed part goes to
  the main `PriorityTranscriber` at dictation priority, with the same
  `TranscriptionOptions` the final pass will use (language, vocabulary
  prompt), plus the previous part's text if the sweep picked it.
- `transcribe(clip, options)` on release: when the options match those the
  parts used and every part succeeded, wait for the running pass,
  transcribe audio after the last cut, return the joined `Transcript`.
  Otherwise transcribe the whole clip, as today.
- Cancel (Esc, or a too-short clip) cancels parts not started and drops
  their results.

### Falling back to the whole clip

Today's full-clip pass runs instead, with no message to the owner, when:

1. The language changed during the hold (language key tap).
2. Any part's pass failed or was cancelled.
3. Language is automatic and parts came back in different languages.
4. Fewer than one part closed before release (short dictations: the normal
   path, at no extra cost).
5. The joined text is empty but the clip is not silent.

Diagnostics records the reason.

### Where it runs

- Ordinary dictation and Notes dictation: yes.
- Command mode, meeting recording, OpenAI-compatible engine, model not
  ready: no.
- Secure field at hotkey press: yes. Audio and text stay on the Mac, and
  the final result is handled exactly as today (copied, never pasted, not
  kept in history).

### Setting

Settings › Speech, below Live preview:

> **Transcribe while speaking** (toggle, default on)
> Turns each finished phrase into text while you talk, so long dictations
> paste sooner. Uses the main speech model while you hold the key. Off with
> the OpenAI-compatible engine.

Settings key `speech.incrementalTranscription`, defaults to true when
missing. Global search gets an entry pointing at it.

No HUD change: the done pill already shows release-to-text seconds.

### Diagnostics and history

- `StageTimings` gains `earlyParts: Int` (decodes as 0 when missing). The
  dictation summary adds `early=3` when parts were used, or
  `early=fallback:<reason>` with reasons `languageChanged`, `partFailed`,
  `mixedLanguage`, `emptyJoin`. No text.
- History keeps the joined raw transcript in `raw`, as today.

### Shadow check (evaluation only)

Hidden settings key `speech.incrementalShadowCheck`, default off, no UI
**(my call)**. When on, after each incremental dictation is pasted,
BugVoice transcribes the whole clip at meeting priority, computes
`WordErrorRate` between the full-clip raw and the joined raw, and logs
`shadow_wer=0.03 early=3 rec=24.1` to Diagnostics. Numbers only. The owner
turns it on for the first week of use; the log section of
`docs/progress/incremental-log.md` records the distribution.

## Evaluation

1. Phase 1 bench report, committed, numbers only.
2. Unit tests: `SpeechChunkerTests` (cuts inside pauses only, shortest and
   longest part, forced cut at the quietest window, silence-only audio gives
   no cut, a pause before the shortest part gives no cut) and
   `IncrementalTranscriptionTests` with a fake transcriber (joins in order,
   waits for a running pass, every fallback reason, options mismatch falls
   back, cancel drops results).
3. Release build bench rerun with the app's real `SpeechChunker` constants:
   same numbers as the simulation within 0.1 s.
4. One week of shadow check: median `shadow_wer` at most 0.02, no value
   above 0.10 without a known cause logged.

## Device checks

I1–I8 for the owner, in `docs/progress/incremental-log.md`:

1. Dictate 40 s into Notion with pauses between sentences: done pill shows
   at least 1 s less than the same dictation with the setting off.
2. Same in Vietnamese, then mixed with English technical words: text as
   good as with the setting off.
3. A 3 s dictation in a terminal: same speed as with the setting off.
4. Speak 30 s without pausing: text complete, nothing doubled at the cut.
5. Tap the language key halfway through: text in the new language
   (fallback), Diagnostics shows `early=fallback:languageChanged`.
6. Press Esc mid-dictation: nothing pasted, the next dictation is normal.
7. Live preview on while dictating 40 s: the card keeps updating about once
   a second.
8. A long Notes dictation: the note gets the full text.

## Left to the builder

- Bench code structure and report layout within the columns above.
- Frame size and RMS details in the chunker, as long as the tests pass.
- How sample snapshots reach the session (callback or polling), as long as
  no audio is copied more than once per part.
- Wording of fallback reasons in code, as long as Diagnostics shows the
  four names above.
