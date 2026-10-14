# BugVoice — Meetings design

Date: 2026-10-14
Status: approved with maintainer amendments
Scope: sub-project 2 of 3 — meeting capture, transcript timeline, playback, summaries, and retention. Dictation core and app shell are already implemented. Notes (sub-project 3) remain out of scope.

## 1. Purpose

Capture a meeting locally as separate microphone and system-audio tracks, transcribe both tracks during and after the call, and provide a searchable, playable timeline. The final playback file is a mix of the two tracks. Nothing leaves this Mac unless the user configured a remote text model; audio is never sent to a text model.

### Success criteria

- Start and stop recording from the menu bar or Meetings page. The menu shortcut is ⌃⌥M.
- Record microphone and system audio separately, with the track also identifying the transcript speaker: **You** for microphone and **Others** for system audio.
- Show transcript progress while recording and preserve useful transcript timestamps after the final pass.
- Keep committed audio and meeting metadata when recording is interrupted by app quit, sleep, or a crash. An interrupted meeting can be recovered on the next launch.
- Keep dictation's existing hotkey, HUD, transcription, and paste flow usable during a meeting recording.
- Retain meetings until the user deletes them by default.

## 2. Scope

### In scope

- Manual recording started from the menu bar or Meetings page.
- A non-activating floating recorder window with elapsed time, You/Others level meters, latest transcript line, Pause, Mark, and Stop controls.
- Local capture of microphone audio and system output audio as separate tracks, plus a mixed playback file.
- Interim transcription in approximately 30-second chunks, followed by a final pass on each track after Stop.
- A day-grouped meeting list, search, playback, transcript timeline, Summary and Action items tabs, export, rename, delete, and Show in Finder.
- Optional meeting retention in Settings → Meetings and a Meetings size row in Settings → Storage.
- A System Audio Recording permission row.

### Out of scope

- Call detection or automatic meeting start. Keep a `MeetingStartTrigger` seam so a later call detector can request the same start operation.
- Speaker diarization, per-person identification, call controls, cloud transcription, and Notes.
- Selecting one application as the only system-audio source. This design captures system output from all other processes and excludes BugVoice's own process.

## 3. Architecture and data flow

### 3.1 Start and capture

The menu item **Start meeting recording** (⌃⌥M) and the Meetings page's **Start recording** button call one injected `MeetingController.start()` operation. Start is rejected with a clear status when there is no microphone input or System Audio Recording access is denied. If WhisperKit is still loading, capture begins and transcription waits for the model to become ready. A failed start must clean up any source already opened.

Capture the microphone through a meeting-owned audio input and capture system output with a Core Audio process tap created by `AudioHardwareCreateProcessTap`. Use `CATapDescription` to tap the system mix while excluding BugVoice's process, and attach the tap as an input to a private aggregate device. Keep independent clocks/sample timestamps for the two inputs and map them to a shared meeting-relative monotonic timebase. Resample each track to the format accepted by the existing `AudioClip` / `Transcriber` path. Do not combine tracks until creating `audio.m4a`.

Core Audio process taps are available from macOS 14.2, below BugVoice's macOS 15 deployment floor. macOS prompts for System Audio Recording access when capture first starts. The app bundle needs `NSAudioCaptureUsageDescription`; `Scripts/build-app.sh` copies `App/Info.plist` into the bundle. There is no public preflight API for System Audio Recording. The Permissions window row says **Requested when the first meeting starts**; attempt the tap at meeting start and detect denial from the observed start/capture behavior. Apple references: [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) and [NSAudioCaptureUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription).

The capture callbacks append to separate durable journals: headerless, signed little-endian Int16 PCM, 16 kHz, mono, one journal per track. This uses about 230 MB per hour for both tracks (decimal MB, excluding metadata). Commit and synchronize journal data and its byte/time checkpoint at least once per second; update `meeting.json` atomically. Pause stops both capture sources and closes the current journal chunk. Resume starts both against the same meeting timebase with an explicit gap in elapsed meeting time. On sleep, stop capture and checkpoint before sleep; do not silently resume on wake. On ordinary Stop, encode `mic.m4a` and `system.m4a` as AAC, create `audio.m4a` as the AAC mix, write the final manifest, and remove the journals only after all final files are durable. On quit, ask whether to stop and keep the meeting or cancel quitting. On crash/relaunch, retain every journal checkpoint, mark the meeting interrupted, and offer **Recover recording**; recovery finalizes the available audio and runs the remaining transcription.

