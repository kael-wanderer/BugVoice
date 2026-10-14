# Meetings implementation log

## Summary

Continuous implementation is in progress. Tasks 1–3 and Task 4 are complete. Tasks 5–13 remain. No on-device system audio permission or process-tap capture has been tested; Task 8a instructions and all related assumptions will be recorded as **UNVERIFIED on device**. Final `swift test`, app build, launch, and dictation initialization check remain pending.

## Task log

| Task | Implementation commit | Tests |
| --- | --- | --- |
| 1 | `eef8b85` — `feat(core): add meeting manifest storage` | 131 VoiceCore + 17 BugVoiceMac passed |
| 2 | `0c003cc` — `feat(core): add durable meeting journal rules` | 136 VoiceCore + 17 BugVoiceMac passed |
| 3 | `f58b374` — `feat(core): prioritize dictation transcription` | 141 VoiceCore + 17 BugVoiceMac passed |
| 4 | `b100d8e` — `feat(core): process meeting transcript chunks`; `b01f719` — `fix(core): constrain meeting overlap deduplication` | 149 VoiceCore + 17 BugVoiceMac before requested fixes; 151 VoiceCore + 17 BugVoiceMac after fixes |

### Task 4 fixes

- Fix commit: `b01f719` — `fix(core): constrain meeting overlap deduplication`.
- Test-first evidence: new tests initially failed to compile because the configured-language argument, chunk provenance, and chunk-based merge API did not exist. After implementation, `swift test --filter MeetingTranscriptionTests` passed 10 tests; full `swift test` passed 151 VoiceCore + 17 BugVoiceMac tests.
- Decisions beyond the plan: source chunk provenance is optional on `MeetingSegment` so existing manifest data and non-chunk producers can decode/use segments; the merger accepts chunk results and uses per-track ordered chunks. This keeps provenance scoped to meeting transcription. Cost if wrong: legacy segment rows without provenance cannot participate in overlap deduplication, so a repeated boundary phrase from old manifests may remain duplicated.
- No skipped checks. The WhisperKit non-Sendable warning remains pre-existing.
- Open questions: none for Task 4.

## Deferred verification and manual checks

- Task 8a: maintainer must run the spike with audible system audio and approve the macOS System Audio Recording prompt. Verify capture, self-audio exclusion, and denial behavior (error versus silent buffers). Until then mark the process tap, aggregate-device routing, and denial handling **UNVERIFIED on device**.
- Final manual checklist rows, app launch, dictation initialization, and device-only permission/audio checks are pending.

### Task 5 — long transcript summary and action items

- Commit: `458077b` — `feat(core): generate long meeting summaries in parts`.
- Tests: 7 `MeetingTextGenerationTests` passed; full suite passed 158 VoiceCore + 17 BugVoiceMac tests.
- Decisions beyond the plan: no `Settings.swift` edit was needed because `MeetingSettings` already stores independent context/output values; `MeetingTextBudget(settings:)` clamps them at the generation boundary, including older or malformed settings. Part size estimates include timestamp/speaker markers at three characters per token, not only transcript text. If the model returns merge text too large to fit the next context window or does not reduce the number of merge inputs, generation throws `mergeDidNotReduceToFitContext` rather than submitting an over-budget request. Cost if wrong: generation can fail for a model that produces unusually long partial results; the user can retry with a smaller output budget or a model that compresses merge results.
- No skipped checks. Cancellation is cooperative between model calls; progress reports completed part and merge calls. Persistent saving is intentionally left to app integration tasks.
- Open questions: none for Task 5.

### Task 6 — export formatting and timeline mapping

- Commit: `b303bd0` — `feat(core): export meeting transcripts and map timeline seeks`.
- Tests: 2 `MeetingExportTests` and 3 `MeetingTimelineTests` passed; full suite passed 163 VoiceCore + 17 BugVoiceMac tests.
- Decisions beyond the plan: Markdown dates use a stable UTC timestamp; transcript line breaks are flattened to spaces in Markdown and SRT so each cue remains one readable line. Cost if wrong: users in other time zones may prefer local time; the stored date remains authoritative and export formatting can be changed without data migration.
- No skipped checks; SRT uses millisecond rounding and timeline intervals are start-inclusive/end-exclusive.
- Open questions: none for Task 6.

