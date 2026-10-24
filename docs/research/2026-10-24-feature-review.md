# BugVoice feature review — 2026-10-24

Reviewed current `main` at `0440a53`. This is a recommendation, not an approved implementation plan. Source inspection establishes feature presence, not device reliability.

## Existing value

BugVoice already spans dictation, command rewriting, notes, local meetings and uploads, and retrieval across that library. Do not re-propose these shipped capabilities:

- Dictionary words, snippets, app styles, app language rules, project vocabulary, correction suggestions, live preview, raw-paste replacement and another-language redo.
- Meetings with live transcription, translation, speakers, summaries and action items; the shared action list already has completion state and owner filtering.
- Notes/Scratchpad, folders and tags, Ask AI, MCP, Shortcuts, backups and retention.
- Context before and after the cursor already enters cleanup prompts: [PromptBuilder](../../Sources/VoiceCore/PromptBuilder.swift).
- Retry already exists: [DictationController](../../Sources/BugVoice/DictationController.swift) saves and retries `last.wav`. Meetings and uploads also have recovery paths.

[Roadmap](../ROADMAP.md) has historical branch/device-status entries that disagree with current source and [proposals](../propose-new-features.md). Use current source and recent progress logs when selecting work.

## Recommended tiers

Priority assumes BugVoice's primary job remains dependable, quick dictation for a bilingual developer. The first tier strengthens that job before expanding the product.

| Rank | Tier | Addition | Concrete benefit and distinction from existing features |
|---|---|---|---|
| 1 | Must have | Faster final dictation through incremental transcription | Reuse stable transcription work performed while speaking; finish only the remaining audio on release. Existing preview is explicitly display-only and uses a separate base model, so this is substantial pipeline work, not enabling the HUD. Measure tail latency and English/Vietnamese/mixed accuracy before selecting the design. |
| 2 | Must have | Cleanup fidelity protection | Check numbers, negations, paths and identifiers before accepting cleanup. Existing terminal style asks the LLM to be literal; add conservative raw fallback or review when a protected detail changes. Semantic checks need evaluation and cannot guarantee correctness. |
| 3 | Must have | Recoverable dictation queue | Keep a small, local, expiring set of failed/pending recordings with retry, language selection and copy after recovery. Last-recording retry exists, but a subsequent recording overwrites its audio; failed transcription has no history entry. Preserve secure-field exclusions and make retention explicit. |
| 4 | Good to have | Exact coding and spelling commands | Say “snake case user profile” or spell an identifier with deterministic formatting. Extends existing terminal style and project vocabulary. |
| 5 | Good to have | Correct the last dictation by voice | “Replace X with Y” and “undo that correction,” scoped to a verified last insertion. This extends command mode and Paste raw with a direct, safe correction path; it must refuse replacement if the field has changed. |
| 6 | Good to have | Editable meeting transcript | Correct a misheard line while preserving original audio/timestamps; regenerate affected summaries and refresh search citations. Speaker naming exists; transcript text editing was not found in the inspected transcript views. |
| 7 | Good to have | Meeting summary templates | Choose stand-up, technical design, interview or personal review outputs. Current summary generation offers fixed summary/action-item prompts. Templates should work with both recordings and uploads. |
| 8 | Good to have | Action-item dates and follow-through | Add explicit due dates, overdue views and optional local reminders. Owners, filtering and checkboxes already exist; this extends them rather than proposing another action list. |
| 9 | Optional | Resume read-only Calendar support | EventKit can supply meeting title, agenda and attendees. This intentionally reopens a frozen roadmap item and should wait for owner demand. |
| 10 | Optional | Explicit export destinations | Apple Notes/Reminders or selected Notion destinations could reduce copying. Start with local destinations; keep posting user-triggered. Integrations are currently frozen. |
| 11 | Optional | Additional languages and specialist profiles | Expand beyond English, Vietnamese and Spanish only against real usage demand and a representative accuracy corpus. |

## Evidence behind the gaps

- [LivePreview.swift](../../Sources/VoiceCore/LivePreview.swift) says preview never feeds final transcription or persistence. [DictationPipeline.swift](../../Sources/VoiceCore/DictationPipeline.swift) transcribes the complete clip after recording, then cleans and inserts it.
- [OutputSanitizer.swift](../../Sources/VoiceCore/OutputSanitizer.swift) strips reasoning/markup and rejects empty or overly long output. It does not validate number, identifier or semantic preservation; snippet placeholders are separately guarded in the pipeline.
- [DictationController.swift](../../Sources/BugVoice/DictationController.swift) writes one last recording and `retryLast()` replays it. [History.swift](../../Sources/VoiceCore/History.swift) stores text and timings, not per-entry audio; `DictationResult.historyEntry` omits failed transcription.
- [MeetingTranscriptView.swift](../../Sources/BugVoice/UI/MeetingWindow/MeetingTranscriptView.swift) provides transcript search/playback; [MeetingsPage.swift](../../Sources/BugVoice/UI/MeetingsPage.swift) includes title and speaker editing. No line-text editing was found in those views.
- [MeetingTextGeneration.swift](../../Sources/VoiceCore/MeetingTextGeneration.swift) contains the summary/action-item prompts; [ActionItems.swift](../../Sources/VoiceCore/ActionItems.swift) has owner and completion/filtering support but no due-date model.

## External comparison

Official [Wispr context-awareness documentation](https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness) describes surrounding-text formatting and IDE file tagging. BugVoice already supplies surrounding text and project vocabulary, so generic context awareness is not a new recommendation. [MacWhisper CLI documentation](https://docs.macwhisper.com/article/57-macwhisper-command-line-tool) describes scriptable transcription and structured exports; BugVoice already has MCP and Shortcuts, making another automation surface a lower priority. These are comparison points, not proof of demand.

## Suggested delivery order

Ship recoverable dictation and cleanup fidelity protection first because they address loss and correctness. Prototype incremental final transcription next, measuring accuracy and latency before committing to an architecture. Then choose one meeting improvement based on actual usage. Avoid resuming every frozen integration or adding more top-level pages at once.

No app source was changed and no device checks were run for this review.
