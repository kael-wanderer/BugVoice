# BugVoice — Handoff

Last updated: 2026-10-19

## Current state

**Learn from corrections:** merged on `main` (2026-10-19), not pushed. Ordinary
non-terminal pastes are watched locally for 60 s; word fixes become Dictionary
suggestions with Add / Dismiss and Replace every time (off when both words are
real words); counts in the popover and sidebar; Settings › Speech switch;
`suggestions.json` in backups. Paste raw, Redo and Retry cancel the watch.
Tests: **1,132 VoiceCore, 30 MCPKit, 114 BugVoiceMac**. Device checks K1–K10
not run yet (owner merged before trying them); list in
`docs/progress/corrections-log.md`.

**Project words:** merged on `main` and pushed (2026-10-19). Repo file names
and code identifiers feed the Whisper prompt and the cleanup and command
prompts in coding apps; names the repo declares rank first, and words the
speaker said go first in the cleanup list. Dictionary › Projects manages
folders, rescans and hidden words; Settings › Speech selects Coding apps / All
apps / Off; `projects.json` is in backups. Tests: **1,100 VoiceCore, 30 MCPKit,
109 BugVoiceMac**. Owner ran P1–P8: all pass. Details:
`docs/progress/project-words-log.md`.

**Command mode:** merged on `main` and pushed (2026-10-19). Hold Right Option
to rewrite the selection or write new text; Settings › General chooses Right
Option / Right Command / Off. Selection capture with clipboard restore,
focus/selection checks, terminal copy-only, Escape cancels, Original via
select-back, Command tag in history, Insights exclusion. Tests: **1,061
VoiceCore, 30 MCPKit, 101 BugVoiceMac**. Owner ran the device checks: all pass.
Details: `docs/progress/command-log.md`.

**Language per app and fix last paste:** merged on `main` and pushed
(2026-10-19, build 231). Per-app language rules, popover switch, language key
while recording, English-word preservation, Paste raw (⌃⌥R) and Redo in the
other language (⌃⌥L). Evidence and device checks: `docs/progress/language-log.md`.

**Backup and restore merged on `main` and pushed (2026-10-19).** Settings › Storage ›
Backup: Back up now, Restore (applied at the next launch, current library kept as a
safety copy), automatic Daily/Weekly into a chosen folder keeping 5. Spec:
`docs/superpowers/specs/2026-10-19-backup-restore-design.md`; plan:
`docs/superpowers/plans/2026-10-19-backup-restore.md`; evidence, review fixes and
device checks: `docs/progress/backup-log.md`. Codex built Tasks 1–8; review and device
checks found and fixed an empty restore sheet and a relaunch hang, plus four smaller
issues. Device: B1, B5–B9 pass; B2–B4, B10 not run. Owner to try: choose Daily in
the picker, Restore while a meeting records (B10), light theme. 1,106 tests pass.

