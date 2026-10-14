# BugVoice Agent Guide

Shared source of truth for any AI agent working in this repository (Claude Code,
Codex, etc.). `CLAUDE.md` is a symlink to this file. Machine-specific overrides
go in `AGENTS.local.md` / `CLAUDE.local.md`; both are gitignored.

Read this file first, then `docs/progress/HANDOFF.md` for current state.

## Project

BugVoice is a personal, local-first macOS menu-bar dictation app: hold Right
Option, speak English / Vietnamese / mixed, release, and cleaned text is pasted
at the cursor (terminal coding agents, Notion, browsers, chat). Speech-to-text
runs on device (WhisperKit); cleanup uses any local model through an
OpenAI-compatible or Anthropic-compatible API (LM Studio, Ollama, MLX…) or
Apple Intelligence.

Built in three sub-projects, each with its own spec → plan → implementation:

1. **Dictation core + app shell** — current. Spec and plan below.
2. **Meetings** — record mic + system audio, timeline transcript, player, file list.
3. **Notes** — speak into an in-app note editor (no timeline).

Space for 2 and 3 is reserved in the UI, storage layout and code seams
(spec §10). Do not build them inside sub-project 1.

## Key documents

- Spec: `docs/superpowers/specs/2026-10-14-dictation-core-and-shell-design.md`
- Plan: `docs/superpowers/plans/2026-10-14-dictation-core-and-shell.md`
- UI mockup: `docs/design/mockup.html` (open in a browser; light/dark toggle)
- Handoff / status: `docs/progress/HANDOFF.md`

## Rules

- Swift package, tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only.
- Exactly one external dependency: WhisperKit pinned `exact: "1.1.1"`. Any other
  dependency is a maintainer decision and gets a `THIRD_PARTY_NOTICES.md` entry.
- TDD for everything in `VoiceCore`: failing test first, then code. `swift test`
  must pass before every commit.
- API keys live in Keychain (service `BugVoice`), never in `settings.json`.
- Build the app with `Scripts/build-app.sh`. It signs with the `Bugler Local Dev`
  identity so macOS keeps Microphone / Accessibility / Input Monitoring grants
  across rebuilds. Do not switch to ad hoc signing.
- Never paste into a secure text field. Never send audio or text off this Mac
  unless the user configured a remote server.
- UI copy: plain English, no hedging words, no emoji.
- Commit after each plan task; message style `feat(core): …`, `feat(app): …`, `docs: …`.

## Machine facts (maintainer's Mac)

- Apple M3 Ultra, 96 GB RAM, macOS 27, Swift 6.4, Xcode command-line tools, ffmpeg.
- LM Studio at `http://localhost:1234`, model `qwen3.8-27b-mlx`.
- Search with `rg`, not grep/find.
