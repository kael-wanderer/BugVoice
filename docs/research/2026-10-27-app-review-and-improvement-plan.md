# BugVoice app review and improvement plan — 2026-10-27

Status: proposed implementation sequence, not approved scope or completed work.
Reviewed checkout: `864c404` on the current repository. Working tree was clean at review start.

## Assessment

BugVoice has a strong, unusually complete feature set for a personal dictation app. Its value is fast English/Vietnamese developer dictation, local processing, and a reusable library of notes and meetings. The next release should make that experience more dependable before expanding integrations.

Already implemented: live preview, per-app languages/styles, dictionary/snippets, project vocabulary, correction learning, command mode, raw/cleaned replacement, cleanup fidelity protection, meeting speakers/translation, Ask AI, MCP, Shortcuts, backups and update checks. These are not new roadmap proposals. Incremental final transcription is still a gated experiment; preview does not implement it.

The main opportunities are (1) privacy and output correctness at boundaries, (2) recovery without repeating speech, (3) measured release-to-paste latency, (4) correcting meeting outputs without losing work, and (5) discoverable configuration.

## Scope and evidence limits

This is a source, tests, UI-code and project-document review. No live GUI inspection, screenshot audit, real microphone recording, synthetic paste, provider request or owner-library inspection was performed. UI suggestions below are design recommendations, not claims of observed visual defects. The full automated test run passed: **1,315 VoiceCore + 30 MCPKit + 114 BugVoiceMac = 1,459 tests**. Passing tests do not disprove uncovered boundary cases.

The owner’s 2026-10-19 completion statement supersedes historical pending checklists. Later features have their own checks. Do not treat every old pending entry as an outstanding defect. Handoff and Roadmap still mix those historical entries with current state.

## Findings that should precede new features

| Priority | Source finding | Why it matters | Evidence |
|---|---|---|---|
| P1 | Ordinary insertion checks current secure state but does not preserve the secure-at-start classification for result/history | Start in a secure field, move to an ordinary field while processing: the result can be treated as a normal insertion and recorded. Start-time audio exclusion already exists, but text classification is inconsistent. Device reproduction not performed. | `Sources/VoiceCore/DictationPipeline.swift:261`, `:77`; `Sources/BugVoice/DictationController.swift:288`, `:370` |
| P1 | Speech-server requests default to `URLSession.shared`, unlike the shared no-redirect helper | A server redirect is not stopped at the delegate boundary. Test locally whether request content follows 307/308 and reject redirects before any second request. No actual leak was observed. | `Sources/VoiceCore/OpenAICompatibleTranscriber.swift:11`, `:45`; `Sources/VoiceCore/HTTP.swift` |
| P1 | HTTP errors/malformed replies can contain response-body fragments; dictation errors are publicly logged | A provider that echoes transcript/request content can expose it through error logging. Redact at error construction, not only the final log call. | `Sources/VoiceCore/HTTP.swift`; `Sources/BugVoice/DictationController.swift:360` |
| P1 | Placeholder stripping removes every square-bracket span | A transcript such as `use items[0]` becomes `use items`; the fidelity checker runs after this loss and cannot recover it. | `Sources/VoiceCore/DictationPipeline.swift:124`, `:187` |
| P2 | Ordinary paste checks security but not whether the destination is the original field | Switching apps during slow transcription/cleanup can send text to the newly focused app. This is a proposed safer destination policy; current behavior may be intentional. | `Sources/VoiceCore/DictationPipeline.swift:261`; `Sources/BugVoiceMac/PasteboardInserter.swift:22` |
| P2 | Retry audio is a single `last.wav`; failed STT produces no history entry | A later recording can overwrite the only retryable audio. Existing Retry last is useful but not durable recovery. | `Sources/BugVoice/DictationController.swift:294`; `Sources/VoiceCore/DictationPipeline.swift:79` |
| P2 | Action-item identity is derived from normalized text | Regeneration or an owner/text change creates a new key, so a previously completed equivalent item appears open. This follows from the model, not a reproduced device bug. | `Sources/VoiceCore/ActionItems.swift:28`, `:55`, `:96` |
| P3 | Connection testing lists models but never generates; settings search indexes selected labels only | Reachable is not proof that the assigned model can complete cleanup. Backup, fidelity, preview and language settings need better search aliases. | `Sources/BugVoice/AppModel+Models.swift:53`; `Sources/VoiceCore/GlobalSearch.swift:44` |

## Delivery plan

Estimates are rough engineering days for one developer, including automated validation but excluding owner availability, real-voice corpus collection and unexpected macOS behavior. They are planning ranges, not deadlines. Build each independently reviewable task as a separate commit; use failing tests first for VoiceCore and run `swift test` before commits. Keep the existing dependency and signing rules.

### Phase 1 — close correctness and privacy gaps (4–7 days)

**1A. Preserve privacy classification throughout a dictation (1–2 days).**