**Branch `fix/review-findings` (2026-10-19, not merged):** fixes from the app review.
`06121c5` adds one unified-log subsystem (`com.kael.bugvoice`, `Log` in BugVoiceMac;
read with `/usr/bin/log show --last 1h --predicate 'subsystem == "com.kael.bugvoice"'`)
and Settings › Storage › Copy diagnostics (versions, engine and model names, this
launch's log; never dictated text). Checked in the dev app: the report copies and holds the
launch line. Not checked on device: the per-dictation log line (dictate once, then copy).
`961670d` splits `AppModel.swift` (1,415 → 697 lines) into `AppModel+Meetings`,
`+Library`, `+Models`. Thread Sanitizer over all 1,064 tests found no races (tests do not
drive real Core Audio callbacks). History timings (12 dictations): speech-to-text
1.25–2.0 s, cleanup 0.3–0.8 s, so release to text is about 2 s; the old 6.2 s
cleanup benchmark figure is stale.

**Device checks: the owner marked all of them done on 2026-10-19.** "Pending" in the
sections below and in the per-project logs is history.

**Build number:** every commit raises `CFBundleVersion` by one through
`Scripts/git-hooks/pre-commit` (`git config core.hooksPath Scripts/git-hooks`); it
started at 200 on 2026-10-19.

**Backup and restore:** merged; see the top of this file.

**`main` was last pushed 2026-10-19 at `0478cdd`.**
Merged 2026-10-18, each with its own log and pending owner checks:

| Project | Merge | Log |
|---|---|---|
| Appearance foundation (21 themes, text/font, icons, HUD size) | `fb6d092` | `docs/progress/appearance-log.md` |
| App shell (grouped sidebar, title bar, list panes, search) | `f21a909` | `docs/progress/app-shell-log.md` |
| Shell polish (resizable panes, section pills, time saved) | `6629e52` | `docs/progress/app-shell-log.md` |
| Menu bar popover | `0d36389` | `docs/progress/menu-popover-log.md` |
| Scratchpad list selects on first click | `89ef610` | — |
| Note editor (tool row, AI bar on request, list right-click menu) | `69ad3f0` | `docs/progress/note-editor-log.md` |
| Folders and tags management (tag colours, rename/merge/delete, Manage library sheet) | `d54202e` | `docs/progress/library-management-log.md` |

`swift test`: 1,060 tests pass. Owner checks still open from these rounds: light theme
and 160% text in the note editor; Mic, History and Trash buttons in the editor; the
colour dot on meeting rows, renaming a tag used by notes and meetings together, and
the page filter after a rename.

**Next roadmap item: 7, Calendar + export** (EventKit calendar, export to Apple Notes
and Notion). Not started; begins with a spec and mockup.

**MCP server (roadmap item 6, second half): merged and pushed (2026-10-17, `378fc2d`).**
`bugvoice-mcp` in `Contents/MacOS` speaks MCP over stdio and forwards tool calls
over `~/Library/Application Support/BugVoice/MCP/bugvoice.sock` to the app's
`MCPService`; Settings › Agents turns it on (off by default). Twelve tools: read,
search, ask, create/edit notes, upload recordings, job status, summaries.
Spec: `docs/superpowers/specs/2026-10-17-mcp-server-design.md`; plan:
`docs/superpowers/plans/2026-10-17-mcp-server.md`; mockup:
`docs/design/proposal-mcp.html`; evidence, choices and **34 pending manual
checks**: `docs/progress/mcp-log.md`. Automated: 858 VoiceCore tests / 93 suites,
30 MCPKit tests / 2 suites, 93 BugVoiceMac tests / 16 suites pass;
`Scripts/build-app.sh` exits 0. Device smoke test on the dev build passed: Agents
tab, MCP off message, reads, search, ask (one meeting), create/append note,
upload → job → transcript → summary. Not confirmed on device: agent edit refused
while the owner types in that note. An all-scope Vietnamese `ask` returned
nothing found. `/Applications/BugVoice.app` is an older build; rebuild and install
to get MCP.

**Ask AI (roadmap item 6, Ask part): merged and pushed (2026-10-17).** Tasks 1–8 provide the reviewed
VoiceCore retrieval/pipeline; Tasks 9–13 add local embedding indexing and Search
settings, per-tab Scratchpad scopes and answer cards, playable/translated citation
panels, and one-shot navigation into Meetings. This note keeps its existing
CHANGE/ANSWER behavior; the live meeting Ask box is unchanged. MCP is next as a
separate project.

Spec: `docs/superpowers/specs/2026-10-17-ask-ai-design.md`; plan:
`docs/superpowers/plans/2026-10-17-ask-ai.md`; mockup:
`docs/design/proposal-ask-ai.html`; evidence, implementation choices and **40
pending manual checks**: `docs/progress/ask-log.md`. Start with Stop/late responses,
wide and 440 pt citation panels, translation shared with open meeting views,
Open in Meetings seek/play/highlight, indexing pause, dictation deletion and a
server stopping mid-backfill. Review Focus coverage is mapped in that log.

Automated checks: **775 VoiceCore tests / 86 suites + 84 BugVoiceMac tests /
16 suites pass**. `Scripts/build-app.sh` exits 0, signed with `Bugler Local Dev`.
The app was not launched; no owner Application Support data was accessed.
Local embedding inference, device playback, layout and under-60-second Ask latency
remain unverified. Maintainer runs GUI/runtime checks; do not infer those passes
from unit tests or builds.

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

Scratchpad window merged on `main` (2026-10-16): spec
`docs/superpowers/specs/2026-10-16-scratchpad-window-design.md`, plan
`docs/superpowers/plans/2026-10-16-scratchpad-window.md`. The floating window is
the only note editor (a non-activating panel, so typing and dictation reach it
while another app is in front); the page lists cards. Device checks 151–168
pending. UI polish later (formatting bar is tight at the 440 pt Smaller width).

Meetings v2 (5a) implemented: spec
`docs/superpowers/specs/2026-10-16-meetings-v2-design.md`, plan
`docs/superpowers/plans/2026-10-16-meetings-v2.md`. A popup offers to record
when a meeting app or a Meet / Teams / Zoom tab starts using the microphone
(Core Audio process list, polled every 2 s); the meeting window replaces the
recorder panel (right third, My notes / Transcript / Summary tabs, live summary
every 3 active minutes, Ask anything about this meeting, final summary after
Stop that follows the notes). Notes are stored on the meeting manifest. Device
checks 172–187 pending.

Meetings v2 (5b) implemented: spec
`docs/superpowers/specs/2026-10-16-meetings-translation-design.md`, plan
`docs/superpowers/plans/2026-10-16-meetings-translation.md`. When a meeting's
languages include one other than English, each new line gets its English under
it, through the Meetings model (12 lines per request, thinking off, one request
at a time, after dictation and the summaries). English is saved on each line
(`MeetingSegment.translation`), carried over to the final transcript at Stop,
shown on the detail page and written to the Markdown export. Show English
(`MeetingManifest.showEnglish`) hides it. Device checks 188–194 pending.

Meeting speakers Part 1 implemented on `feat/meeting-speakers` in
`../BugVoice-meeting-speakers` (2026-10-17), not merged. Spec:
`docs/superpowers/specs/2026-10-17-meeting-speakers-design.md`; plan:
`docs/superpowers/plans/2026-10-17-meeting-speakers.md`. SpeakerKit from the
existing WhisperKit 1.1.1 package splits voices on device after Stop, recovery
and uploads, and on demand. People, names and single-line fixes live on the
Transcript detail page; exports, search, prompts and the read-only finished
meeting window use the names. Older manifests retain their defaults.

Automated checks: 641 VoiceCore tests / 76 suites + 84 BugVoiceMac tests /
16 suites pass. `Scripts/build-app.sh` succeeded and signed with `Bugler Local Dev`.
App not launched; device checks 195–206 and first-use model download/inference
remain pending in `docs/progress/meetings-log.md`. Tuning stays nil pending the
owner's 2-, 3- and 4-person clips. Full task evidence and adaptations are in the meetings log.

**Known voices (Meeting speakers Part 2):** built 2026-10-17 on `feat/known-voices`.
After a split, unnamed call speakers within cosine distance 0.2 of a saved voice
(and 0.1 closer than the next) show "Dani?" with Yes and No; names confirmed by a
rename or Yes are saved per meeting in `voices.json` (0600). Settings › Meetings ›
Known voices lists and deletes them. The 0.2 rule rests on one video's two
speakers; checks 209–212 in the meetings log, including a real call, are pending.

**Packaging:** app icon (Antenna Mic) and `Scripts/build-dmg.sh`; current version 0.1.0 build 10.

### Pending maintainer checks (deferred by the maintainer, 2026-10-14)

1. **System audio spike** (Task 8a): `Scripts/build-meeting-audio-tap-spike.sh`,
   run `./.build/MeetingAudioTapSpike.app/Contents/MacOS/MeetingAudioTapSpike`,
   approve the prompt, confirm other apps' audio is captured and the spike's
   own Glass sound is excluded, then revoke the permission and record whether
   denial is an error or silent buffers. Steps in `docs/progress/meetings-log.md`.
   **Passed 2026-10-16** (capture, prompt, self-exclusion); the deny run was skipped.
2. **Manual checklist**: Meetings rows 45–62 and a dictation regression pass
   (rows 1, 6, 14) in `docs/testing/manual-checklist.md`.

Until the checklist passes, denial handling, the production aggregate input, the
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

Roadmap item 7 (Calendar + export) is next; see Current state. The items below
are the original maintainer gates, still open.

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
