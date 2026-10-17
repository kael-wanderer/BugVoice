# Meetings implementation log

## Summary

Tasks 1–13 and whole-branch review items 1–8 are implemented on `feat/meetings`. Follow-ups `4a50d61`, `9adf72f`, and `570b31c` address short failed starts, failed-pass manifest rebasing, and inactive provider reloads. The branch is not merged or pushed.

- **Tests:** final `swift test` passed 192 VoiceCore tests in 26 suites and 27 BugVoiceMac tests in 7 suites (219 total).
- **Build and launch:** final `Scripts/build-app.sh` succeeded with `Bugler Local Dev`; the rebuilt Info.plist contains `NSAudioCaptureUsageDescription`. `build/BugVoice.app` launched as PID 26981, and `lsof` showed mapped Core ML `bnns_program.bnnsir` resources. No meeting recording or dictation interaction was started.
- **Review decisions:** refresh the provider when selected-engine factory inputs change; read each live chunk once and retry its cursor if reading fails; keep one `MeetingSession` owner for active manifest changes; on sleep pause and stay paused; on quit checkpoint into retryable `.interrupted`; remove failed starts with less than one second of committed audio; stream AAC and mix in one-second blocks; save `.ready` before removing journals; link to Privacy & Security after capture start fails.
- **UNVERIFIED on device:** first System Audio Recording prompt and denial behavior; process-tap capture, self-audio exclusion, and aggregate input conversion; the `Privacy_ScreenCapture` System Settings anchor; recorder focus, sleep/wake and quit dialogs; crash recovery; playback/export dialogs; and end-to-end dictation while recording. The spike bundle was rebuilt with `Bugler Local Dev` but not launched because the prompt requires maintainer approval.
- **Manual checks needed:** Dictation rows 1–44 and Meetings rows 45–62 remain pending with blank Result cells. The spike run steps are below. The sub-project 1 benchmark and deferred-findings review remain outside this work.

## Whole-branch review fixes

### 1. Refresh dictation providers for all factory inputs

- Fix commit: `9c6b970` — `fix(app): refresh transcriber for speech settings and key changes`.
- Test-first: the new `SpeechTranscriberConfiguration` test first failed to compile because the configuration policy did not exist. It verifies engine, Whisper model, server URL/model, and a non-secret speech-key generation trigger replacement; language, vocabulary hints, and microphone UID do not.
- `swift test` passed after implementation (182 VoiceCore tests and 26 BugVoiceMac tests; 208 total). Existing router replacement continues to drain queued work before swapping.
- Decision: track only a monotonically increasing speech-key generation, never the API key or its hash in the configuration. Saving `speech-openai` increments it and refreshes the pair.
- No item-specific manual test was run.

### 2. Schedule only new meeting chunks off MainActor

- Fix commit: `1ae3a93` — `fix(app): avoid repeated meeting journal reads on main actor`.
- Test-first: `MeetingLiveChunkCursor` coverage first failed to compile because the cursor was absent; it verifies completed chunks are returned once, partial trailing chunks wait, and tracks advance independently.
- `swift test` passed after implementation (183 VoiceCore tests and 26 BugVoiceMac tests; 209 total).
- The MainActor monitor now uses lock-only writer sample counts and a per-track cursor. Journal reads run on the writer queue; checkpoint/fsync remains on the writer's timer.
- No item-specific manual test was run.

### 3. Give active meetings one manifest owner