### 3.2 Meeting transcription

Use the existing `Transcriber` protocol and `AudioClip`. Keep an independent chunk scheduler per track. Submit about 30 seconds of audio after it is captured, with a short overlap between adjacent chunks so speech at boundaries is not dropped. Pass each chunk's meeting-relative start offset to a VoiceCore merge function. Merge chunks in stable `(start, speaker)` order, remove duplicate overlap text, and retain each returned segment's start and end adjusted by the chunk offset. Track identity supplies speaker; there is no diarization.

For interim chunks, set transcription language to `.auto` and request timestamps. The final pass re-transcribes the tracks in approximately 30-second chunks with those same options, replacing their interim segments after applying the same offset and merge rules. The final pass never sends an entire track to WhisperKit. Dictation can run between meeting chunks and is scheduled first. The Meetings UI can show interim segments as they arrive and reports final progress as **Transcribing N%**. If a final pass fails, keep the interim transcript and show a retryable error.

**WhisperKit 1.1.1 constraint, fallback, and evidence.** Dictation keeps the current forced-language, no-timestamps path. Meetings first uses timestamp decoding with `.auto` language. This is a per-request option and does not change dictation behavior. Store the language returned by WhisperKit on every chunk in `meeting.json`; do not treat one chunk's detected language as the whole meeting language. A real local run against the cached `large-v3-v20240930_turbo` model with timestamps enabled processed `en-1.wav`, `mix-1.wav`, `mix-2.wav`, and `vi-1.wav`: forced `vi` returned an empty transcript for all four, while `.auto` returned nonempty text for all four. A separate fallback run with `withoutTimestamps = true`, forced `vi`, and VAD chunking on `mix-1.wav` returned text and one segment from `0.00` to `15.00` seconds. That VAD window range is usable as coarse timing for the 15-second input, but it is not word-level alignment. Forced `vi` on `vi-1.wav` still returned no text, so the fallback does not guarantee recovery for every clip. The bench executable was temporarily instrumented to print segment bounds, then its source instrumentation was removed; the adapter source was restored. Auto language can also render Vietnamese clauses as English, as seen in the mixed-language benchmark. If the user requests a forced-language retry, use `.vi` or `.en` with `withoutTimestamps = true` and the returned VAD window start/end times. Preserve the detected or forced language for that chunk.

#### Chunk scheduling and filtering

The app owns one `WhisperKitTranscriber` instance, shared by dictation and Meetings. Route transcription work through a `TranscriptionScheduler`: dictation has priority over every meeting chunk, and the scheduler yields at chunk boundaries. A pending dictation waits only for the one currently running meeting chunk. Interim and final meeting work both submit chunks of about 30 seconds; never submit an entire track as one transcription call. The VoiceCore scheduler has deterministic tests that prove a queued dictation request runs before the next queued meeting chunk. A `CancellationError` from a cancelled queued dictation is represented as cancellation, with no error HUD; add a regression test through `PriorityTranscriber` and `DictationPipeline`.

Before each meeting transcription call, split the normalized Float32 audio into adjacent 100 ms windows and skip the chunk only when no window has RMS above `0.003` (the existing dictation silence threshold). This preserves a short utterance inside an otherwise silent 30-second window while avoiding Whisper calls on silent system-audio windows. For every returned chunk, strip Whisper placeholders and apply `HallucinationFilter` before merge and before saving the segment. An empty, silence-only, or hallucinated chunk remains recorded in progress metadata but adds no transcript text.

Each meeting chunk record stores track, offset, duration, requested language/mode, returned detected language, result state, and segment bounds. Retry with forced `vi` or `en` and timestamps disabled only when the auto result is empty after placeholder stripping and the 100 ms energy gate passes. Use the returned VAD window ranges as coarse segment bounds. A hallucination-filtered but nonempty result does not trigger an automatic retry. If Speech language is `.auto`, ask the user to select `vi` or `en` before a forced retry.

