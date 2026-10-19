# Live preview while speaking

Date: 2026-10-19. Status: draft for owner review.
Mockup: `docs/design/proposal-live-preview.html`.
Follows: `docs/propose-new-features.md` item 3, picked by the owner on
2026-10-19. The owner asked for the spec and mockup without a question round,
so every choice below is **my call** unless it restates an existing BugVoice
rule.

## Why

While the owner holds the key, the HUD shows a red dot, level bars and a
clock, and nothing tells them BugVoice is hearing the right words until the
text lands about 2 s after release. Showing the words as they are spoken
gives two things: confidence (a wrong language or a dead mic shows at once,
so the owner can let go and start over) and a shorter-feeling wait (the text
is already on screen during Transcribing and Cleaning).

## Goals

1. **Words while speaking.** Under the HUD pill, the last words heard, updated
   about once a second while the key is held (hold and hands-free).
2. **Command mode too.** The spoken instruction shows under the Command pill.
3. **Kept through the wait.** After release, the last preview stays (dimmed)
   under Transcribing and Cleaning until the result shows.
4. **No slower paste.** Release to text stays within 0.3 s of what it is with
   the preview off (device check P1).

## Non-goals

- Pasting sooner. The pasted text still comes from one transcription of the
  whole recording after release, then cleanup, exactly as today.
- Reusing preview passes for the final transcript (a later speed project;
  see the Speed note in `docs/propose-new-features.md`).
- Cleaned or Dictionary-corrected preview. The preview is what Whisper heard.
- Editing the preview, or a preview in Meetings (Meetings already has live
  text).

## Anti-goals

- A password read out on screen: no preview when the focused field is secure.
- Audio sent off the Mac once per second: no preview with the
  OpenAI-compatible speech engine, even a local one (it would multiply the
  requests). WhisperKit only.
- A preview that makes dictation wait: preview work always yields to the
  final transcription and to meeting chunks.
- Preview text kept anywhere: never in history, logs, diagnostics or
  Insights.

## What the owner sees

Mockup screens 1–4.

- **Listening:** the pill as today. Once the first words are heard, a card
  appears under it, the same width as the pill or wider up to 460 pt (times
  the HUD size factor), with at most two lines of text in the body font.
  When the text is longer, the start is cut and shown as "…" so the newest
  words are always visible.
- **Updates:** each pass replaces the card text (0.15 s crossfade). No
  per-word animation.
- **Command:** same card under the Command pill, showing the instruction.
- **After release:** the card stays, text in the secondary color, under
  Transcribing / Cleaning / Rewriting. It hides with the pill when the
  result (Done, a warning, Nothing heard) shows.
- **Nothing yet:** no card until a pass returns text. Silence, Whisper
  hallucination lines ("Thank you.", "Cảm ơn các bạn đã theo dõi") and blank
  passes show nothing.
- **Off cases:** secure field, meeting recording, OpenAI-compatible engine,
  setting off, speech model still loading: the pill exactly as today, no
  card, no message.

## How it works

1. **Audio.** `AudioRecorder` gives a copy of the last N seconds recorded so
   far without stopping (`recentSamples(seconds:)`).
2. **Cadence.** The first pass starts when 1.0 s of audio is recorded. Each
   later pass starts 0.6 s after the previous one returned. A pass uses the
   last 15 s of audio (shorter recordings: all of it). Only one pass at a
   time; a pass that returns after the key is released is discarded.
3. **Engine.** Passes run on a separate small Whisper model,
   `openai_whisper-base` (about 150 MB, downloaded once into the models
   folder, loaded at launch when Live preview is on), never on the main
   model. Revised 2026-10-19 after a benchmark on the branch: sharing the
   main model added 0.7 s to release-to-text (median 2.12 s vs 1.41 s,
   because a running pass cannot be stopped mid-inference), while the
   separate model added none (1.38 s) and each pass takes about 0.2 s. The
   preview text is rougher, mostly in Vietnamese; the pasted text is
   unchanged. At release the running preview pass is cancelled. Until the
   preview model is ready, no card shows.
4. **Options.** Same language as the run (the language shown in the pill;
   a language key change applies from the next pass), same vocabulary
   prompt as the final pass.
5. **Text.** Placeholders and hallucination lines are removed
   (`DictationPipeline.stripPlaceholders`, `HallucinationFilter`),
   whitespace collapsed. For the card: the last 140 characters, cut at a
   word boundary, prefixed with "…" when cut.

## Settings

Settings › Speech, after Use vocabulary hints: **Live preview** switch, on by
default. Footnote: "Shows the words under the HUD while you speak, using a small extra
speech model (downloaded once, about 150 MB). The pasted text still comes
from the whole recording after you release. Off with the OpenAI-compatible
engine." (mockup screen 5).

## Where the logic lives

VoiceCore (test first):

- `LivePreviewModel.name` (the preview model).
- `TranscriptionPriority.preview` and `TranscriptionPriorityQueue` order
  (dictation, meeting, preview), single preview slot, drop previews when a
  dictation request is enqueued.
- `PriorityTranscriber` cancels a running preview when a dictation request
  arrives.
- `LivePreviewPolicy.isEnabled(settings:engine:secureField:meetingRecording:speechReady:)`.
- `LivePreviewCadence`: given recorded sample count, the time the last pass
  returned and now, whether to start a pass and which sample range to use.
- `LivePreviewText.display(_:)`: strip, collapse, last 140 characters at a
  word boundary with "…".

App: `LivePreviewController` (runs passes for one recording, owned by
`DictationController` and `CommandController`), `HUDModel.preview`, the
card in `HUDView`, the setting.

## Limits

- First pass at 1.0 s, 0.6 s between passes, 15 s window, one pass at a time.
- Card: two lines, 140 characters, width up to 460 pt × HUD size factor.
- Release to text within 0.3 s of preview-off (median of 10 dictations).

## UI copy

Plain English, no hedging, no emoji. Strings are in the mockup.

## Left to the builder

- How a running WhisperKit pass is stopped (task cancellation or the
  decoding callback), as long as P1 holds.
- Card layout details within the mockup.

## Open for the owner

My calls; say if any is wrong:

1. The preview shows raw Whisper text, not cleaned text.
2. On by default.
3. Off during a meeting recording and with the OpenAI-compatible engine.
4. The preview stays visible, dimmed, while transcribing and cleaning.
5. Command mode shows its instruction the same way.
