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

Status: all three sub-projects (dictation, Meetings, Notes) are merged on
`main`. Pending maintainer gates: manual checklist (dictation 1–44, Meetings
45–62, Notes 63–72), benchmark, and system-audio spike. See `docs/progress/HANDOFF.md`, `docs/progress/meetings-log.md`, and
`docs/progress/notes-log.md`.

Built in three sub-projects, each with its own spec → plan → implementation:

1. **Dictation core + app shell** — merged on `main`; maintainer gates remain.
2. **Meetings** — merged on `main`; device checks pending.
3. **Notes** — speak into an in-app note editor; merged on `main`; device checks pending.

Release packaging: `Scripts/build-dmg.sh` builds `build/BugVoice-<version>-<build>.dmg`;
version and build live in `App/Info.plist`. App icon source is `App/Icon/AppIcon.svg`
(`Scripts/make-app-icon.sh` regenerates `App/AppIcon.icns`).

## Key documents

- Spec: `docs/superpowers/specs/2026-10-14-dictation-core-and-shell-design.md`
- Plan: `docs/superpowers/plans/2026-10-14-dictation-core-and-shell.md`
- UI mockup: `docs/design/mockup.html` (open in a browser; light/dark toggle)
- Handoff / status: `docs/progress/HANDOFF.md`
- Meetings spec: `docs/superpowers/specs/2026-10-14-meetings-design.md`
- Meetings plan: `docs/superpowers/plans/2026-10-14-meetings.md`
- Meetings execution log: `docs/progress/meetings-log.md`
- Notes spec: `docs/superpowers/specs/2026-10-14-notes-design.md`
- Notes plan: `docs/superpowers/plans/2026-10-14-notes.md`
- Notes execution log: `docs/progress/notes-log.md`
- Ask AI spec: `docs/superpowers/specs/2026-10-17-ask-ai-design.md`
- Ask AI plan: `docs/superpowers/plans/2026-10-17-ask-ai.md`
- Ask AI mockup: `docs/design/proposal-ask-ai.html`
- Ask AI execution log and manual checks: `docs/progress/ask-log.md`
- MCP server spec: `docs/superpowers/specs/2026-10-17-mcp-server-design.md`
- MCP server mockup: `docs/design/proposal-mcp.html`
- Roadmap (next sub-projects, dropped ideas): `docs/ROADMAP.md`

## Rules

- Swift package, tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only.
- Exactly one external dependency: WhisperKit pinned `exact: "1.1.1"`. Any other
  dependency is a maintainer decision and gets a `THIRD_PARTY_NOTICES.md` entry.
- TDD for everything in `VoiceCore`: failing test first, then code. `swift test`
  must pass before every commit.
- API keys live in `credentials.json` (`CredentialStore`: folder 0700, file 0600),
  never in `settings.json`. Not the Keychain: without an Apple Team ID, macOS ties
  each Keychain item to the exact build, so every rebuild asked for the login
  password. Keychain is read once at launch to import keys from older builds.
- Build the app with `Scripts/build-app.sh`. It signs with the `Bugler Local Dev`
  identity so macOS keeps Microphone / Accessibility / Input Monitoring grants
  across rebuilds. Do not switch to ad hoc signing.
- Run the dev app with `Scripts/run-dev-app.sh`, never a bare `open`. With two
  displays its windows open on the one that is not primary, so the owner's
  main display stays free; with one display they open as usual.
  `BUGVOICE_DEV_SCREEN=primary Scripts/run-dev-app.sh` keeps them on the
  primary display. Find the window's position before a screenshot or click,
  and capture the BugVoice window itself, not a screen region.
- Never paste into a secure text field. Never send audio or text off this Mac
  unless the user configured a remote server.
- UI copy: plain English, no hedging words, no emoji.
- Commit after each plan task; message style `feat(core): …`, `feat(app): …`, `docs: …`.

## Machine facts (maintainer's Mac)

- Apple M3 Ultra, 96 GB RAM, macOS 27, Swift 6.4, Xcode command-line tools, ffmpeg.
- Local LLM: oMLX (`/Applications/oMLX.app`) at `http://localhost:8000`, OpenAI-compatible,
  needs an API key (kept in `credentials.json`). Use it for tests. MTPLX
  (`/Applications/MTPLX.app`) is a faster alternative but spins the fans. LM Studio and
  Ollama are no longer used.
- Search with `rg`, not grep/find.
