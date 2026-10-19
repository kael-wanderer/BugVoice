# Live preview execution log

Date: 2026-10-19. Branch: `feat/live-preview`, from `main`.
Spec: [live preview design](../superpowers/specs/2026-10-19-live-preview-design.md).
Plan: [live preview implementation](../superpowers/plans/2026-10-19-live-preview.md).
Mockup: [live preview](../design/proposal-live-preview.html).

## Built

1. Preview priority (`preview = 2`, existing raw values preserved). Queue order:
   dictation, meeting, preview; newest queued preview replaces the older one;
   dictation drops queued previews and cancels a running preview. Caller
   cancellation also stops running work at every priority. Dropped requests
   throw CancellationError; idle waits still include the active engine pass.
2. Foundation-only policy, cadence and display helpers; `speech.livePreview`
   defaults to true when missing in older settings. First pass after 1 s,
   0.6 s after each pass, last 15 s of audio. Strip placeholders and hallucinations,
   collapse whitespace, retain the last 140 grapheme clusters at a word boundary.
3. Thread-safe sample-tail copies and sample-based duration in AudioRecorder.
   WhisperKit's decoding callback reads a cancellation flag protected by a
   standard-library Mutex; cancellation is checked before and after inference.
4. Separate preview controllers for dictation and command recordings using the
   shared transcription router. Each start clears the card. Stop cancels work
   and increments a generation, preventing late results from reaching another
   recording. Language is read at each pass; vocabulary prompt is captured at
   start as specified in the plan. RMS below 0.003 skips a pass. Preview errors
   are ignored without logging. Final text continues to come exclusively from
   the existing full-recording pipelines; no preview persistence or Insights.
5. Settings › Speech › Live preview with the exact specified footnote. Default
   on, off for secure start fields, meeting recordings, the OpenAI-compatible
   engine, or a model not ready. Card uses the existing HUD theme, two lines,
   head truncation, 460 pt × HUD factor maximum width, scaled padding and corner
   radius, 0.15 s text crossfade; dim during processing, clear on results/hide.

## Cancellation measurement — Task 3 Step 2

A throwaway `bugvoice-bench` entry point used the cached
`large-v3-v20240930_turbo` model through the actual WhisperKitTranscriber.
Input: 20.000 s of locally generated Samantha speech, looped/resampled to
16 kHz mono with ffmpeg. A 2 s transcription warmed the model first. Three
passes used English and preview priority; each was cancelled 100 ms after
starting. ContinuousClock measured cancellation until CancellationError:

| Attempt | Cancel to throw |
|---|---|
| 1 | 0.916248375 s |
| 2 | 1.801081375 s |
| 3 | 1.068064083 s |

Median **1.068064083 s**, maximum **1.801081375 s**. This was a debug command-line
build, not a production release-to-paste benchmark. The throwaway entry point
was restored before committing; no probe source or generated audio is committed.
No microphone recording, app launch, hotkeys, clipboard operation or remote
inference was involved.

**The under-0.3 s cancellation target was not met.** WhisperKit 1.1.1 invokes
its callback in a detached task (`Task.isCancelled` there cannot see the caller),
so the implementation uses the plan's Mutex flag fallback. This stops decoding
when the callback can run, but cannot interrupt the preceding Core ML prediction
immediately. The scheduler waits for that pass before starting final inference,
maintaining serial access to the model. Preview audio is capped at 15 s in the
app; the spec accepts waiting for one pass when immediate interruption is not
possible. P1 remains unverified and must not be inferred from unit tests.

## HUD sizing

The NSHostingView still reports intrinsic size changes. HUDView measures the
pill height separately; HUDController sizes the panel to the full stack's
`fittingSize`. Extra height = stack height minus pill height minus the original
16 pt outer padding (8 pt per side). The panel widens around its center and its
bottom moves down by that extra height, keeping the pill at its old position.
The preview is below it, separated by 6 pt × HUD size factor. If this would put
the card below the physical screen (for example with an auto-hidden Dock), the
bottom is clamped to the screen edge, lifting the stack just enough to fit.
Without a card the original placement and padding apply. Layout and Large HUD
rendering still require owner checks; the app was not launched.

## Validation

VoiceCore tests were written and run red before each core implementation:
Task 1 failed because `.preview` did not exist; Task 2 failed because preview
helpers and the setting did not exist. Full `swift test` runs before commits:

