# BugVoice Roadmap

Agreed 2026-10-15. Each numbered item is its own sub-project: spec → plan →
implementation, like Dictation, Meetings and Notes before it.

## Current state

| Feature | State |
|---|---|
| Dictation (speech → text at the cursor) | Works. Device checks passed for Terminal, VS Code, Notion, Chrome, Vietnamese, hands-free. |
| Meetings | Built (You/Others tracks, transcript, Summary, Action items). Untested on device; waits for a real meeting and the system-audio spike. |
| Notes | Built, but failed when tried. On hold until item 0. |
| Insights | Built (Usage tab). Device checks 73–80 pending. |
| Meeting speakers | Part 1 merged (2026-10-17); device checks 195–206 and tuning pending. Part 2 known voices built (2026-10-17) with a cautious 0.2 rule; checks 209–212 and a real-call check pending. |
| Upload audio/video | Implemented (Upload queue, local media extraction, file-only transcription, recovery and uploaded Meetings). Device checks 103–119 pending. |

## Order

| # | Project | Scope | Why here |
|---|---|---|---|
| 0 | Fix Notes + finish device checks | Debug the failed Notes run; finish the manual checklist and system-audio spike | Notes is broken and item 6 depends on it |
| 1 | Insights | New page: words, words per minute, dictations, notes, meetings, streak, activity heatmap, per-app and per-style use | Small; uses data already recorded |
| 2 | Snippets + Styles | Snippets: spoken trigger → saved text (acronyms, links, prompts). Styles: tone per app group (personal message, work message, email, other) | Improves every dictation |
| 3 | Models per feature | Pick a model for dictation, meetings and notes separately; cloud API keys (OpenAI, Anthropic, OpenRouter…); coding CLIs (claude, codex, gemini, pi) as providers for slow tasks | Groundwork for 4–6 |
| 4 | Upload audio/video | Upload page (drop or browse → file card → Transcribe → progress), as in OpenWhispr. AVFoundation formats (MP3, WAV, M4A, AIFF, CAF, MP4, MOV, M4V). Result is a meeting with an "Uploaded" badge: timestamped transcript labelled "Speaker", click a line to play, Summary, Action items, export. Keeps `audio.m4a` only | Reuses the meeting pipeline; keeps timestamps so item 6 can cite audio |
| 5 | Meetings v2 | 5a: Meeting detected popup; meeting window docked to the right third with My notes / Transcript / Summary (live) tabs and Ask anything about this meeting; marks feedback and marks on the detail page. Spec: `docs/superpowers/specs/2026-10-16-meetings-v2-design.md`. 5b: live English translation under each Transcript line. Spec: `docs/superpowers/specs/2026-10-16-meetings-translation-design.md` | 5a implemented 2026-10-16 (plan `docs/superpowers/plans/2026-10-16-meetings-v2.md`); device checks 172–187 pending. 5b implemented 2026-10-16 (plan `docs/superpowers/plans/2026-10-16-meetings-translation.md`); device checks 188–194 pending |
| 6 | Ask AI + MCP server | Chat that answers from notes, dictations and meetings; an MCP server so coding agents read the same data. Answers cite their proof as recording + time range ("Standup, 0:20–0:50"); clicking a citation opens the recording and plays that range. Citations are checked against real segments. The Scratchpad AI box gets a source picker (This note / This folder / All folders); the meeting window Ask box gains All meetings | One retrieval layer serves both |
| 7 | Calendar + export | Calendar via EventKit (Google and Microsoft accounts already added to macOS Calendar, no sign-in); export to Apple Notes and Notion | Polish |
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