- Fix commit: `fce94cc` — `fix(core): serialize meeting manifest updates and finalization`.
- Test-first: tests for rename during blocked final transcription, concurrent mark/interim persistence, and pause/mark preserving interim segments first failed to compile because the session mutation APIs were missing. Added all mutations to `MeetingSession`; the live scheduler and AppModel now route active-meeting writes through it.
- `swift test` passed (187 VoiceCore tests and 26 BugVoiceMac tests; 213 total).
- The finalizer no longer saves `meeting.json` independently. While finalization is awaiting audio work, the session keeps concurrent title and generated text changes and merges them into the ready manifest.
- Decision: the same commit also implemented review item 7 because both fixes depend on session ownership of the finalization manifest. Finalizer AAC creation returns without deleting `.capture`; the session durably saves `.ready` first, then asks the finalizer to remove journals. A VoiceCore test observes the saved state at cleanup time.
- No manual concurrent rename/summary interaction was run.
- Follow-up commit `27551bb` adds a deterministic blocked-pause/interim test. It first failed because `pause()` overwrote the newer manifest after awaiting audio I/O; pause, resume, stop, and cancel now rebase after awaited work. The full suite passed with 191 VoiceCore + 27 BugVoiceMac tests.

### 4. Checkpoint before sleep and quit

- Fix commit: `5a1f185` — `fix(app): checkpoint meetings before sleep and quit`.
- Test-first: VoiceCore tests first failed to compile because the explicit sleep-pause operation did not exist. Tests now verify sleep leaves the session paused without resuming, and quit-stop writes a durable interrupted state.
- `swift test` passed (189 VoiceCore tests and 26 BugVoiceMac tests; 215 total).
- `NSWorkspace.willSleepNotification` calls the durable pause path. The quit alert provides “Stop and keep” and “Cancel”; the keep action waits for the in-flight chunk and `cancel()` checkpoints an interrupted manifest before `terminateNow` is replied.
- During final transcription, stop has already persisted `.transcribing`; quitting leaves the journals and retryable state. No final-pass prompt is shown.
- Sleep/wake and quit dialogs were not manually exercised. They remain manual checks.

### 5. Remove failed starts with no committed audio

- Fix commit: `481fea9` — `fix(core): remove empty failed meeting folders`.
- Test-first: updated the source-start failure test to require an empty store and one deletion; it failed because the failed manifest remained. Added coverage proving a failed start with committed PCM remains available as `.failed`.
- `swift test` passed (190 VoiceCore tests and 26 BugVoiceMac tests; 216 total).
- The audio coordinator retains its last durable checkpoint after rolling back a partial source start so the session can distinguish a truly empty folder from a partial recording.
- No item-specific manual test was run.

### 6. Stream AAC finalization in bounded blocks

- Fix commit: `541070e` — `fix(app): stream meeting journals into AAC files`.
- Test-first: bounded journal-reader coverage first failed to compile because no sequential reader API existed. It verifies 16,000-sample reads, remaining counts, and PCM fidelity within Int16 quantization.
- `swift test` passed (190 VoiceCore tests and 27 BugVoiceMac tests; 217 total). Existing AAC duration/mix coverage also passed.
- The finalizer streams mic and system AAC separately, then reopens both journals and mixes one-second blocks into the playback AAC. Memory use is bounded by those blocks and AVAudioFile buffers.
- Long-duration memory profiling was not run.

### 8. Open System Settings after a System Audio Recording failure

- Fix commit: `8a104d3` — `fix(app): open system audio recording settings after denial`.
- The System Audio Recording row now shows “Open System Settings” after process-tap start failure and opens Privacy & Security → Screen & System Audio Recording. The row still describes the initial request timing before a failure.
- `swift test` passed (190 VoiceCore tests and 27 BugVoiceMac tests; 217 total).
- The settings deep link and prompt were not manually exercised.

### 2. Cursor acknowledgement follow-up

- Fix commit: `1cc94d0` — `fix(core): advance live cursors only after enqueue`.
- Updated the VoiceCore cursor test to prove the same range remains pending until explicitly marked sent. The controller acknowledges a range only after its background read succeeds and it is enqueued, so a read error retries on the next monitor tick.
- Full `swift test` passed (191 VoiceCore tests and 27 BugVoiceMac tests; 218 total).

### Review follow-ups