### 3.3 Dictation while a meeting records

Dictation remains available during meetings. The existing Right Option hotkey and HUD work as before, and its paste flow inserts into the current focused field. Dictation audio is also present in the meeting's microphone track and may appear in the You transcript. Do not stop, pause, or change meeting capture when dictation starts. Both consumers can read the microphone concurrently; failure to start dictation must not affect the meeting, and failure of one meeting capture track must not cancel dictation.

### 3.4 Summary and action items

Summary and Action items are generated on demand from the final transcript using the configured `TextModel` returned by `ProviderFactory`. Follow the app's existing local-first setting: local endpoints remain local, and configured remote providers may receive transcript text. Never send audio to `TextModel`. If no text model is configured, or the configured model fails, keep the Transcript tab usable and show a retry action. Save successful summary and action-item text in `meeting.json` so it remains available offline. Prompts request the transcript language, prohibit adding facts, and format action items as concise Markdown bullets with an owner only when stated.

## 4. Storage model

Use `AppPaths.meetings`, already reserved at `~/Library/Application Support/BugVoice/Meetings/`. Each meeting is stored at `Meetings/<id>/`:

| File | Content |
|---|---|
| `audio.m4a` | Final mixed playback file |
| `mic.m4a` | Final microphone track |
| `system.m4a` | Final system-output track |
| `meeting.json` | Stable id, title, start/end times, duration, state, per-chunk requested and detected language, audio format, marks, transcript segments with speaker, transcript progress/errors, and generated summary/action items |
| `.capture/` while recording or awaiting recovery | Append-only PCM journal chunks and checkpoints used to recover captured audio after interruption; remove after all final files are durable |

Write `meeting.json` through a same-directory temporary file followed by atomic rename. The model is Codable and versioned so future schema changes can migrate stored meetings. A meeting folder exists as soon as start succeeds, and `meeting.json` is checkpointed alongside captured journal data. A missing/corrupt final mix can be rebuilt from the two source tracks. A missing source track is represented as unavailable; never substitute the mixed track for a speaker-specific source.

### Meeting state

Persist one of `recording`, `paused`, `interrupted`, `transcribing`, `ready`, or `failed`. The state and completed chunk count allow relaunch recovery to distinguish a complete meeting from an interrupted capture. In-memory UI states such as playing are not persisted.

## 5. UI

### 5.1 Floating recorder

Use a floating `NSPanel` configured as non-activating so opening it never changes the frontmost app or focused text field. It stays visible above the meeting app and follows the active screen. It shows:

- Recording or Paused state and elapsed meeting time.
- Separate live **You** and **Others** meters.
- The latest timestamped transcript line and speaker, when available.
- **Pause** / **Resume**, **Mark**, and **Stop** controls.

Mark appends the current meeting-relative time and an optional short label to the manifest. Stopping closes the recorder panel and leaves transcription running in the background. The menu indicates recording state and provides Stop and Open Meetings actions while capture is active.

### 5.2 Meetings page

Add Meetings to `Page` and show it in the main-window sidebar. The list is grouped by day, ordered newest first, with title, start time, duration, and processing status. Support transcript search across saved meetings. **Start recording** is available when no meeting is active. Selecting an interrupted meeting offers recovery; an active meeting can be reopened without starting another capture.

The detail view contains:

- Editable title and metadata: date/time, duration, file size, and transcription language when known.
- Player for `audio.m4a`: play/pause, seekable waveform, ±15 seconds, and playback speed (0.5×, 0.75×, 1×, 1.25×, 1.5×, 2×).
- Track legend for You (microphone) and Others (system audio).
- Transcript rows with `m:ss – m:ss`, speaker, and text. Selecting a row seeks playback to its start. Highlight the row containing the current playback time; no row is highlighted while paused outside a segment.
- Tabs **Transcript**, **Summary**, and **Action items**. Show transcript progress and retry state independently from playback.
- **Export** options for Markdown, SRT, or audio; **Show in Finder**; **Rename**; and **Delete** with confirmation.