- Add an explicit run-level sensitivity policy derived from start focus and the final focus check. Secure/unknown-sensitive classification must not be downgraded merely because focus changes.
- Apply it consistently to history, recall, preview, correction learning, insights and retained audio. Audit retry/redo/command paths against the same policy.
- Keep the current secure-field copy behavior; never post paste to a secure field. Do not silently change configured provider selection as part of this fix.
- Tests: secure→ordinary, ordinary→secure, unknown focus, focus lookup failure, cancelled runs, retry and notes-mode isolation. Verify no sensitive history/recall/audio remains.
- Acceptance: changing focus cannot turn a sensitive run into persistent ordinary history.

**1B. Make provider failures safe (1 day).**

- Default server STT to the existing no-redirect session while retaining session injection for tests.
- Replace raw response bodies in routine errors with structured status/category and a safe user message; cover malformed successful replies too.
- Log only safe diagnostic fields. Test with a sentinel secret in a failed response and a malformed JSON response.
- Use local mock servers to test 301/302/307/308; assert the redirect destination receives no request body. No real credentials or recordings are needed.
- Acceptance: no redirect follow-up and no sentinel content in public diagnostic/error output.

**1C. Preserve legitimate bracketed text (0.5–1 day).**

- Replace broad bracket removal with an explicit allowlist of observed Whisper annotation tokens. Preserve unknown bracketed content.
- Cases: `[BLANK_AUDIO]`, `[Music]`, `items[0]`, `[String]`, `[draft]`, Markdown links and mixed Vietnamese/English text.
- Acceptance: known empty-audio markers remain filtered; legitimate code/prose reaches the fidelity check intact.

**1D. Make destination changes explicit (1.5–3 days).**

- Capture a destination token at recording start: process/app plus accessible element identity where available. Reuse focus-identity facilities already used for corrections/command mode.
- Immediately before posting paste, verify the original destination. If it changed or cannot be verified, copy and show “Copied — focus changed”. Do not steal focus back automatically.
- Retain the processing task and propagate cancellation through transcription, cleanup and the final insertion guard. Suppress late results immediately even if Core ML computation takes time to unwind. Test cancellation during each stage and a late successful response.
- Keep note dictation bound to its captured note/editor. Ensure clipboard restoration cannot overwrite a newer clipboard change, including the unconsumed-paste path.
- Tests: app switch, two fields in one app, destroyed field, unavailable AX identity, clipboard changed during wait, normal unchanged target.
- Acceptance: the declared target policy is consistent and the original text remains recoverable. Owner validates compatibility in Terminal, editor, browser and Notion while away from the keyboard for synthetic paste checks.

### Phase 2 — recover failed dictations (3–5 days)

**2A. Add a small durable recovery store.**

- Introduce a Foundation-only manifest and state machine: captured → transcribing → ready/failed; interrupted processing returns to retryable after relaunch.
- Store each eligible recording under an independent ID with atomic manifest updates. Exclude sensitive and private-note runs; respect history-off behavior through an explicit separate retention choice.
- Proposed retention: opt-in, at most 10 clips, 24 hours, plus a hard byte cap. Show the policy before enabling; never silently retain more audio than current settings promise.
- Define backup policy explicitly; default to excluding transient recovery audio. Deletion, expiry, retention disable and disk-full behavior must be deterministic.

**2B. Extend the existing Dictation page.**

- Add a compact “Needs attention” section with timestamp, language, duration, reason, Retry, Copy result and Delete. Menu popover links to it.
- Retry can select a language/model and yields text for explicit copy/paste; background recovery must never auto-paste into whatever happens to be focused.
- Keep ordinary successful history visually simple; do not add another top-level page.

**Validation:** crash/relaunch during each state; second recording after first fails; missing/corrupt audio; full disk; expiration; concurrent retry/delete; settings changes; sensitive-run exclusions. Acceptance: multiple failures remain recoverable within the stated retention limits and successful retry never surprises the current app with a paste.

### Phase 3 — improve speed only after measurement (1–2 days measurement; 4–7 days implementation if gate passes)

- Continue the existing incremental transcription decision, not a new architecture proposal. Read `docs/progress/incremental-log.md` and its spec/bench plan.
- Owner records the six requested real long clips. Run the existing latency bench and retain raw results and configuration. Current synthetic results narrowly fail the original 1.0-second 30s+ target; they are not sufficient evidence to ship.
- Apply the recorded owner decision: consider the 0.8-second long English/mixed threshold only after the real-voice rerun supports it. Keep the existing accuracy and short-utterance non-regression gates.
- Measure STT, cleanup, insertion, cold/warm state, preview on/off and concurrent meeting load separately. Add p50/p95 release-to-result reporting with sample counts; distinguish text-ready from pasted.
- If eligible, implement stable chunk reuse, final-tail decoding, cancellation and preview/part-pass scheduling. If the gate fails, record the result and defer incremental final STT.
- Expand fidelity evaluation using consented local replay and crafted numbers, negations, paths, identifiers and literal brackets. Report false positives and missed changes separately; existing 14-entry replay is a small sample.
- Acceptance: measured benefit survives real bilingual speech and preview contention, with no material accuracy regression. No claim of semantic correctness from the heuristic fidelity check.

