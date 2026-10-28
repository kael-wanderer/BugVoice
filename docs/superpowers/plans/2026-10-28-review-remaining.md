# Codex review, remaining items — plan for Codex Sol (2026-10-28)

Source: `docs/research/2026-10-27-app-review-and-improvement-plan.md`. Five items
remain from it. Phases 1A–1C, 1D (app-level copy and Esc cancel), 2A, 4A and
most of 5 are already merged on `main`; do not redo them.

| # | Item | Review ref | Size |
|---|---|---|---|
| A | Crash recovery of an in-flight dictation | Phase 2 | small |
| B | Language choice on Retry of a failed recording | Phase 2B | small |
| C | Per-field destination check | Phase 1D | medium |
| D | Summary templates | Phase 4C | medium |
| E | Edit transcript lines, Revert original | Phase 4B | large |

Do them in this order. A–C touch the dictation path; D–E touch Meetings.

## Ground rules (all items)

- Read `AGENTS.md` and `docs/progress/HANDOFF.md` first. Ignore any
  superpowers skill header in older plans; execute directly.
- One branch per item, each from the latest `main` you have:
  `feat/crash-recovery`, `feat/retry-language`, `feat/field-check`,
  `feat/summary-templates`, `feat/transcript-edit`. If an item depends on an
  earlier unmerged one (B on A), branch from that item's branch and say so.
- Each item: write a short spec in `docs/superpowers/specs/2026-10-28-<name>-design.md`.
  Every item with UI also gets an HTML mockup
  `docs/design/proposal-<name>.html` (copy the structure, colour tokens and
  light/dark toggle of `docs/design/proposal-readiness.html`). Commit spec and
  mockup first (`docs: …`; item A's first commit also adds this plan file), then implementation commits (`feat(core): …`,
  `feat(app): …`), then add both doc links to `AGENTS.md` under Key documents.
- TDD for everything in `VoiceCore`: failing test first, confirm it fails, then
  code. Swift Testing (`@Test`, `#expect`). `swift test` must pass before every
  commit. Logic goes in `VoiceCore` where it can be tested; the app target stays
  thin.
- End every commit message with a blank line and
  `Co-Authored-By: Codex <noreply@openai.com>`. The pre-commit hook bumps the
  build in `App/Info.plist`; let it.
- No new dependency. `VoiceCore` imports Foundation only.
- Files you write under the BugVoice data folder: owner-only (folder 0700,
  files 0600, write to a temp file then `replaceItemAt`), as
  `FailedDictationStore` does.
- Errors shown or logged never include a provider response body; use
  `error.localizedDescription`.
- UI copy: plain English, no hedging words, no emoji.
- Never paste into a secure field. Never send audio or text off the Mac unless
  the user configured a remote server.
- Do not launch the app with a bare `open`; do not send synthetic key events or
  pastes (the owner is at the keyboard). `Scripts/build-app.sh` must succeed at
  the end of each item. Do not push or merge.
- If something in this plan does not match the code, or an item needs a design
  decision this plan does not make, write the question at the top of that
  item's spec, pick the safest option, and say so in the report.

At the end of each item, report: branch, commit hashes and messages, test
totals, owner device checks to add to HANDOFF, and any open questions. Then go
on to the next item.

---

## A. Crash recovery of an in-flight dictation

**Problem.** `DictationController.finishNow` writes `last.wav`, then
`process(...)` runs the pipeline. If BugVoice quits or crashes before the
result, the clip sits in `last.wav` with no record, and nothing tells the owner
on the next launch. Failed transcriptions already go to `FailedDictationStore`
(`Sources/VoiceCore/FailedDictationStore.swift`, list under Dictation ›
Needs attention, `AppModel.keepFailedDictation/reloadFailedDictations` in
`Sources/BugVoice/AppModel+Models.swift`).

**Decisions.**
- An in-flight marker, not a second audio copy: when an ordinary dictation
  starts processing, write `inflight.json` next to `last.wav` (add
  `AppPaths.inflightDictation`). It holds id, startedAt, appName, bundleID,
  duration. Remove it when the run returns any outcome (success, cancel,
  failure) — `defer`-style at the end of the processing task.
- Write the marker only when the run would be kept on failure today: ordinary
  mode (not notes or meeting notes), not secure at start, history retention not
  off, not a Retry of a kept recording, and `last.wav` was written for this clip.
- At launch, before the failed list loads: if `inflight.json` exists and
  `last.wav` exists and decodes, move the clip into `FailedDictationStore` with
  reason "BugVoice quit before this dictation finished." and the marker's
  metadata; then delete the marker. If either file is missing or damaged,
  delete the marker silently. Respect `maxCount`/`maxAge` (the store does).