| Task | VoiceCore | MCPKit | BugVoiceMac | Total |
|---|---:|---:|---:|---:|
| 1 | 1,185 | 30 | 114 | 1,329 |
| 2 | 1,194 | 30 | 114 | 1,338 |
| 3 | 1,194 | 30 | 114 | 1,338 |
| 4 | 1,194 | 30 | 114 | 1,338 |
| 5 | 1,194 | 30 | 114 | 1,338 |

Tasks 3 and 4: `swift build` passes. Task 5: `Scripts/build-app.sh` succeeds
in release configuration, signed with **Bugler Local Dev**, signature verified,
and Shortcuts metadata generated with Xcode. Final `swift test`: **1,338 tests
pass**. The app was not launched. WhisperKit remains pinned exactly at 1.1.1;
no dependency or package manifest change.

## Decisions differing from literal plan details

- The proposed queue-order example enqueues preview, meeting, then dictation
  but expects the preview to survive. This contradicts the explicit dictation
  drop rule. The ordering test enqueues dictation first, then preview and meeting;
  a separate test verifies dictation drops queued previews.
- A suffix that already starts at a word boundary keeps that complete word;
  it only drops a partial leading word. Vietnamese text is normalized to NFC,
  preserving composed/decomposed diacritics and grapheme boundaries.
- New-recording clearing lives in preview `start`, rather than clearing on every
  listening state update: language-key flashes reuse listening states and must
  preserve the current card.
- Screen-bottom clamp avoids clipping when there is insufficient space below
  the pill; only this fallback moves the pill upward.
- Both listening variants now drive the existing HUD level timer. Silent windows
  wait the normal gap before resampling to avoid repeated tail copies at 10 Hz.
- No installed superpowers execution skills were found; followed the five tasks
  directly. No subagents were used.

## Owner device checks — not run

The owner runs these checks. No app launch or input automation was performed.

- [ ] P1 Release to text: 10 dictations of about 5 s with Live preview on and 10
  with it off (Settings › Speech); median release-to-text from History differs
  by at most 0.3 s. Pay attention to release during an active preview pass.
- [ ] P2 Hold in Slack or Notes and speak: card appears after about a second and
  updates about once a second; after release it stays dimmed under Transcribing
  and Cleaning, hides with Done.
- [ ] P3 Two quick dictations in a row: the second HUD never shows words from
  the first.
- [ ] P4 Speak 30 s: the card stays at two lines, start cut with "…", newest words
  visible.
- [ ] P5 Vietnamese and mixed speech: diacritics correct in the card; language
  key tap changes the next update.
- [ ] P6 Command mode with a selection: the instruction shows under the Command
  pill and stays dimmed under Rewriting.
- [ ] P7 Password field: no card. Meeting recording: no card. Engine set to
  OpenAI-compatible: no card. Setting off: no card.
- [ ] P8 Silence for 3 s: no card, no "Thank you.".
- [ ] P9 History, Insights and logs contain no preview text (only the final
  dictation).
- [ ] P10 HUD size Large: card scales with the pill. Also check an auto-hidden
  Dock, a one-line/two-line card, and light/dark appearance.

## Review: separate preview model (2026-10-19)

The 1 s cancellation measured above made the final transcription wait for a
running preview pass. A release-build benchmark (throwaway, not committed)
ran the real `PriorityTranscriber` and `large-v3-v20240930_turbo` on locally
generated speech: a 6 s final clip, previews of a 13.6 s clip every 0.6 s,
release at 2.0–4.9 s, 10 runs per case.

| Case | Final transcription, median | Max |
|---|---|---|
| Preview off | 1.41 s | 1.46 s |
| Preview on the main model (queue) | 2.12 s | 2.32 s |
| Preview on separate `openai_whisper-base` | 1.38 s | 1.43 s |

Preview pass, 13.6 s clip: main model 1.63 s, base 0.21 s, small 0.55 s.
Vietnamese sample ("Sáng nay mình họp với team mobile về bản build mới…"):
base heard "hợp với tim mua bay", small "họp với tim mô bay", main "họp với
team mobile". English was exact on base.

Change: the preview uses its own `WhisperKitTranscriber` with
`LivePreviewModel.name = "openai_whisper-base"`, downloaded once into the
models folder and loaded at launch (and when Live preview or the engine
setting changes). No card until it is ready. The footnote says so. The
queue priority work from Task 1 stays: it is tested and harmless, and caller
cancellation now also stops running work.

Device check P1 still applies; P11: first launch with Live preview on
downloads the base model (about 143 MB) and the card appears once it is
loaded.