### Phase 4 — make meeting outputs editable and durable (6–10 days)

**4A. Stabilize action items first (2–3 days).**

- Persist structured items with stable IDs, owner, text and completion; migrate existing keys and preserve completed work.
- Generation produces a proposed revision, not an overwrite of user-maintained state. Match exact source-backed items; show ambiguous additions/removals for review instead of guessing completion by semantic similarity.
- Tests: rewording, owner edit, duplicate items, changed order, reload, backup/restore, old-format migration and regeneration cancellation.
- Acceptance: editing/regeneration never silently resets a user’s completed item.

**4B. Edit transcript lines with provenance (3–5 days).**

- Add Edit and Revert original to a transcript line, preserving audio, timestamp and stable line ID. Start with finished meetings/uploads, not live transcription.
- Save original text plus revision metadata. Update search indexing; mark translation, summaries and action-item extraction stale when their source revision changes.
- Prevent an in-flight old generation from overwriting a newer transcript revision. Existing Ask citations must resolve to the current source or visibly indicate an outdated answer.
- Exports use corrected text; original audio remains unchanged. Include revisions in backups and define MCP read behavior.
- Acceptance: correction survives relaunch/export; audio seeking still works; stale derived results are visible and can be regenerated explicitly.

**4C. Add a few summary templates (1–2 days).**

- General, technical design, stand-up and interview presets; preserve current “follow my notes” behavior and define its precedence over templates.
- Persist template ID/version per meeting. Avoid arbitrary prompt-building UI in the first iteration.
- Evaluate factual fidelity on fixed local transcripts; missing owners/deadlines must stay unspecified. Current generator already chunks and merges; preserve those token-budget and cancellation guarantees.

Due dates/reminders should follow stable action-item IDs as a separate optional increment. Avoid turning BugVoice into a full task manager.

### Phase 5 — reduce configuration friction (2–4 days)

- Add a compact readiness card in existing Settings/menu surfaces: microphone, hotkey, speech model, selected cleanup model, and specific repair links. Reuse existing permissions and connection status.
- Distinguish “Server reachable” from “Selected model tested”. Offer an explicit synthetic generation test with no owner text; show where the configured request goes and whether raw fallback is available.
- Expand existing settings search with aliases for language, fidelity, live preview, backup, retention, input device and correction learning. Do not build a second search system.
- Correct Permissions copy that still refers to “Settings → Text model”; settings now has Models and a separate speech-server configuration.
- Perform a real UI pass at normal/large text sizes and narrow/wide windows: keyboard traversal, VoiceOver names, non-color status, long errors and offline states. Audit nine Settings sections for overflow before changing navigation.
- Acceptance: common repair tasks are reachable from their error state; settings queries find the correct section; keyboard and enlarged-text flows remain usable.

## Release order and decision points

| Release slice | Contents | Exit gate |
|---|---|---|
| A: trust fixes | Phase 1 plus documentation reconciliation | Regression tests, signed build, targeted owner focus/clipboard checks |
| B: recovery | Phase 2 | Crash/retention tests and owner recovery smoke |
| C: speed | Phase 3 only if real-voice gate passes | Published before/after report with quality and contention results |
| D: meeting quality | Phase 4 | Migration, revision/citation/export and user-edit preservation tests |
| E: usability | Phase 5; small copy/search fixes can land in A | Live keyboard, accessibility and scaled-layout checks |

Recommended first commitment: Release A, then recoverable dictation. Collect the real-voice corpus alongside that work. Choose meeting improvements after those foundations, based on actual meeting use.

Deferred: frozen Calendar/export integrations, another Home page, additional providers/languages without demand, broad visual redesign, and a general command grammar. The current shell/search and feature set already cover these adjacent needs sufficiently to prioritize dependability.

## Project documentation and verification

Create a current-state table with implemented, automated-tested, owner-verified and blocked fields; keep historical logs in a clearly historical section. Reconcile obsolete “not merged”, packaging build and “Calendar next” statements with current source/history without inventing device evidence. Record current exceptions (later feature checks and the incremental real-voice gate).

For each delivered slice: failing VoiceCore tests first, targeted Mac tests, `swift test`, `Scripts/build-app.sh` with Bugler Local Dev, then `Scripts/run-dev-app.sh` for owner/device validation on the non-primary display. Unit tests and compilation do not count as microphone, paste, Bluetooth or layout verification. Update repo progress and BugMind copies together. No new external dependency is necessary for the proposed first releases.

This review added documentation only. No implementation, app launch or device check was performed. Detailed core evidence is in `docs/research/2026-10-27-core-review-notes.md`.
