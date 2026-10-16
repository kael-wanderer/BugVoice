# BugVoice — Handoff

Last updated: 2026-10-15

## Current state

**Sub-project 1 (Dictation core + app shell): merged on `main`. Its manual checklist and benchmark gate remain pending; deferred findings are fixed.**

**Sub-project 2 (Meetings): merged on `main` (2026-10-14) after whole-branch review and two fix rounds. Device checks pending.**

**Sub-project 3 (Notes): merged on `main` (2026-10-14) after whole-branch review and fixes. Notes manual checks (rows 63–72) pending.**

**Roadmap item 4 (Upload audio/video): implemented.** The Upload page queues local
files, streams a file-only journal, resumes committed transcription on launch and
saves uploaded results in Meetings. Source files stay unchanged. Device checklist
103–119 remains pending; do not mark those rows passed from unit tests. Uploads
use the configured Speech engine and do not contribute Insights usage. The kept
retry journal costs about 115 MB per hour until ready/deleted. Schema stays 1;
older builds cannot decode the new file-track value in uploaded meetings.

Folders and tags (roadmap item 9) merged on `main`: spec
`docs/superpowers/specs/2026-10-15-folders-tags-design.md`, plan
`docs/superpowers/plans/2026-10-15-folders-tags.md`. Device checks 126–134 pending.

Scratchpad (roadmap item 8) merged on `main` (2026-10-16): spec
`docs/superpowers/specs/2026-10-15-scratchpad-design.md`, plan
`docs/superpowers/plans/2026-10-15-scratchpad.md`. Device checks 136–150 pending.

Scratchpad window built on branch `feat/scratchpad-window`: spec
`docs/superpowers/specs/2026-10-16-scratchpad-window-design.md`, plan
`docs/superpowers/plans/2026-10-16-scratchpad-window.md`. Awaiting review and
merge; device checks 151–168 pending.

**Packaging:** app icon (Antenna Mic) and `Scripts/build-dmg.sh`; current version 0.1.0 build 10.

### Pending maintainer checks (deferred by the maintainer, 2026-10-14)

1. **System audio spike** (Task 8a): `Scripts/build-meeting-audio-tap-spike.sh`,
   run `./.build/MeetingAudioTapSpike.app/Contents/MacOS/MeetingAudioTapSpike`,
   approve the prompt, confirm other apps' audio is captured and the spike's
   own Glass sound is excluded, then revoke the permission and record whether
   denial is an error or silent buffers. Steps in `docs/progress/meetings-log.md`.
2. **Manual checklist**: Meetings rows 45–62 and a dictation regression pass
   (rows 1, 6, 14) in `docs/testing/manual-checklist.md`.

Until both pass, system-audio capture, self-exclusion, denial handling, the
`Privacy_ScreenCapture` settings link, recorder focus, sleep/quit/crash
recovery and playback are **UNVERIFIED on device**.

| Item | Path | Status |
|---|---|---|
| Design spec | `docs/superpowers/specs/2026-10-14-dictation-core-and-shell-design.md` | Approved |
| UI mockup | `docs/design/mockup.html` | Approved |
| Implementation plan | `docs/superpowers/plans/2026-10-14-dictation-core-and-shell.md` | Approved; Tasks 1–20 done |
| Code | `main` (merged from `feat/dictation-core`) | Built subagent-driven: each task implemented, reviewed, fixed until clean |
| Meetings spec | `docs/superpowers/specs/2026-10-14-meetings-design.md` | Approved with maintainer amendments |
| Meetings plan | `docs/superpowers/plans/2026-10-14-meetings.md` | Tasks 1–13 implemented and committed on `feat/meetings` |
| Meetings code | `main` (merged from `feat/meetings`) | Recorder, dual-track journals/finalization, transcription, library, player, exports, settings, recovery |
| Notes spec | `docs/superpowers/specs/2026-10-14-notes-design.md` | Approved with maintainer amendments |
| Notes plan | `docs/superpowers/plans/2026-10-14-notes.md` | Approved with maintainer amendments; Tasks 1–7 implemented; merged on `main` |
| Notes code | `main` (merged from `feat/notes`) | Markdown store, authoritative edit buffers, captured-note dictation, Notes page, settings, menu, lifecycle |
| Upload spec | `docs/superpowers/specs/2026-10-15-upload-design.md` | Approved |
| Upload plan | `docs/superpowers/plans/2026-10-15-upload.md` | Tasks 1–11 implemented and committed on `feat/upload`; device checks pending |
| Upload automated tests | `swift test` on `feat/upload` | VoiceCore 407 tests / 48 suites, BugVoiceMac 70 tests / 14 suites — all pass |
| Upload app | `Scripts/build-app.sh` on `feat/upload` | Build passed and signed with `Bugler Local Dev`; device checks 103–119 pending |
| Automated tests | `swift test` on `main` | VoiceCore 229 tests / 31 suites, BugVoiceMac 58 tests / 11 suites — all pass |
| App | `Scripts/build-app.sh` on `main` | Build passed, signed with `Bugler Local Dev`, launched once and remained running; see `docs/progress/notes-log.md` |
| Manual checklist | `docs/testing/manual-checklist.md` | Dictation rows 1–44, Meetings rows 45–62, Notes rows 63–72 written; **not run** (needs maintainer checks) |
| Benchmark gate (Task 8 step 12) | `bench/clips/`, `docs/bench/2026-10-14-stt-bench.md` | **Open**: first run found and fixed a decoder bug; clips and references incomplete |