- Never paste or copy at launch. The entry only appears under Needs attention.
- Model the marker in `VoiceCore` (`InflightDictation` Codable +
  `InflightDictationStore` with `begin`, `end`, `recover(into:lastRecording:now:)`)
  so all of it is unit-tested; the app calls it.

**Tests (VoiceCore).** begin/end round trip and owner-only modes; recover with
marker + wav → one failed entry with the marker's id/app/duration and the reason
text, marker gone; recover with no wav → nothing kept, marker gone; damaged
marker → nothing kept, marker gone; recover twice → one entry; expired marker
(older than `FailedDictationStore.maxAge`) → dropped.

**No mockup needed** (reuses the Needs attention row); the spec states the
reason text.

**Owner check.** Dictate a long sentence with a slow cleanup model, quit
BugVoice from Activity Monitor during Cleaning, relaunch: the dictation is
under Needs attention with the quit reason; Retry copies it.

## B. Language choice on Retry of a failed recording

**Problem.** Retry on a failed recording reruns with the language rule for the
original app. If the failure came from the wrong language (or the owner wants
another one), there is no way to choose.

**Decisions.**
- In `DictationHistoryView` (Needs attention row), Retry becomes a split
  control: the button retries as today; a menu beside it lists
  "Retry in English", "Retry in Vietnamese", … — exactly
  `settings.speech.dictationLanguages` — plus "Retry with automatic language"
  only if Auto is a valid choice in `LanguageResolver`.
- `DictationController.retryFailed(_:language:)` passes the choice as
  `languageChoice:` into `process(...)`, which already supports it. Text still
  goes only to the clipboard (`copyOnly: true`).
- If the retry fails, the entry's reason updates as today; the chosen language
  is not stored.
- Any pure helper for the menu items (labels, order) goes in `VoiceCore` with a
  test.

**Mockup.** The Needs attention row with the Retry menu open, light and dark.

**Owner check.** Make a Vietnamese dictation fail (speech server at a wrong
address), fix the server, Retry in Vietnamese: Vietnamese text on the
clipboard.

## C. Per-field destination check

**Problem.** Since 2026-10-27 a dictation is copied, not pasted, when another
*app* is in front at insert time (`copiedFocusChanged` in
`DictationPipeline.run`). A different *field* in the same app (another Slack
channel, another browser tab's input, another Notion block outside the same
text view) still gets the paste.

**Decisions.**
- `VoiceCore` stays Foundation-only, so the element comparison lives behind a
  protocol. Extend `FocusProvider` (in `DictationPipeline.swift`) with
  `func isSameTarget(asStart: FocusTargetToken?) async -> Bool?` or an
  equivalent design of your choice, where `nil` means "cannot tell". The app
  side captures the start element with `FocusInspector.focusedElement()` and
  compares with `FocusInspector.isSameElement` at insert time.
- Policy, in this order: secure (start or now) → copy; different app → copy
  (`copiedFocusChanged`); same app and the check says *different field* → copy
  with a new outcome `copiedFieldChanged`; same app and the check says *same*
  or *cannot tell* → paste. "Cannot tell" must paste: terminals and some
  Electron apps expose no stable focused element, and the review asks not to
  break them.
- HUD for `copiedFieldChanged`: warning "Copied — press ⌘V", detail
  "the cursor moved to another field". History and Insights treat it like
  `copiedFocusChanged`. Check every `switch` over `DictationOutcome`.
- Do not steal focus back.
- Learn-from-corrections and Fix last already use element identity; reuse
  `FocusInspector`, do not add another AX helper.
- Notes mode is unaffected.

**Tests (VoiceCore).** A fake `FocusProvider` returning same / different /
nil: pasted, `copiedFieldChanged`, pasted. Secure and different-app still win.
`HUDState` and history mapping for the new outcome (if `HUDState` is in the app
target, test the VoiceCore parts only).

**Mockup.** The HUD warning pill, light and dark.

**Owner checks (away from the keyboard is required: these paste).** Terminal
(Ghostty), VS Code, Chrome text field, Notion, Slack: dictate and stay put →
pastes. Slack: dictate, switch channel before the text lands → copied with the
new message. Terminal: dictate, click another split pane → note what happens;
pasting is acceptable if the terminal reports no element.

## D. Summary templates

**Problem.** Meeting summaries use one prompt
(`Sources/VoiceCore/MeetingTextGeneration.swift`, `systemPrompt(kind:stage:followsNotes:)`).
A stand-up, a design review and an interview need different shapes.

