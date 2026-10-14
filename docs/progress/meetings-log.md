# Meetings implementation log

## Summary

Tasks 1–13 are complete on branch `feat/meetings`. Task 13 handoff commit: `1d76c42` (`docs: record meetings implementation handoff`). The branch is not merged or pushed.

- **Tests:** final `swift test` passed 181 VoiceCore tests in 26 suites and 26 BugVoiceMac tests in 7 suites. Task commits ran the full suite before committing.
- **Build and launch:** `Scripts/build-app.sh` passed and signed with `Bugler Local Dev`. Info.plist contains `NSAudioCaptureUsageDescription`. `build/BugVoice.app` launched as PID 68193; Core ML model resources were mapped in the process. No meeting recording was started.
- **Decisions:** keep one stable transcription router and drain the old priority queue before swapping engines; only retry `vi` on an empty gated auto result; dedupe only across same-track chunk boundaries; persist per-chunk detected language and progress; keep echoed You lines and recommend headphones; retain journals until durable final audio/manifest; use 180 bounded waveform peak buckets; automatically prune ready meetings only.
- **UNVERIFIED on device:** System Audio Recording prompt/denial behavior, process-tap capture, self-audio exclusion, aggregate input conversion, recorder focus retention, sleep/quit/crash recovery, actual AAC playback, export dialogs, summary cancellation, and an end-to-end dictation interaction. The app launch and model-resource mapping were verified, but visual UI inspection was denied by CUA approval review.
- **Manual checks needed:** all existing Dictation rows 1–44 remain pending; Meetings rows 45–62 are added with blank Result cells. Run the Task 8a spike steps in this log before relying on system audio capture. The sub-project 1 benchmark and deferred-findings review also remain pending.

## Task log

| Task | Implementation commit | Tests |
| --- | --- | --- |
| 1 | `eef8b85` — `feat(core): add meeting manifest storage` | 131 VoiceCore + 17 BugVoiceMac passed |
| 2 | `0c003cc` — `feat(core): add durable meeting journal rules` | 136 VoiceCore + 17 BugVoiceMac passed |
| 3 | `f58b374` — `feat(core): prioritize dictation transcription` | 141 VoiceCore + 17 BugVoiceMac passed |
| 4 | `b100d8e` — `feat(core): process meeting transcript chunks`; `b01f719` — `fix(core): constrain meeting overlap deduplication` | 149 VoiceCore + 17 BugVoiceMac before requested fixes; 151 VoiceCore + 17 BugVoiceMac after fixes |
| 5 | `458077b` — `feat(core): generate long meeting summaries in parts` | 158 VoiceCore + 17 BugVoiceMac passed |
| 6 | `b303bd0` — `feat(core): export meeting transcripts and map timeline seeks` | 163 VoiceCore + 17 BugVoiceMac passed |
| 7 | `aa9f45d` — `feat(core): model meeting lifecycle and recovery` | 171 VoiceCore + 17 BugVoiceMac passed |
| 8a | `d8aa190` — `docs: add system audio tap spike and maintainer steps` | 171 VoiceCore + 17 BugVoiceMac passed; spike built but not launched |
| 8b | `dec343f`, `c3e9828` — audio journals and periodic durable checkpoints | 172 VoiceCore + 25 BugVoiceMac passed |
| 8c | `fd99d5c` — `feat(app): finalize meeting tracks and mixed playback` | 171 VoiceCore + 24 BugVoiceMac passed |
| 9 | `2c5ee82` — `feat(app): wire meetings and shared transcription`; log `618ba55` | 172 VoiceCore + 26 BugVoiceMac passed |
| 10 | `cada987` — `feat(app): add floating meeting recorder`; log `8a1dbd9` | 174 VoiceCore + 26 BugVoiceMac passed |
| 11 | `a53003d` — `feat(app): add meetings library and playback`; log `fe96bb0` | 177 VoiceCore + 26 BugVoiceMac passed |
| 12 | `d404ecf` — `feat(app): add meeting settings and recovery`; log `92577b7` | 181 VoiceCore + 26 BugVoiceMac passed |
| 13 | `1d76c42` — `docs: record meetings implementation handoff`; final log entry in follow-up | 181 VoiceCore + 26 BugVoiceMac passed; signed app built and launched |

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

### Task 10 — non-activating recorder panel

- Implementation commit: `cada987` — `feat(app): add floating meeting recorder`.
- Test-first evidence: `MeetingRecorderPresentationTests` first failed to compile because the VoiceCore presentation policy did not exist. Added tests for action availability in idle/recording/paused/transcribing states and for preserving the latest valid transcript line after empty or filtered chunks. Focused tests passed; full `swift test` passed 174 VoiceCore + 26 BugVoiceMac tests; `swift build --product BugVoice` passed.
- The panel uses a floating, non-activating `NSPanel`, a hosting view that declines first-responder status, and `orderFrontRegardless`; it does not call `makeKeyAndOrderFront` or activate BugVoice. It is positioned at the top of the main screen and repositions when display parameters change. Stop hides the panel immediately while session final transcription continues.
- Decision beyond the plan: the app executable is not an importable test target, so panel action availability and latest-line retention were factored into Foundation-only `VoiceCore` and the view renders that policy. Cost if wrong: app controller state could drift from the tested presentation state mapping; the view derives this enum directly from the controller's four booleans.
- Skipped/unverified: did not launch the app to check focus retention or click the panel during a real dictation. Panel non-activation and screen movement remain manual checks for the final checklist. No UI automation or audio capture was run.
- Open questions: none beyond the panel focus manual check and the outstanding Task 8a device checks.

