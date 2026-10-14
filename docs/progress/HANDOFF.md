# BugVoice — Handoff

Last updated: 2026-10-14

## Current state

**Sub-project 1 (Dictation core + app shell): spec approved, plan written, no code yet.**

| Item | Path | Status |
|---|---|---|
| Design spec | `docs/superpowers/specs/2026-10-14-dictation-core-and-shell-design.md` | Approved by maintainer |
| UI mockup | `docs/design/mockup.html` | Approved ("it looks great") |
| Implementation plan | `docs/superpowers/plans/2026-10-14-dictation-core-and-shell.md` | Written, awaiting maintainer review |
| Code | — | Not started |

## Next step for a new session

1. Read `AGENTS.md`, the spec, and the plan (in that order). Open the mockup in a browser.
2. Ask the maintainer to confirm the plan and choose execution:
   - **Subagent-driven** (`superpowers:subagent-driven-development`) — fresh implementer + reviewer per task.
   - **Native** (`superpowers:executing-plans`) — one session implements all tasks, one whole-branch review at the end.
3. Start at **Task 1**. Work on a branch (`feat/dictation-core`), commit after each task.

## Plan at a glance (21 tasks)

| # | Task | Gate |
|---|---|---|
| 1 | Package skeleton, AudioClip, WAV encode/decode, core protocols | `swift test` |
| 2 | Vocabulary (terms, `spoken => written`, Whisper prompt) | `swift test` |
| 3 | Settings model (tolerant decoding), SettingsStore, AppPaths | `swift test` |
| 4 | FocusSnapshot + StyleRouter (bundle ids, VS Code terminal, browser URLs) | `swift test` |
| 5 | PromptBuilder, OutputSanitizer, HallucinationFilter | `swift test` |
| 6 | OpenAI- / Anthropic-compatible text models, ModelCatalog | `swift test` (stubbed HTTP) |
| 7 | OpenAI-compatible transcriber (multipart) | `swift test` |
| 8 | WhisperKit engine + `bugvoice-bench` CLI + WER | **Maintainer gate**: record 6 clips in `bench/clips/`, pick default language and cleanup model |
| 9 | History log (JSONL) + stats | `swift test` |
| 10 | Hold / double-tap gesture detector | `swift test` |
| 11 | DictationPipeline (timeouts, raw fallback, secure field) | `swift test` |
| 12 | BugVoiceMac: pasteboard inserter + snapshot restore | `swift test` |
| 13 | Focus inspector (AX), secure input, permissions, Keychain | `swift test` + build |
| 14 | Hotkey event tap, global shortcuts, audio recorder, devices | build |
| 15 | App bundle, AppModel, provider factory, menu bar, window shell | app launches |
| 16 | HUD panel | build |
| 17 | DictationController — end-to-end | 8 manual checks in the task |
| 18 | Settings page (6 tabs) | manual |
| 19 | Dictation history page | manual |
| 20 | Permissions window + full menu | manual |
| 21 | Manual checklist, final verification, update this file | checklist |

## Decisions already made (do not re-ask)

- Native Swift menu-bar app (not Python daemon, not Electron).
- Text model API: OpenAI-compatible and Anthropic-compatible, plus Apple Intelligence and None. Default LM Studio `http://localhost:1234`, `qwen3.8-27b-mlx`. Runtime may change to Ollama / MLX — presets exist.
- Speech: WhisperKit `large-v3-v20240930_turbo` on device; optional OpenAI-compatible transcription server.
- Languages: English, Vietnamese, mixed. Default language decided by the Task 8 benchmark.
- Terminal style: cleanup off by default, literal text, no trailing period.
- Main window: sidebar Dictation · (Meetings) · (Notes) · Settings. Settings live in the main window, six tabs including Storage. No storage footer in the sidebar.
- Meetings (sub-project 2) and Notes (sub-project 3) are separate specs later; requirements recorded in spec §10.

## Known risks

- Qwen 27B cleanup latency may exceed the 1.5 s target. Terminal skips the model; Task 8 measures it, a smaller cleanup model may be chosen.
- Whisper detects one language per clip; mixed EN/VI quality depends on the language setting (Task 8 decides).
- ⌘V is posted as key code 9; non-QWERTY layouts are untested.
- Clipboard managers may request pasteboard data and make a failed paste look consumed.
- `com.vng.zalo` bundle id unverified (Task 4 Step 5 checks).

## Background

The design came from a study of Wispr Flow 1.6.1147 (Electron; cloud gRPC transcription; Swift helper pastes via delayed pasteboard provider + ⌘V; meetings capture mic + system audio). BugVoice keeps the paste technique and moves everything on device.