**Decisions.**
- Four built-in templates, no custom prompt editor: General (today's prompt,
  unchanged, the default), Technical design (decisions, options considered,
  open questions, risks), Stand-up (per person: done, next, blocked), Interview
  (candidate, topics, strengths, concerns, follow-ups). Write the prompt text
  in the spec; keep the existing output rules (Markdown, no invented owners or
  dates: missing owners and deadlines stay unspecified).
- A template has a stable id and a version (`general@1`). Store the id and
  version used on the meeting manifest (`MeetingManifest`, new optional fields,
  decoded with `decodeIfPresent` so old meetings load; old meetings read as
  General).
- Precedence: the owner's own notes ("My notes") still lead, as today
  (`followsNotes`); the template shapes the sections around them. State the
  exact wording in the spec.
- Chunking and merge (`split(transcript:budget:)`, part/merge stages) keep
  their budgets and cancellation behaviour; the template applies at both
  stages.
- UI: a template picker next to Generate / Regenerate on the meeting's Summary
  tab (and the meeting window's Summary if it has its own button). The picker
  shows the meeting's stored template; changing it does not regenerate until
  the owner presses Regenerate. Action items generation is unchanged.
- MCP `get_meeting` (or the tool that returns the summary) may include the
  template id; do not add a new tool.

**Tests (VoiceCore).** Each template's system prompt contains its sections and
the no-invention rule; General equals today's prompt byte for byte; manifest
round trip with and without the new fields; chunked generation passes the
template to part and merge stages (use the existing fakes in
`MeetingTextGeneration` tests).

**Mockup.** Summary tab with the picker closed and open, a Stand-up summary
example, light and dark.

**Owner check.** Regenerate one real meeting with each template; facts match
the transcript; no invented owners or dates.

## E. Edit transcript lines, Revert original

**Problem.** A wrong word in a meeting transcript (a name, a number) stays
wrong in the Transcript tab, exports, Summary regenerations and Ask answers.

**Decisions.**
- Scope: finished meetings and uploads only (`state == .ready`). Live
  transcription and the meeting window's live transcript are not editable.
- `MeetingSegment` gains optional `editedText: String?` and `editedAt: Date?`
  (`decodeIfPresent`; old files load unchanged). `text` stays the original
  Whisper output and is never overwritten. Add a computed `displayText`
  (`editedText ?? text`) and use it everywhere a line's words are read for the
  owner or a model: Transcript tab, export (`MeetingExport`), Summary and Action
  items generation input, Ask index and citations, MCP output, Scratchpad send,
  search. Grep for `.text` on segments and justify each remaining use of the
  original in the spec.
- Segment `id`, `start`, `end`, `track`, speaker and audio stay as they are, so
  playback from a line and citations keep working.
- UI on the Transcript tab: hover or right-click a line → Edit; inline text
  field; Return saves, Esc cancels. An edited line shows a small "Edited" label;
  its menu has "Revert to original", which clears `editedText`. Empty text is
  not allowed (Revert instead). Translation for that line clears when edited
  (it was of the old text) and regenerates the way untranslated lines do today,
  if Show English is on.
- Saving writes the manifest with the existing meeting store's write path
  (atomic, owner-only). A transcript edit made while a Summary or Action items
  generation is running for that meeting must not be overwritten when the
  generation finishes: the generation result writes only its own fields, read
  fresh from disk (or under the store's existing lock), never a stale whole
  manifest. Write a test for this race in `VoiceCore` if the store lives there.
- Summary and Action items made before an edit are not regenerated
  automatically. Show "Transcript edited after this summary" above an older
  Summary (compare the newest `editedAt` with the summary's generation time;
  add a `summaryGeneratedAt` if none exists).
- Ask: the index uses `displayText`; re-index the meeting after an edit the
  same way it is indexed after transcription. An Ask answer citing a line that
  was edited after the answer shows the current text.
- Backups include the edits automatically (they are in the manifest); confirm
  in a test or the spec.

**Tests (VoiceCore).** Old manifest decodes; edit and revert round trip;
`displayText` used by export, generation input, Ask index text, MCP format;
generation finishing after an edit keeps the edit; empty edit rejected.

**Mockup.** Transcript tab: a line in edit mode, an edited line with the label,
the line menu with Revert, the Summary notice; light and dark.

**Owner check.** Open a finished meeting, fix a name in one line, export: the
fix is in the export; Ask about it: the answer uses the fixed name; Revert:
original back.

---

## Finish

After all five items: `swift test` on each branch, `Scripts/build-app.sh` on the
last one. Report per item as described in Ground rules. Do not merge, push or
launch the app. Claude reviews each branch before it is merged.