### Task 11 — meetings library, detail, player, and exports

- Implementation commit: `a53003d` — `feat(app): add meetings library and playback`.
- Test-first evidence: `MeetingListProjectionTests` first failed to compile because the projection and list/delete store APIs did not exist. Added three tests for newest-first local-day groups and Today/Yesterday labels, case-insensitive title/transcript search, and deletion disappearing from store listings. Full `swift test` passed 177 VoiceCore + 26 BugVoiceMac tests; `swift build --product BugVoice` passed.
- Detail includes transcript, summary and action-item tabs; configured text-model generation uses the Task 5 budget/progress/cancel path and persists to `meeting.json`. Player has decoded-audio peak waveform scrubbing, play/pause, ±15 seconds, speed choices 0.75× through 2×, clickable `m:ss – m:ss` transcript rows, and playback-only current-row highlighting. Export writes Markdown, SRT, or the mixed AAC file; rename, confirmed delete, and Show in Finder are present.
- Decisions beyond the plan: waveform reads audio sequentially into 180 peak buckets, keeping memory bounded for long recordings. A `.none` text-model setting reports “Choose a text model in Settings before generating meeting notes.” Store listing surfaces a corrupt or unsupported manifest as a load error instead of silently hiding that meeting. Cost if wrong: one unreadable folder can prevent the list from loading; this preserves the schema error instead of making a meeting disappear without explanation.
- No manual playback, export dialog, or summary request was run. The test suite exercises the deterministic projection/export/timeline code; real AAC playback and GUI behavior remain manual checks.
- Open questions: complete the playback/export manual checks and Task 8a system-audio checks on device.

### Task 12 — settings, storage, recovery, and retention

- Implementation commit: `d404ecf` — `feat(app): add meeting settings and recovery`.
- Test-first evidence: `MeetingRecoveryPolicyTests` initially failed to compile because the recovery policy was missing. It now covers old settings default decoding, meeting settings round-trip, and the available recovery action for each lifecycle state. `MeetingSessionTests` covers retrying an interrupted recording and persisting in-progress transcript percent. Full `swift test` passed 181 VoiceCore + 26 BugVoiceMac tests; `swift build --product BugVoice` passed.
- Startup marks stale recording/paused manifests interrupted without deleting journals. Recover truncates uncheckpointed tails, transcribes bounded chunks, finalizes AAC, and preserves source journals on failure. Incomplete transcription can retry; an active retry can cancel and wait for the in-flight chunk. Progress is durably written after each final chunk so the library can show a percentage.
- Settings include Never/30/90/365 day deletion and separate context/output token controls. Retention uses `MeetingRetention.pruneCandidates`, which selects ready meetings only. Storage shows meeting count, allocated size, and Finder access; the recursive directory size includes `.capture` journals.
- Decision beyond the plan: persist transcript progress after every final chunk rather than only in memory. Cost if wrong: this adds one durable manifest replacement per roughly 30-second chunk, trading small metadata I/O for accurate restartable list status.
- No manual settings persistence, storage-size, sleep, quit, or crash recovery run was performed. Those remain checklist checks. A future-schema or corrupt manifest can make `MeetingStore.list()` fail as noted in Task 11, leaving all meetings visible only after the manifest is repaired.
- Open questions: complete the storage/recovery manual checks and the Task 8a device checks.

### Task 13 — manual checklist, handoff, and final build

- Documentation commit: `1d76c42` — `docs: record meetings implementation handoff`; final summary is recorded above.
- Added Meetings manual rows 45–62 with blank Result cells, updated Handoff and `AGENTS.md` status for merged sub-project 1 and the unmerged `feat/meetings` branch.
- Final verification: `swift test` passed 181 VoiceCore tests in 26 suites and 26 BugVoiceMac tests in 7 suites. `Scripts/build-app.sh` succeeded and signed the app with `Bugler Local Dev`. The built Info.plist contains `NSAudioCaptureUsageDescription` and retains `LSUIElement`.
- Launched `build/BugVoice.app` once. PID 68193 remained running. Unified logs showed Core ML runtime activity and `lsof` showed mapped `bnns_program.bnnsir` model resources in BugVoice, confirming speech-model initialization reached model loading. No meeting recording was started.
- UI inspection via CUA was denied with “Computer Use was not approved to use BugVoice.” The process and model resources were verified through read-only process/log inspection, but no visual UI state or dictation interaction was confirmed. Do not report the manual checklist as run.
- Unverified on device: System Audio Recording prompt/denial behavior, process-tap capture and self-audio exclusion, aggregate input conversion, recorder focus retention, sleep/quit/crash recovery, actual AAC playback, export dialogs, and end-to-end dictation interaction. Exact spike run steps remain above in Task 8a.
- No other skipped automated checks. The app process remains open after the required launch check.