### Task 7 — meeting lifecycle and retention

- Commit: `aa9f45d` — `feat(core): model meeting lifecycle and recovery`.
- Tests: 8 `MeetingSessionTests` passed, including capture rollback, pause-gap timing, marks, final chunks, checkpoint-based recovery, transcribing retry, and Stop/Cancel waiting for the active chunk; full suite passed 171 VoiceCore + 17 BugVoiceMac tests. Existing `MeetingJournalTests` continue to cover retention cutoffs and active-state exclusions.
- Decisions beyond the plan: `MeetingSession` awaits a `MeetingTranscriptionScheduler.transcribeFinal(..., chunkSeconds: 30)` operation; its adapter is responsible for queuing bounded chunks and returning only after submitted work completes. Recovery duration uses the greatest per-track committed checkpoint end offset. The session clock is an injected wall clock, with pause intervals excluded from elapsed duration. Cost if wrong: wall-clock changes during one active recording can skew duration; a monotonic clock adapter can replace the injected implementation without changing the session API.
- Cancellation removes queued meeting work and waits on scheduler in-flight completion before stopping capture and persisting `.interrupted`. A racing Stop observes cancellation and skips finalization.
- No skipped checks. Audio-source, scheduler, and finalizer production adapters are intentionally left to app tasks.
- Open questions: none for Task 7.

### Task 8a — process-tap spike

- Commit: `d8aa190` — `docs: add system audio tap spike and maintainer steps`.
- Verification: `swiftc -typecheck Scripts/meeting-audio-tap-spike.swift` passed; `Scripts/build-meeting-audio-tap-spike.sh` built and verified a signed app bundle with `Bugler Local Dev`; it was not launched. `swift test` passed 171 VoiceCore + 17 BugVoiceMac tests.
- Apple documentation supports creating a tap with `AudioHardwareCreateProcessTap`, attaching its UID to a private aggregate device tap list, and expecting the System Audio Recording prompt on first recording start. The spike excludes its own Core Audio process object and plays a BugVoice-owned Glass sound during the capture window.
- Maintainer run steps: (1) from the repo root run `Scripts/build-meeting-audio-tap-spike.sh`; (2) run `./.build/MeetingAudioTapSpike.app/Contents/MacOS/MeetingAudioTapSpike` in Terminal; (3) approve the System Audio Recording prompt; (4) observe the automatic Glass sound and confirm it produces no RMS output; (5) play audio from another app and confirm positive RMS lines; (6) quit with Return; (7) revoke the app's System Audio Recording permission in System Settings → Privacy & Security → System Audio Recording, rerun, deny access, and record whether tap/device start returns an OSStatus error or yields silent buffers. Record macOS build, each result, and any API adjustment in the spec.
- **UNVERIFIED on device:** System audio capture, exclusion of BugVoice's own sound, permission prompt behavior, and denial behavior were not exercised. The aggregate tap dictionary shape and Float32 mono interpretation are compile-checked but runtime-unverified.
- Decision: compile and sign the spike without launching it; this avoids consuming the maintainer's one-time OS permission decision. Cost if wrong: the first runtime attempt could reveal a compile-clean Core Audio setup error; the spike can be adjusted and rerun before production integration review.
- Open question for maintainer's later run: does permission denial return an error at tap start or produce silent buffers?


### Task 8b — PCM journals and capture sources

