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

## Order

| # | Project | Scope | Why here |
|---|---|---|---|
| 0 | Fix Notes + finish device checks | Debug the failed Notes run; finish the manual checklist and system-audio spike | Notes is broken and item 6 depends on it |
| 1 | Insights | New page: words, words per minute, dictations, notes, meetings, streak, activity heatmap, per-app and per-style use | Small; uses data already recorded |
| 2 | Snippets + Styles | Snippets: spoken trigger → saved text (acronyms, links, prompts). Styles: tone per app group (personal message, work message, email, other) | Improves every dictation |
| 3 | Models per feature | Pick a model for dictation, meetings and notes separately; cloud API keys (OpenAI, Anthropic, OpenRouter…); coding CLIs (claude, codex, gemini, pi) as providers for slow tasks | Groundwork for 4–6 |
| 4 | Upload audio/video | Import a file, extract audio, transcribe with the meeting transcript pipeline | Reuses existing code |
| 5 | Meetings v2 | Live meeting window with My thoughts / Transcript / Summary tabs and "Ask anything" | Needs the system-audio spike to pass first |
| 6 | Ask AI + MCP server | Chat that answers from notes, dictations and meetings; an MCP server so coding agents read the same data | One retrieval layer serves both |
| 7 | Calendar + export | Calendar via EventKit (Google and Microsoft accounts already added to macOS Calendar, no sign-in); export to Apple Notes and Notion | Polish |

## Notes on scope

- Item 3 replaced the single text model with connections (each with its own
  Keychain key) and a model per feature; `claude`, `codex` and `pi` can write
  meeting notes. Gemini was left out.
- Coding CLIs take several seconds per call: fine for summaries and Ask AI,
  too slow for dictation cleanup.
- Item 2 replaced `vocabulary.txt` with `dictionary.json` (words, heard-as
  forms, snippets); an existing `vocabulary.txt` is migrated once and renamed
  `vocabulary.migrated.txt`.

## Dropped

| Idea | Reason |
|---|---|
| Meeting bot that joins Zoom/Meet calls | Needs a cloud server and the meeting platforms' APIs; breaks local-first. BugVoice records mic + system audio on this Mac, as Granola does. |
| Connectors that post into Slack or email | Speak → format → paste is dictation plus Styles (item 2). Posting on the user's behalf adds accounts and risk for no gain. |
| Calendar sign-in with Google / Microsoft OAuth | EventKit reads those accounts through macOS Calendar with no login and no dependency. |

## Deferred

| Idea | Reason |
|---|---|
| Per-person speaker labels (diarization) | Needs a second dependency besides WhisperKit (maintainer decision). Revisit after You/Others is tested on real meetings. |
