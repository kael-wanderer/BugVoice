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

- Commit: pending this task commit.
- Verification: `swiftc -typecheck Scripts/meeting-audio-tap-spike.swift` passed; `Scripts/build-meeting-audio-tap-spike.sh` built and verified a signed app bundle with `Bugler Local Dev`; it was not launched. `swift test` passed 171 VoiceCore + 17 BugVoiceMac tests.
- Apple documentation supports creating a tap with `AudioHardwareCreateProcessTap`, attaching its UID to a private aggregate device tap list, and expecting the System Audio Recording prompt on first recording start. The spike excludes its own Core Audio process object and plays a BugVoice-owned Glass sound during the capture window.
- Maintainer run steps: (1) from the repo root run `Scripts/build-meeting-audio-tap-spike.sh`; (2) run `./.build/MeetingAudioTapSpike.app/Contents/MacOS/MeetingAudioTapSpike` in Terminal; (3) approve the System Audio Recording prompt; (4) observe the automatic Glass sound and confirm it produces no RMS output; (5) play audio from another app and confirm positive RMS lines; (6) quit with Return; (7) revoke the app's System Audio Recording permission in System Settings → Privacy & Security → System Audio Recording, rerun, deny access, and record whether tap/device start returns an OSStatus error or yields silent buffers. Record macOS build, each result, and any API adjustment in the spec.
- **UNVERIFIED on device:** System audio capture, exclusion of BugVoice's own sound, permission prompt behavior, and denial behavior were not exercised. The aggregate tap dictionary shape and Float32 mono interpretation are compile-checked but runtime-unverified.
- Decision: compile and sign the spike without launching it; this avoids consuming the maintainer's one-time OS permission decision. Cost if wrong: the first runtime attempt could reveal a compile-clean Core Audio setup error; the spike can be adjusted and rerun before production integration review.
- Open question for maintainer's later run: does permission denial return an error at tap start or produce silent buffers?