- **a — Commit `4a50d61` (`fix(core): discard subsecond failed meeting starts`).** The system-start-failure test now represents the real ordering: mic commits 10 ms of PCM before the system tap fails. It first failed because the session retained a failed folder. Startup rollback now deletes folders when neither track has one second of committed samples, and keeps a failed meeting with at least one second. Full `swift test` passed with 191 VoiceCore + 27 BugVoiceMac tests (218 total).
- **b — Commit `9adf72f` (`fix(core): preserve meeting edits after transcription failure`).** A test renames the meeting during a blocked final pass and then makes that pass fail. The test first failed because the catch path restored the original title. The catch now rebases the `.transcribing` error state on the latest in-memory manifest. Full `swift test` passed with 192 VoiceCore + 27 BugVoiceMac tests (219 total).
- **c — Commit `570b31c` (`fix(app): skip inactive speech provider reloads`).** The configuration test first failed when inactive server fields and a credential-generation change modified a WhisperKit configuration. Configuration now compares only the selected engine's model/server/key-generation inputs; saving `speech-openai` only rebuilds when `.openAICompatible` is selected. The test also checks OpenAI mode ignores the inactive Whisper model. Full `swift test` passed with 192 VoiceCore + 27 BugVoiceMac tests (219 total).
- **d — Log update.** The System Settings `Privacy_ScreenCapture` anchor remains **UNVERIFIED on device**; it has not been opened on the maintainer's Mac.

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
- **Device result (2026-10-16, macOS 27.0.1 build 26A434):** the maintainer ran the spike twice. Run 1 showed the System Audio Recording prompt; after approval, YouTube playback in the browser produced RMS lines (0.002–0.38) that followed the video. Run 2 did not prompt again; with nothing else playing, the spike's own Glass sound was audible and printed no RMS lines, so self-exclusion works. **Verified:** process-tap capture, aggregate tap dictionary, Float32 mono reading, first-run prompt, self-audio exclusion. **Still unverified:** denial behavior (error versus silent buffers); the deny run was skipped. The production `AVAudioEngine` aggregate-input path is checked by Meetings rows 45–48.


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

## Meeting speakers — Part 1 (2026-10-17)

Implemented on `feat/meeting-speakers` in `../BugVoice-meeting-speakers`, from
`main`. Spec: `docs/superpowers/specs/2026-10-17-meeting-speakers-design.md`;
plan: `docs/superpowers/plans/2026-10-17-meeting-speakers.md`.
Part 1 is implemented pending device checks; Part 2 is not implemented.

Tuning pending: needs the owner's test clips (2, 3, 4 people).

`SpeakerSplitter.Tuning.clusterDistanceThreshold` and `minClusterSize` stay nil.
No owner audio or application data was read, changed, played, or sent anywhere.
The app was built and signed, not launched. SpeakerKit's first-use model download
and real-audio inference remain unverified. The initial baseline was explicitly
authorized to finish fetching the pinned Swift package dependencies.

### Automated verification and task review

- Baseline: 619 VoiceCore tests / 75 suites and 84 BugVoiceMac tests / 16 suites passed.
- Task 1: older-file defaults, display-name override, split-state round trips,
  speaker carry-over. Tests first failed on the missing API; full run passed
  623 VoiceCore + 84 BugVoiceMac tests before commit.
- Task 2: all planned placement, split, name transfer, edit, people, notice,
  export and search assertions. Tests first failed on the missing API; full
  run passed 634 VoiceCore + 84 BugVoiceMac tests before commit.
- Task 3: session routing, interrupted-state refusal, summary stamp. Tests
  first failed on the missing session method; full run passed 637 VoiceCore
  + 84 BugVoiceMac tests before commit.
- Task 4: builds and tests passed (637 + 84); `git diff main -- Package.resolved`
  was empty. SpeakerKit comes from WhisperKit 1.1.1. Model notice copied verbatim.
- Task 5: builds and tests passed (637 + 84). `Scripts/build-app.sh` succeeded,
  signed with `Bugler Local Dev`. Recording/inspection step skipped as requested.
- Task 6: UI built from the HTML source, using spec section 10 for copy. Full
  tests passed (641 VoiceCore / 76 suites + 84 BugVoiceMac / 16 suites).
  `Scripts/build-app.sh` succeeded, signed with `Bugler Local Dev`.
  Running-app walkthrough, screenshots and test recordings skipped as requested.