Markdown export includes title, date, speaker-labelled timestamped transcript, and any saved summary/action items. SRT export orders segments by start time and numbers them from 1. Audio export copies the mixed `audio.m4a`; source tracks remain accessible through Show in Finder. Export uses save panels and does not overwrite a destination without confirmation.

### 5.3 Settings and permissions

Add a **Meetings** Settings tab with **Delete meetings after**: Never (default), 30 days, 90 days, or 1 year. Retention prunes only ready meetings by their end time; never delete a recording, transcript, or recovery journal while capture or transcription is active. Retention runs at launch and after the setting changes. Deletion removes the full meeting folder. Include **Model context size** (default 8,192 tokens) and **Generation output limit** (default 2,048 tokens), both independent of dictation cleanup's `maxTokens`. Long transcript generation splits the transcript into ordered parts sized to fit that context after reserving space for instructions and output, summarizes each part, then recursively merges the part summaries or action items under the same context/output limits. The Foundation-only estimator budgets three characters per token to account for denser Vietnamese tokenization, and preserves speaker/timestamp boundaries; if one segment is too large, split its text at sentence or word boundaries and retain its parent speaker and time range. Show progress as `Summarizing 2 of 6` or `Merging summaries`; provide Cancel and discard partial generated output while preserving the transcript.

Add a **Meetings** category to Settings → Storage. Display its total size, including an active `.capture` journal, and a Show in Finder action. Measurement uses the existing directory-size approach.

Add System Audio Recording to the Permissions window. There is no public preflight API for audio capture. Show **Requested when the first meeting starts**; detect denial at meeting start by observing process-tap creation/start and capture behavior, and show the user how to grant access in System Settings. Do not use Screen Recording APIs such as `CGPreflightScreenCaptureAccess()` or `CGRequestScreenCaptureAccess()` for this permission. Keep microphone permission separate. System audio denial blocks meeting start with an explanation; dictation remains usable.

## 6. Error handling and interruption safety

| Condition | Behavior |
|---|---|
| Microphone or process tap fails at start | Stop and destroy any source that did start; keep no empty meeting folder; explain which source failed |
| Permission missing | Keep dictation available; show the System Audio Recording permission row; retry start after access is granted |
| Audio callback or disk write fails | Stop both tracks cleanly, preserve the last durable checkpoint, mark the meeting failed/interrupted, and offer recovery |
| User pauses | Flush both tracks and manifest, then stop audio callbacks; timer pauses; Resume starts both tracks together |
| App receives sleep notification | Flush and stop capture; mark paused due to sleep; do not resume until the user presses Resume |
| User quits while recording | Present Stop and keep / Cancel. Stop and keep finalizes captured audio before termination; any pending transcription resumes on next launch |
| Process crashes or is force-quit | On next launch, detect `recording`, `paused`, or incomplete `transcribing` state, retain audio and checkpoints, mark interrupted or retryable, and offer recovery |
| WhisperKit fails | Keep audio, show transcript failure, allow retry; playback and export audio stay available |
| Text model fails | Keep transcript; show Summary or Action items generation failed with Retry |
| Meeting delete | Confirm, then delete that meeting's folder; no effect on other meetings or dictation history |

## 7. Testing

**VoiceCore unit tests (`swift test`)** cover the Codable/versioned meeting model and interrupted-state recovery metadata; chunk scheduling and offset calculation; dictation-priority scheduling when a meeting chunk is queued; the `CancellationError` path through the priority transcriber and dictation pipeline; 100 ms silence windows including 30 seconds of silence containing one second of speech; chunk filtering; segment merge, overlap deduplication, stable ordering and track speaker; per-chunk language storage; SRT and Markdown export; meeting retention boundaries and active-state exclusions; transcript-time-to-player seek and current-row mapping; and long-transcript part splitting against configured context, segment-boundary preservation, summary/action-item merge, separate Meetings context/output limits, progress, and cancellation.