## Next steps

Insights built on `feat/insights`; run checklist 73–80 after review.

1. **Maintainer: benchmark gate.** Record six clips in `bench/clips/` per its
   README, run `Scripts/stt-bench.sh > docs/bench/$(date +%F)-stt-bench.md`,
   pick the default language (lowest mean WER on `mix-*`) and the cleanup
   model. If `vi` wins, change `SpeechSettings.language` default and
   `defaultsMatchSpec` in `SettingsTests`.
   - First run (2026-10-14): see `docs/bench/2026-10-14-stt-bench.md`.
     Re-record `en-1`/`vi-1` (decoder hears music), add `en-2`/`vi-2` and a
     `.txt` reference for every clip.
   - Known: WhisperKit 1.1.1 returns empty text for a forced language with
     timestamp decoding; the transcriber decodes without timestamps.
     Meetings (sub-project 2) needs timestamps and must revisit this.
   - Known: LM Studio with `qwen3.8-27b-mlx` ignores every request-side
     thinking switch (`chat_template_kwargs.enable_thinking`, `reasoning_effort`).
     Smoke test: English cleanup 6.2 s, Vietnamese empty (reasoning hits the
     token cap). Turn thinking off in LM Studio's model settings, or choose a
     non-thinking or smaller model.
2. **Maintainer: manual checklist.** Run `docs/testing/manual-checklist.md`,
   fill in results. Notes rows 63–72 cover note editing, dictation privacy,
   external edits, undo, export, storage, and quit. Meetings rows 45–62 cover OS audio permission, track
   separation, echo/headphones, focus, dictation concurrency, sleep/crash
   recovery, language fallback, summaries, player, exports, retention, and
   storage. Failures in decisions that live in `VoiceCore` get a test.
3. **Final whole-branch review**: done; the deferred minor findings are fixed
   (see below).

## Deviations from the plan (all decided during execution)

- Main window and Permissions window are AppKit windows opened via
  `AppModel.openMainWindow(page)` / `openPermissionsWindow()`, not SwiftUI
  `Window` scenes with a notification bridge. `bootstrap()` runs from
  `AppDelegate.applicationDidFinishLaunching`.
- Dock icon: activation policy `.regular` while a window is open, `.accessory`
  when none is (spec §9).
- HUD and menu use the spec's wording (*Secure field — copied*,
  *Copied — press ⌘V*, *Raw — model unavailable*, *Done (style)*,
  *Cleaning (model)*, *Model loading*).
- Secure fields fail closed: AX not trusted, unreadable focus, AX error, or
  secure event input owned by the frontmost app ⇒ copy, never paste.
  Paste last and Paste again check too. Secure-field dictations are not logged,
  not shown in the menu, and leave no `last.wav`.
- Right ⌥ must be held alone: key mapping lives in `VoiceCore.KeyEventMapper`
  (tested). ⌃ held, then Right ⌥, then ⌃ released never records.
- Every recording (hold or hands-free) has the time cap; a lost event tap
  cancels any recording and shows *Hotkey not active*.
- Cleanup: `chat_template_kwargs: {"enable_thinking": false}` is sent for Qwen
  models; `maxTokens = min(1024, 2 × raw + 50)`; Whisper `[…]` placeholders are
  stripped and placeholder-only clips are *Nothing heard*.
- `history.jsonl` keys `app` / `inserted` per spec §3.3.
- Hotkeys include F14–F19; Text model presets include *Custom*; "Don't save"
  asks before clearing history; save failures show a *Could not save* alert.
- `build-app.sh` refuses to sign ad hoc unless `ALLOW_ADHOC=1`.

## Deferred minor findings (fixed 2026-10-14)

The seven deferred sub-project 1 findings are fixed on `main`:
- Vocabulary replacements match in NFC (precomposed and decomposed Vietnamese).
- An unknown style in `appOverrides` drops only that entry.
- Clipboard restore is skipped when the pasteboard changed after the paste.
- Paste again waits for the previous app to become frontmost (1 s cap).
- `AudioRecorder.start` refuses a double start and a failed device selection
  (no silent fallback to the default mic); the HUD names the cause.
- Every taken ⌃⌥ shortcut (V, B, N, M) is listed in the menu.
- Transcription cancellation is detected by type (`CancellationError`,
  `URLError.cancelled`, or any error after task cancellation).

## Known risks

- Meetings system audio capture, self-audio exclusion, aggregate-device input
  behavior, and denied-permission behavior are **UNVERIFIED on device**. Run
  the spike steps in `docs/progress/meetings-log.md` before relying on capture.
- Auto language detection can render Vietnamese clauses as English. Forced
  `vi` retry only runs when the timestamped auto result is empty; the manual
  checklist includes mixed-language review.
- Without headphones, the microphone can capture Others as You. The app keeps
  those lines; compare with headphones during the Meetings checklist.
- ⌘V is posted as key code 9; non-QWERTY layouts are untested.
- Clipboard managers may request pasteboard data and make a failed paste look consumed.
- `com.vng.zalo` bundle id unverified (Zalo not installed on the dev Mac).
- Whisper detects one language per clip; mixed EN/VI quality depends on the
  language setting (benchmark gate decides).

## Background

The design came from a study of Wispr Flow 1.6.1147 (Electron; cloud gRPC transcription; Swift helper pastes via delayed pasteboard provider + ⌘V; meetings capture mic + system audio). BugVoice keeps the paste technique and moves everything on device.