- Task 7: documentation and pending device checklist recorded; final `swift test`
  passed 641 VoiceCore / 76 suites + 84 BugVoiceMac / 16 suites.
- Each task reviewed against its interfaces/assertions and the plan's five
  Review Focus items. The plan has no separate Self-Review section.
- Test and build output is saved in `/tmp/bugvoice-speakers-*.log` for this session.

### Minimal plan adaptations and open choices

- Superpowers workflow skills waived by the owner; executed the plan directly.
  Browser requirement waived; read the HTML markup and CSS instead.
- There is no `MeetingExport` type or `JSONDecoder.meeting` helper. Used
  `MeetingExporter`, the standard JSON decoder and an encoded manifest with
  all new keys removed to exercise older-file decoding.
- Session pseudocode helpers were not present. Built `readyRecordedSession`
  with the existing `SessionRig`/store/recover path and used start/cancel to
  construct the interrupted case. No capture device is involved.
- Empty New person names use `EditError.duplicateName("")` because the fixed
  error interface has no empty-name case; the UI keeps an empty field open.
  Equal-distance/identical-start placement ties use the voice ID as the final
  deterministic tie-breaker. Name-transfer ties use old ID, then new index.
  The general empty-rename rule applies to manual pN speakers too; their unnamed
  fallback is Other N, with the same duplicate-name validation as other speakers.
- Only speakers with lines are retained, including You. Microphone-only
  recordings get an empty system-track split (You only) without model inference,
  as required by spec section 9. The first counted call split includes the
  owner when converting People to a voice count even before speaker records exist.
- Reused `FlowLayout` for wrapping chips, dynamic AppKit colours for the exact
  six light/dark palettes, and the AppModel environment for the new views.
  Added speaker metadata to the meeting-window controller and its view call
  site, since read-only colours need the manifest's speaker records.
  Chips are displayed in first-line order, with You first, after line edits too.
  The timestamp uses the mockup's start-only column; time and text retain seeking.
- Review found that the summary chunker constructed fresh segments for long
  lines and lost speaker fields. Added a failing regression test, then carried
  ID/name onto fragments so all summary/action-item prompts retain names.
- Review found that assigning a line between existing speakers did not change
  the name map, leaving the summary falsely current. Added a failing test,
  then invalidated `speakerNamesAtSummary` for line assignments. Notice dismissal
  also tracks line assignments, so the next fix shows it again without adding
  persisted fields.
- Review Focus 1 exposed another rebuild before the final carry-over pass:
  `persistFinal` (and the corresponding `persistInterim`) merged fresh segments.
  Added a failing actual-session retry test, then used the existing carry-over
  rule at both rebuilds. This also preserves translations at those boundaries.

- Recovery previously transcribed without generating a final summary. It now requests
  the summary after the split even without a visible window, matching spec section 4.
  Summary failure does not relabel successful transcription as a transcript failure.
- Deleting a meeting drains its running split before deleting the folder, preventing
  a late session save from recreating it. Focus-loss rename and New person submissions
  are disabled when splitting starts, including an already-open popover.

- The plan's inspection/older-meeting step uses literal JSON statuses (`"done"`,
  `"none"`). Synthesized enum Codable instead used objects. Added a failing
  format regression, then encoded none/running/done as strings and failure as
  `{ "failed": "message" }`. All split-state round-trip tests still pass.

### Device checklist — speakers (pending)

