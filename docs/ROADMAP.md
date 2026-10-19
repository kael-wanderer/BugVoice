# BugVoice Roadmap

Agreed 2026-10-15. Each numbered item is its own sub-project: spec → plan →
implementation, like Dictation, Meetings and Notes before it.

## Current state

The owner marked prior device checks done on 2026-10-19; their "pending" entries
below are history. Backup and restore checks: B1, B5–B9 pass; B2–B4, B10 not run
(see `docs/progress/backup-log.md`).
Proposed new features from the 2026-10-19 review: `docs/propose-new-features.md`.

| Feature | State |
|---|---|
| Dictation (speech → text at the cursor) | Works. Device checks passed for Terminal, VS Code, Notion, Chrome, Vietnamese, hands-free. |
| Meetings | Built (You/Others tracks, transcript, Summary, Action items). Untested on device; waits for a real meeting and the system-audio spike. |
| Notes | Fixes BV-0004/5/6 landed (2026-10-15); notes are edited in the Scratchpad window (item 8). Device checks 63–72 pending. |
| Insights | Built (Usage tab). Device checks 73–80 pending. |
| Meeting speakers | Part 1 merged (2026-10-17); device checks 195–206 and tuning pending. Part 2 known voices built (2026-10-17) with a cautious 0.2 rule; checks 209–212 and a real-call check pending. |
| Upload audio/video | Implemented (Upload queue, local media extraction, file-only transcription, recovery and uploaded Meetings). Device checks 103–119 pending. |
| Ask AI | Merged and pushed (2026-10-17, `dcc4b21`). Per-tab Scratchpad scope, checked cards, translated audio citations, local search index (Qwen3-Embedding-0.6B on oMLX) and Meetings jumps. Tried on device in English and Vietnamese. Device checks 1–40 in `docs/progress/ask-log.md` pending. |
| MCP server | Built (2026-10-17): `bugvoice-mcp` stdio bridge, Settings › Agents, 12 tools. Device checks 1–34 in `docs/progress/mcp-log.md` pending. |
| Backup and restore | Merged on `main` (2026-10-19): local archives, automatic backups and retention, restore applied at next launch with a safety copy, Storage controls. B1, B5–B9 pass on device; B2–B4 and B10 not run (B2/B4 covered by tests). 1,106 tests pass. Evidence: `docs/progress/backup-log.md`. |
| Command mode | Built on `feat/command-mode` (2026-10-19, not merged or pushed). Hold Right Option to rewrite selections or write new text; Original, history tag/search, safe copy decisions and Insights exclusion. 1,190 tests pass; signed build succeeds. Read-only Settings smoke passed. C1–C11 not run; C12 partial only. Evidence: `docs/progress/command-log.md`. |
| Language per app and fix last paste | Implemented on `feat/language-fix-last` (2026-10-19, not merged). Language rules, menu switch, language key, English-word preservation, paste-raw and other-language replacement. L1–L12 not run because the computer-use provider rejected BugVoice access. Evidence: `docs/progress/language-log.md`. |

## Order