Use fakes for clock, storage, transcriber, audio source, and text model. Test the `MeetingController` state transitions, pause/resume gaps, start rollback when one track fails, stop/finalization, recovery of the last durable checkpoint, and that dictation lifecycle errors do not change meeting state. Keep AVFoundation/Core Audio, windows, and permission queries outside `VoiceCore`.

**Manual checklist** covers process-tap permission prompt and denial, mic/system source separation and levels, app playback excluded from Others, recorder window focus behavior, menu and page start/stop, concurrent dictation while recording, pause/resume, marks, sleep, quit, crash recovery, 30-second interim transcription and final replacement, seeking/highlighting, summary/action items with local and configured remote models, exports, rename/delete, retention, storage size, auto-detected language on mixed English/Vietnamese speech, and a repeated meeting with headphones to compare echo in the You and Others lanes.

Known risk: without headphones, the microphone can capture and transcribe Others' audio as You speech. Do not automatically delete repeated You lines because real speakers may echo a phrase intentionally. The manual checklist asks for a headphones comparison.

## 8. Implementation seams

- `Transcriber` and `TranscriptSegment` are the shared transcription contract. Add per-request timestamp and transcription priority options; defaults preserve dictation's current behavior. When meeting timestamps are on, the WhisperKit adapter uses auto language. A forced-language fallback disables timestamps and uses VAD window bounds. Keep the shared WhisperKit instance behind a scheduler that prioritizes dictation and yields between 30-second meeting chunks.
- `AppPaths.meetings` already exists. Extend `ensureExists()` only as needed; do not create Notes files or UI.
- Keep all meeting models, state transitions, chunk scheduling/merging, retention policy, export formatting, and timeline seek math in Foundation-only `VoiceCore`.
- Keep transcription scheduling priority, silence threshold decisions, per-chunk language metadata, placeholder/hallucination filtering, long-transcript part splitting/merging, and meeting-specific token budgets in `VoiceCore`.
- Put AVFoundation and Core Audio capture behind `BugVoiceMac` protocols with fake implementations available to app-level integration tests.
- Reuse `ProviderFactory.textModel(...)` for meeting summary and action-item generation.
- Add meeting controls to `MenuContent`, a Meetings page in `AppModel` / `MainWindow`, a non-activating recorder panel alongside the existing HUD, Meetings settings/storage rows, and System Audio Recording permission handling.
- Add `NSAudioCaptureUsageDescription` to `App/Info.plist`; `Scripts/build-app.sh` already copies that file into the app bundle.
- `MeetingStartTrigger` is the future seam for call auto-detect. This sub-project exposes only the manual menu/page trigger.

## 9. Decisions recorded from maintainer review

1. Use auto language with timestamp decoding as the normal Meetings path. Store detected language per chunk. Record the known risk that auto detection can render Vietnamese clauses as English. Retry with forced `vi`/`en` and `withoutTimestamps = true` only when the auto result is empty and the chunk passes the 100 ms energy gate; use VAD window start/end times. The real run verified coarse `0.00–15.00` timing with nonempty text on `mix-1.wav`, not word-level timing.
2. Dictation remains available during a meeting; its audio is included in the You track.
3. Capture system output from all other processes and exclude BugVoice's own process.
4. Journal signed 16 kHz mono Int16 PCM per track and synchronize checkpoints at least once per second. Final source and mixed `.m4a` files use AAC. Sleep stops capture until manual resume; quit asks Stop and keep / Cancel; a crash offers recovery.
5. Generate Summary and Action items on demand through the configured `TextModel`; audio stays local and transcript text follows the user's configured provider.
6. The shared WhisperKit instance serves dictation first. Meeting work runs in approximately 30-second chunks and yields to queued dictation between chunks, including during the final pass.
7. Skip meeting chunks only when no 100 ms window exceeds RMS `0.003`; strip placeholders and run `HallucinationFilter` on every chunk. Echo is a known risk; the manual checklist recommends headphones.
8. Long transcript generation splits within the configured context budget (default 8,192 tokens), summarizes parts then merges them, uses a separate Meetings output limit (default 2,048 tokens), reports progress, and supports cancellation.