| # | Check | Result |
|---|---|---|
| 195 | Stop a recording with multiple guests: split runs after final transcription and before summary; microphone stays You and call lines become Other N. | Pending |
| 196 | Upload a recording with multiple people: all file lines are split, nobody is forced to You. | Pass 2026-10-17 (two-voice `say` clip; first use downloaded the 11 MB model; automatic count found 4) |
| 197 | People −/+ stays within bounds, confirms before splitting again, clears line fixes, and carries names to the closest voices; shows the actual resulting count. | Pass 2026-10-17 (upload; 4 to 2 and back, Dani carried) |
| 198 | Rename each chip (including You), save with Return or focus loss, cancel with Escape, and clear to restore its default; every line changes. | Pending |
| 199 | Duplicate names, including case/space variations, are refused without merging speakers; inline error uses the name. | Pending |
| 200 | Move one line to another speaker, including microphone lines; other lines stay unchanged and empty speakers disappear. | Pending |
| 201 | New person creates a named chip, moves only the chosen line, and gives its lines the matching colour. | Pass 2026-10-17 (upload) |
| 202 | Markdown, SRT, Send to Scratchpad and meeting search use speaker names; translation stays on its line. | Pending |
| 203 | Ask, What did I miss, summary and action-item prompts use speaker names. | Pending |
| 204 | Rename/fix shows the names-changed notice; Not now lasts until the next change; revisiting and Regenerate summary use the saved stamp. | Pending |
| 205 | Older meeting loads without new fields, Find speakers works, failure offers Try again, and silence leaves unplaced call lines as Others. | Pending |
| 206 | Finished meeting window shows matching names/colours read only; while splitting it keeps Others, then updates; later session saves do not overwrite edits. | Pending |

Review fixes, 2026-10-17 (maintainer session): a split left `running` by a quit
now shows "Speakers could not be found." with Try again; the speaker row shows
only on ready meetings (no "recorded before" banner while recording); recovery
clears transcribing before the split and summary; the summary stamps the names
it was generated with; a recorded call keeps the 2-person minimum when You owns
no line and never asks SpeakerKit for 0 voices; a microphone-only meeting is
fixed at 1; clearing a New person's name keeps it; picking a line's current
speaker changes nothing; the stepper steps from the pending number (4 to 2 is
one confirm); the speaker row sits outside the lazy transcript stack; − and +
have accessibility labels. Rows 196, 197 and 201 checked on an upload; rows
198, 200 and 205 partly (Return rename, file-line fix, Try again). Recorded
meetings (Stop, call track, meeting window colours) still need the owner.

## Known voices (Meeting speakers Part 2), 2026-10-17

Measurement (spec 8.4): on call audio the same person was 0.09–0.10 apart and
two different people 0.28–0.35; microphones and quiet speech spread one person
up to 1.07, so no single threshold covers all audio. Owner chose the cautious
rule: a suggestion needs distance 0.2 or less and a 0.1 margin over the next
saved voice, and every suggestion waits for Yes or No. Each suggestion keeps its
distance in `meeting.json`; check them after the monthly Dani and Mariel call.

Plan: `docs/superpowers/plans/2026-10-17-known-voices.md`, executed natively on
`feat/known-voices`. Upload check with two `say` clips sharing two voices: the
second clip suggested both correctly (0.087 and 0.089); Yes named Dan and added
a second meeting to Dan; No declined Sam for that meeting; Delete removed Sam;
`voices.json` was 0600.

| # | Check | Result |
|---|---|---|
| 207 | Name call speakers in one meeting; a later meeting with the same people shows "Name?" dashed chips with Yes and No, and "Name?" on their lines. | Pass 2026-10-17 (uploads) |
| 208 | Yes names the speaker everywhere and Settings shows one more meeting; No returns to Other N and the name is not suggested again in that meeting. | Pass 2026-10-17 (uploads) |
| 209 | Export, summary and Ask keep Other N until Yes. | Pending |
| 210 | Settings › Meetings › Known voices: switch off hides suggestions and saves nothing; Delete removes a voice, meetings keep their names. | Pass 2026-10-17 (uploads; Delete also hides a waiting suggestion) |
| 211 | Renaming Dani to David moves the meeting to David; clearing removes it; deleting a meeting drops its count. | Pending |
| 212 | Real call: two meetings with the same people on Zoom or Meet; note each suggestion's distance from `meeting.json`. | Pending (monthly Dani and Mariel call) |