- Commits: `dec343f` — `feat(app): journal meeting microphone and system audio`; `c3e9828` — `fix(app): checkpoint meeting journals during capture`.
- Tests: 5 `MeetingAudioCaptureTests` and 1 `AppBundleUsageDescriptionTests` passed, including the one-second checkpoint timer. `swift build --target BugVoiceMac` and `swift build --product BugVoice` passed; `plutil` confirmed the usage description. Full suite passed 172 VoiceCore + 25 BugVoiceMac tests.
- Durability: each journal is synchronized before a durable checkpoint file replacement; checkpoint temporary file and containing directory are fsynced. Manifest writes synchronize the same-directory temporary file before `FileManager.replaceItemAt` / move. Recovery truncates uncheckpointed tails and clamps checkpoint claims to actual even-byte file lengths.
- Decisions beyond the plan: the engine consumes an aggregate device through `AVAudioEngine`'s input node and converter, rather than maintaining a custom Core Audio IOProc in production. The disposable spike keeps the explicit IOProc. This reuses the app's existing audio conversion path while keeping system tap creation separate. Cost if wrong: the aggregate device may not expose an input format AVAudioEngine accepts; the on-device spike/manual run is still required before trusting this path.
- Permission handling presently fails immediately when Core Audio returns an error. If macOS instead supplies silent buffers after denial, true silence and denial cannot be distinguished reliably from buffers alone; this remains **UNVERIFIED on device** and is an open question for the maintainer's spike run.
- No audio capture was launched. All process tap behavior, TCC prompt/denial behavior, actual capture, self-audio exclusion, aggregate input format, and physical-device format conversion remain **UNVERIFIED on device**.
- Open maintainer check: run the exact steps above before release; record actual macOS build, audio-present RMS, excluded Glass sound, and denial result in spec/log.

### Task 8c — AAC finalizer and mix

- Commit: `fd99d5c` — `feat(app): finalize meeting tracks and mixed playback`.
- Tests: 2 `MeetingAudioFinalizerTests` passed for separate AAC tracks, unequal source lengths, silent-track padding, mixed duration, and journal retention after failure; full suite passed 171 VoiceCore + 24 BugVoiceMac tests. `swift build --product BugVoice` passed.
- Decision beyond the plan: use AVFoundation's AAC encoder defaults at 16 kHz mono. An explicit 64 kbps setting was rejected by the system converter for this stream; default AAC settings encode successfully. Cost if wrong: encoded file size/quality differs from a fixed bitrate target; the source is speech and output remains AAC.
- Finalization synchronizes each AAC file and directory, durably saves the finalized manifest, and removes `.capture` only after all outputs and manifest are saved. A failure leaves journals for retry.
- Skipped/unverified: no actual captured recording was played through speakers; tests used synthetic PCM and decoded AAC duration. On-device audio output and process-tap source capture remain **UNVERIFIED on device**.
- Open maintainer check: play `audio.m4a`, `mic.m4a`, and `system.m4a` after completing the Task 8a permission/capture run.

### Task 9 — permission state, app model, and menu controls

- Implementation commit: `2c5ee82` — `feat(app): wire meetings and shared transcription`.
- Tests: the `TranscriptionRouterTests` replacement test proves the old in-flight and queued requests complete on the old priority transcriber, while a request arriving during replacement is routed to the new pair. `MeetingPermissionTests` proves System Audio Recording has no Screen Recording preflight and does not gate dictation. Full `swift test` passed 172 VoiceCore + 26 BugVoiceMac tests; `swift build --product BugVoice` passed.
- Decisions beyond the plan: AppModel holds a stable `TranscriptionRouter` because the dictation pipeline and meeting scheduler retain their transcriber reference. A replacement closes the router to new routing, drains the old `PriorityTranscriber`, then installs the new pair and releases held requests. Engine/model fields are published only after this drain. This adds a small buffering layer during model changes; cost if wrong: queued requests wait until all old meeting chunks finish, but no request is stranded or silently sent to a mixed engine/model pair.
- The System Audio Recording row has no status preflight and says “Requested when the first meeting starts.” Successful capture marks it granted for the current run; a Core Audio tap-start error is reported at meeting start and leaves dictation available. Cost if wrong: if macOS reports denial only as silent buffers, the app cannot distinguish denial from genuine silence.
- Menu recording controls call the meeting controller while the existing dictation hotkey, HUD and paste pipeline continue through the shared router. Ctrl-Option-M is registered as a global shortcut; the duplicate SwiftUI menu shortcut was removed to avoid dispatching the toggle twice.
- No test failure remains. Process-tap capture and permission denial behavior remain **UNVERIFIED on device** per Task 8a; the spike was not launched. No dictation-specific manual interaction was run during this task.
- Open questions: none for Task 9 beyond the Task 8a maintainer run listed above.