| # | Project | Scope | Why here |
|---|---|---|---|
| 0 | Fix Notes + finish device checks | Debug the failed Notes run; finish the manual checklist and system-audio spike | Notes fixes done (2026-10-15); manual checklist and system-audio spike remain |
| 1 | Insights | New page: words, words per minute, dictations, notes, meetings, streak, activity heatmap, per-app and per-style use | Small; uses data already recorded |
| 2 | Snippets + Styles | Snippets: spoken trigger → saved text (acronyms, links, prompts). Styles: tone per app group (personal message, work message, email, other) | Improves every dictation |
| 3 | Models per feature | Pick a model for dictation, meetings and notes separately; cloud API keys (OpenAI, Anthropic, OpenRouter…); coding CLIs (claude, codex, gemini, pi) as providers for slow tasks | Groundwork for 4–6 |
| 4 | Upload audio/video | Upload page (drop or browse → file card → Transcribe → progress), as in OpenWhispr. AVFoundation formats (MP3, WAV, M4A, AIFF, CAF, MP4, MOV, M4V). Result is a meeting with an "Uploaded" badge: timestamped transcript labelled "Speaker", click a line to play, Summary, Action items, export. Keeps `audio.m4a` only | Reuses the meeting pipeline; keeps timestamps so item 6 can cite audio |
| 5 | Meetings v2 | 5a: Meeting detected popup; meeting window docked to the right third with My notes / Transcript / Summary (live) tabs and Ask anything about this meeting; marks feedback and marks on the detail page. Spec: `docs/superpowers/specs/2026-10-16-meetings-v2-design.md`. 5b: live English translation under each Transcript line. Spec: `docs/superpowers/specs/2026-10-16-meetings-translation-design.md` | 5a implemented 2026-10-16 (plan `docs/superpowers/plans/2026-10-16-meetings-v2.md`); device checks 172–187 pending. 5b implemented 2026-10-16 (plan `docs/superpowers/plans/2026-10-16-meetings-translation.md`); device checks 188–194 pending |
| 6 | Ask AI + MCP server | Ask built: Scratchpad scopes (This note / This folder / A meeting… / All notes and meetings), word and local meaning search across notes, meetings, uploads and dictations, checked proof, translated range playback and Open in Meetings. The live meeting Ask box stays unchanged. Spec: `docs/superpowers/specs/2026-10-17-ask-ai-design.md` | Ask merged on `main` (2026-10-17); device checks pending in `docs/progress/ask-log.md`. MCP server built (2026-10-17; spec `docs/superpowers/specs/2026-10-17-mcp-server-design.md`, plan `docs/superpowers/plans/2026-10-17-mcp-server.md`); device checks pending in `docs/progress/mcp-log.md`. |
| 7 | Integrations | Frozen (2026-10-19); see Frozen below | Rarely used; the sidebar hides the page |
| 8 | Scratchpad (Notes v2) | Note window with tabs for several open notes, formatting toolbar, Transforms (Polish, More concise, More professional, ask a question) using the Notes model; uploaded and dictated text can land here. As in Wispr Flow | Built (2026-10-16). Spec: `docs/superpowers/specs/2026-10-15-scratchpad-design.md`. Floating Scratchpad window (the only editor; the page lists cards): spec `docs/superpowers/specs/2026-10-16-scratchpad-window-design.md`, merged (2026-10-16) |
| 9 | Folders and tags | One level of folders plus tags, shared by meetings, uploads and notes; AI suggests existing tags after a summary. Spec: `docs/superpowers/specs/2026-10-15-folders-tags-design.md` | Built before item 8 |

## Notes on scope

- Item 3 replaced the single text model with connections (each with its own
  Keychain key) and a model per feature; `claude`, `codex` and `pi` can write
  meeting notes. Gemini was left out.
- Coding CLIs take several seconds per call: fine for summaries and Ask AI,
  too slow for dictation cleanup.
- Item 2 replaced `vocabulary.txt` with `dictionary.json` (words, heard-as
  forms, snippets); an existing `vocabulary.txt` is migrated once and renamed
  `vocabulary.migrated.txt`.
- Item 4 follows `docs/superpowers/specs/2026-10-15-upload-design.md` and
  `docs/superpowers/plans/2026-10-15-upload.md`; only extracted `audio.m4a` is
  retained after success. URL import remains deferred; speaker splitting is
  implemented as Meeting speakers Part 1.
- Next round: the note editor (owner's option A, app shell spec). Owner
  requests for the floating Scratchpad editor go into that round's design
  (2026-10-18): a right-click menu on list notes with Pin, Move to folder and
  Move to Trash; Folder and Tags on one row; the Markdown | Doc switch on the
  title row (end) or the folder/tags row; the "This note" scope picker to the
  left of Polish.

## Frozen

Agreed with the owner 2026-10-19. Not built now; decisions so far are kept here.

| Idea | Decisions so far |
|---|---|
| Integrations page (was item 7, Calendar + export) | The Connect group and Integrations page are hidden from the sidebar. When resumed, the page holds: **Calendars** with three rows as in OpenWhispr — Apple Calendar (EventKit, built first), Google Calendar and Microsoft Calendar (shown greyed out until the owner registers OAuth clients and confirms the company allows the sign-in). Calendar is read-only: event title becomes the meeting title, agenda from the event notes, attendees as speaker-name suggestions, join link the owner clicks. BugVoice never joins a meeting (bots stay dropped). **MCP server** moves here from Settings › Agents. **Export** to Apple Notes and Notion stays in scope; existing Markdown, SubRip and audio exports stay where they are. |
| Help page | In-app guides (getting started, shortcuts, styles, meetings, coding agents), readable offline. Hidden from the sidebar 2026-10-19; the page code stays. |
| Home page | A start page like OpenWhispr's Home ("Welcome back", today's items, Connect calendar card). Frozen: nothing useful to show until Calendars exists. |

## Dropped

| Idea | Reason |
|---|---|
| Meeting bot that joins Zoom/Meet calls | Needs a cloud server and the meeting platforms' APIs; breaks local-first. BugVoice records mic + system audio on this Mac, as Granola does. |
| Connectors that post into Slack or email | Speak → format → paste is dictation plus Styles (item 2). Posting on the user's behalf adds accounts and risk for no gain. |
| Calendar sign-in with Google / Microsoft OAuth | EventKit reads those accounts through macOS Calendar with no login and no dependency. |

## Deferred

| Idea | Reason |
|---|---|
| Import from a URL (YouTube, audio link) | Needs yt-dlp, a second dependency, and a network fetch. |
