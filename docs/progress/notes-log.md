# Notes implementation log

## Summary

Implementation is complete on `feat/notes`; final build and launch passed. Notes manual checks remain pending.

- **Documentation commit:** 035a116 — docs: notes design and implementation plan
- **Baseline tests:** swift test passed with 192 VoiceCore tests in 26 suites and 27 BugVoiceMac tests in 7 suites (219 total).
- **Final suite:** `swift test` passed with 223 VoiceCore tests in 31 suites and 49 BugVoiceMac tests in 11 suites (272 total).
- **Build / launch:** `Scripts/build-app.sh` passed and signed `build/BugVoice.app` with `Bugler Local Dev`; the app launched and remained running. `codesign` reported `Authority=Bugler Local Dev` and `Identifier=com.kael.bugvoice`.
- **UNVERIFIED:** all Notes manual checklist rows 63–72 remain blank. Live microphone, clipboard observation, focus/caret behavior, external-change UI, export dialog, and quit dialogs were not manually exercised. The production build emits the existing WhisperKit non-Sendable warnings in `WhisperKitTranscriber.swift`.

## Approved decisions and costs

- Loaded-note in-memory buffers owned by NotesController are authoritative. NotesStore directly applies an insertion only when a note is not loaded. Successful store writes return the new file version to NotesController so its own writes cannot become external-change warnings.
- One NSUndoManager per loaded note is retained by NotesController for the app run, including while the editor is off screen. Undo history does not survive relaunch.
- The external-change fingerprint checks modification time, size, and a stable 64-bit FNV-1a hash on selection, app activation, and before every save. Hashing reads the whole note file; this linear I/O cost is accepted for expected note sizes.
- If registering ⌃⌥N fails, show “New note shortcut unavailable” in the menu; the menu action remains usable.
- Note files without a leading nonempty H1 derive the title from the filename stem, with hyphens changed to spaces. The entire file remains body content until edited.
- Notes routing is selected only at recording start. Later focus changes do not cancel or reroute the run. An unchanged note uses the captured selection; a changed note appends. A deleted note discards the result. Notes never write dictation history, last.wav, menu last-result, or pasteboard.
- Body saves debounce 500 ms. A title rename commits only on Return or title-field focus out.
- Notes implementation is complete; no Notes manual checklist behavior has been verified yet.

## Implementation commits and verification

| Commit | Task | Tests | Notes |
|---|---|---|---|
| 035a116 | Approved spec, plan, and scratch ignore | Baseline: 192 VoiceCore + 27 BugVoiceMac passed | Documentation only |
| a8d8a82 | Task 1: VoiceCore note model, parsing, slug policy | 203 VoiceCore + 27 BugVoiceMac passed | Foundation-only policy and Notes directory |
| e48f79e | Task 2: route, insertion, search, export | 214 VoiceCore + 27 BugVoiceMac passed | Notes pipeline mode and VoiceCore operations |
| a690259 | Task 3: autosave and external-version policy | 222 VoiceCore + 27 BugVoiceMac passed | 500 ms debounce and FNV-1a version checks |
| 0e53b0d | Task 4: durable NotesStore actor | 222 VoiceCore + 34 BugVoiceMac passed | One actor owns Markdown file operations |
| ea0c27f | Task 5a: loaded note buffer and undo | 222 VoiceCore + 41 BugVoiceMac passed | Buffer authority, pending-save insertion, and per-note undo |
| 9f769f8 | Pre-Task 5b ordinary dictation regression | 223 VoiceCore + 41 BugVoiceMac passed | Pins exact output and inserted UTF-8 bytes for outside-app dictation |
| 5d05016 | Task 5b: Notes route-at-start wiring | 223 VoiceCore + 43 BugVoiceMac passed | Captured-note routing; ordinary byte regression stayed green |
| de5954e | Task 6: Notes page and lifecycle integration | 223 VoiceCore + 49 BugVoiceMac passed | UI, menu, storage, activation refresh, combined quit handler |

## Decisions made during implementation

See each task section below for decisions, rationale, and cost if wrong.

## Skipped or NOT BUILT

See each task section below. Manual and live app checks remain unverified until final launch/checklist work.

## Manual checklist

Not run. Keep all Notes Result cells blank until the maintainer performs the device checks.

### Task 1 — VoiceCore note document and slug policy

- Test-first: NotesDocumentTests initially failed to compile because NotesMarkdownDocument and NotesSlug were not implemented. After the first implementation, the collision tests failed because candidate allocation retained title casing and therefore missed case-insensitive existing names. Normalizing the requested base through NotesSlug.make fixed both cases.
- Implemented Markdown H1 parsing/serialization, filename-derived titles for non-H1 and empty files, Vietnamese Đ/đ slug mapping, ASCII slug/collision allocation, and Notes directory creation.
- Tests: focused NotesDocumentTests passed (11); full swift test passed with 203 VoiceCore tests / 27 BugVoiceMac tests (230 total).
- Self-review: parsing and slug/collision policy remain Foundation-only; opening a non-H1 file returns a parsed value and performs no write; AppPaths creates Notes with existing app directories.
- Decision left by the plan: invalid UTF-8 note files surface a parse error rather than lossy decoding, preserving the no-silent-content-change rule. Cost if wrong: externally created invalid files need an explicit user-facing recovery flow; no lossy conversion is attempted.
- Skipped / UNVERIFIED: none for Task 1. Notes UI and real filesystem durability remain for later tasks.

### Task 2 — VoiceCore route, insertion, search, export, and Notes pipeline mode

- Test-first: new policy/list/export/pipeline tests first failed to compile because the Notes policy/export interfaces did not exist. The first route test run then exposed two test-fixture cases where nil optional arguments meant “keep the existing value”; the fixture now explicitly supplies optional nil for missing note/selection. The policy tests pass.
- Implemented immutable start captures, insertion placement (captured selection for unchanged revisions, body end for changed revisions, discard only for a deleted note), literal case/diacritic-insensitive search, deterministic sorting, canonical Markdown export, and Notes-specific pipeline outcomes.
- The Notes pipeline forces document style and directly invokes its injected insertion target without checking end focus or calling copy. Ordinary mode retains the existing secure-field and paste path.
- Tests: NotesPolicyTests 5, NotesListProjectionTests 2, NotesExportTests 2, DictationPipelineTests 27 all pass. Full swift test passed with 214 VoiceCore tests / 27 BugVoiceMac tests (241 total).
- Self-review: Notes routing is computed once and the immutable capture contains the note/editor IDs, selection, revision, and initial body length. Later focus cannot change policy output. Insertion placement uses current body length only for changed-revision append. Notes outcomes have no history entry. Ordinary-path tests continue to pass.
- Decision left by the plan: in Notes pipeline mode, InsertionTarget.notConsumed maps to the deleted-note outcome because the Notes route injects only a captured-note target and never a paste target. Cost if wrong: a separate target failure may be described as deletion; the Notes adapter should return notConsumed only when the captured note no longer exists.
- Skipped / UNVERIFIED: app-level route capture and file/buffer integration are Task 5a/5b; no Notes UI, clipboard observation, audio, or manual check has been run.

### Task 3 — Autosave and external-version policy

- Test-first: NotesAutosaveTests first failed to compile because the policy/fingerprint interfaces were missing. Implemented the policy and a stable FNV-1a fingerprint; all focused tests passed.
- Covered 500 ms deadline/reset, title commit reasons, last-committed title during body save, revision ordering, FNV-1a known vectors, equal-mtime/equal-size content changes, metadata changes, and only the selection/activation/before-save refresh triggers.
- Tests: NotesAutosaveTests 8 passed; full swift test passed with 222 VoiceCore tests / 27 BugVoiceMac tests (249 total).
- Self-review: FNV-1a is deterministic and non-cryptographic, used only for change detection. It does not replace file version metadata. Actual file reading and version refresh remain in NotesStore.
- Decision left by the plan: same-revision saves are permitted as idempotent writes; strictly older revisions are rejected. Cost if wrong: duplicate work for retries, but same-revision data cannot overwrite newer content.
- Skipped / UNVERIFIED: real debounce task scheduling and file fingerprint checks await NotesStore/controller implementation. No polling was added.

### Task 4 — Single-owner durable NotesStore actor

- Test-first: NotesStoreTests first failed to compile because NotesStore did not exist. Initial tests then exposed that decoded revisions must come from the actor's saved-revision map, older revisions must be rejected before comparing the version changed by a newer in-app write, and URL resource-value timestamps were not stable on immediate reread. The store now reads modification time from file attributes and compares the whole mtime/size/FNV fingerprint before every save.
- Implemented one NotesStore actor for listing, opening, creating, saving, committed-title rename, external-change checks, and confirmed move-to-Trash. Durable writes use unique same-directory temp files, write all bytes, fsync file, atomic POSIX rename, then fsync directory. Successful writes return a version for the controller baseline. External clean changes reload; dirty changes return conflict; confirmed Keep mine replaces after the pre-save fingerprint check.
- Tests: NotesStoreTests 7 passed, covering canonical create/save/open, non-H1 open without rewrite, case-insensitive collisions and rename identity, clean reload and dirty conflict, explicit Keep mine, newer-revision preservation, and confirmation-gated Trash. Full swift test passed with 222 VoiceCore tests / 34 BugVoiceMac tests (256 total).
- Self-review: Note reads and writes are actor-isolated and no UI thread performs file I/O. The store retains NoteID-to-path identity across a rename during the app run. If a filename is reused while the old renamed note remains loaded, the new note receives a distinct in-memory UUID. All saved files remain `Notes/<slug>.md`; IDs are not serialized in Markdown.
- Decision left by the plan: the durability call order is implemented directly with POSIX calls rather than an injectable filesystem abstraction. Cost if wrong: tests do not fault-inject each fsync/rename boundary, so failure recovery for hardware/filesystem errors relies on code review and returned errors.
- Skipped / NOT BUILT: direct insertion into unloaded notes is deferred to Task 5a because loaded-buffer authority must be coordinated there. No watcher or polling loop was added.
- UNVERIFIED: crash/power-loss durability and system Trash behavior outside the temporary-directory test are not manually checked.

### Task 5a — Loaded-note buffer, insertion, and undo

- Test-first: controller and insertion tests first failed to compile because NotesController and NotesEditorInsertion were not implemented. Tests now cover in-memory buffer ownership during a pending save, captured-note routing, unloaded direct-store insertion, version-baseline updates, deleted-note rejection, and per-note undo lifetime.
- Implemented NotesController as the authoritative loaded-note buffer. User edits and captured dictation update the buffer and visible text view, increment revision, and rearm the normal 500 ms save. Saves run through NotesStore and update the controller's known file version. The store has a direct insertion operation for notes not loaded in the controller. Each loaded note retains its own undo manager for the app run, including off-screen insertion; NotesTextView supplies it through the AppKit `undoManager` override.
- Tests: NotesControllerTests 5 and NotesEditorInsertionTests 2 passed; NotesStoreTests 7 passed; full swift test passed with 222 VoiceCore tests / 41 BugVoiceMac tests (263 total).
- Self-review: loaded insertions do not call NotesStore's direct insertion path; pending body edits are kept because dictation mutates the same note buffer before the save snapshot. A successful store write updates the baseline before selection refresh. NotesEditorInsertion has no pasteboard dependency and its `copy` method is a no-op.
- Decision left by the plan: controller retains every loaded note and its undo manager for the full app run; no unload/eviction policy was added. Cost if wrong: long sessions with many opened notes retain their in-memory buffers and undo histories until app exit.
- Skipped / UNVERIFIED: an AppKit test that created a real NSWindow passed alone but caused the combined controller test process to exit with signal 11, so it was removed. The visible-window placement and editing behavior remain for manual verification; off-screen buffer insertion and undo are automated. No Notes UI delegate wiring exists yet.

### Task 5b — DictationController route-at-start wiring

- Before touching DictationController, committed `9f769f8` with a regression test that pins the ordinary Safari dictation's exact final UTF-8 bytes, PasteboardInserter payload bytes, insertion count, and no-copy behavior. Full swift test passed before that commit.
- Added app-owned NotesStore/NotesController, a Notes page route marker, and a NotesController capture method that requires BugVoice frontmost, Notes selected, and the matching NotesTextView as first responder. DictationController stores that immutable capture at recording start and uses it through completion, independent of later focus changes.
- Notes runs skip all last.wav reads/writes/removal and skip AppModel.record, so they do not alter audio replay, last-result, or history. They pass the captured NotesEditorInsertion and explicit Notes mode into the existing pipeline. Ordinary retry, paste-last, clipboard, secure-field and provider paths are unchanged.
- A clean external body reload increments the loaded buffer revision when the body changed, causing a captured run to append to the reloaded body instead of using a stale selection.
- Tests: route-capture start conditions and changed-body append pass in NotesControllerTests; ordinary byte regression remains passing. Full swift test passed with 223 VoiceCore tests / 43 BugVoiceMac tests (266 total).
- Self-review: DictationController selects the target once in `begin`; `finish` only uses the stored capture. A Notes result does not reach `AppModel.record`. If no Notes capture exists, code follows the existing ordinary pipeline and last.wav branch.
- Decision left by the plan: only a body-content change during clean external reload increments the insertion revision; title-only or metadata-only changes preserve the captured body selection. Cost if wrong: if title-only changes should count as an edited body, dictation would insert at selection rather than append.
- Skipped / NOT BUILT: mic button integration, in-editor route availability in a real Notes page, and UI conflict/save-state presentation are Task 6. No outside-BugVoice behavior changes were made.
- UNVERIFIED: no live microphone, focus-loss recording, last.wav filesystem observation, pasteboard observation, or app launch has been run yet.

### Task 6 — Notes page, menu, storage settings, and quit integration

- Test-first: added a Store regression for a delayed body save after title rename. It failed because the rename did not advance the Store's saved revision. Rename now accepts and records a revision above the controller's current buffer revision; the delayed write is rejected as stale. `NotesStoreTests` passed (9).
- Implemented the searchable split Notes page, title and Markdown body editors, word count/modified-time rows, save/conflict states, New note, mic/listening bar, Markdown copy/export, confirmed Trash, menu shortcut, shortcut registration feedback, storage count/allocated-size row, app-activation refresh, and the combined Meetings/Notes quit flow. The Notes mic button refuses first responder so it preserves the editor selection.
- Tests: full `swift test` passed with 223 VoiceCore + 49 BugVoiceMac tests (272 total). This includes the ordinary dictation byte regression, Notes route/insertion/privacy tests, pending-save buffer test, title-rename revision race, and global shortcut registration failure test. `git diff --check` passed.
- Self-review: Notes file access remains in NotesStore; storage measurement and export writes run detached. NotesController remains authoritative for loaded notes and receives its own store versions. `applicationShouldTerminate` is still the single handler. Failed shortcut registration leaves the menu action available and shows “New note shortcut unavailable”.
- Decisions left by this plan: a blank committed title becomes “Untitled”; rename advances the note revision beyond the current loaded buffer revision to invalidate queued body snapshots. Cost if wrong: users cannot intentionally keep an empty title, and callers that bypass NotesController must supply a revision that reflects pending edits.
- Skipped / NOT BUILT: no UI automation was added for showing the shortcut-registration warning or the combined quit dialog; those remain manual-checklist cases. Export overwrite behavior uses NSSavePanel's standard confirmation.
- UNVERIFIED: live NSWindow caret/focus behavior, ⌃⌥N inside the running app, activation conflict UI, menu shortcut warning visibility, Storage rendering, export dialog/write, Trash dialog, combined quit interaction, and launch behavior remain for the final app launch/manual checklist. No live microphone or clipboard observation has been run.

### Task 7 — Manual checklist, handoff, final build

- Added Notes manual checklist rows 63–72 with blank Result cells, updated the sub-project status in `AGENTS.md`, and recorded Notes branch status and remaining maintainer gates in `HANDOFF.md`.
- Verification: final `swift test` passed (223 VoiceCore tests / 31 suites; 49 BugVoiceMac tests / 11 suites). `Scripts/build-app.sh` passed. The built app was opened once; process `BugVoice` remained running. `codesign -dv` confirmed `Bugler Local Dev` and `com.kael.bugvoice`. `git diff --check` passed.
- Self-review: earlier Dictation and Meetings maintainer gates are retained. Notes manual Result cells remain blank. `.planning/` remains ignored scratch and is not committed. No merge or push was performed.
- Skipped / UNVERIFIED: all Notes manual checklist rows, live microphone and actual pasteboard observation, and UI-only editor/focus, export, shortcut-warning, storage, Trash, and combined quit behavior await maintainer checks.

## Whole-branch review fixes

### Review item 1 — Notes mic route and last selection

- Test-first: added a VoiceCore policy test for mic capture with no first-responder requirement and a controller test for using the editor's last selection after focus moves. The policy test first failed to compile because `captureForMic` was missing; the first controller run exposed that the fixture had not moved the NSTextView selection, so the test now models the selection callback before focus loss.
- Implemented a dedicated Notes mic capture policy requiring a selected, editable note and valid cached selection. `NotesTextView` selection changes update the loaded note's last range. The mic button passes a Notes-only start mode and returns without starting if there is no selected note; it cannot fall back to ordinary dictation. The existing Right Option route continues to require its original frontmost/page/first-responder conditions.
- Tests: full `swift test` passed with 224 VoiceCore tests / 31 suites and 50 BugVoiceMac tests / 11 suites (274 total).
- Self-review: ordinary `begin` still reads start focus once after readiness checks and uses the original route-at-start decision. Mic captures bind to selected NoteID, cached selection, and current revision before recording.
- Skipped / UNVERIFIED: no live mic-button recording or focus loss was manually exercised; device checks remain pending.

### Review item 2 — Undo-safe editor insertion and reload

- Test-first: added a no-window standalone NSTextView regression covering typed text, dictated text, two undos, an external reload, and another undo. It passed before the fix because the old snapshot path did not reproduce the real visible editor's native undo sequence; after the fix it exercises the range-based NSTextView undo path and verifies text and buffer contents at each boundary. The off-screen test now explicitly detaches the editor before insertion and reattaches it before undo.
- Implemented attached-editor insertion with `breakUndoCoalescing()`, `shouldChangeText(in:replacementString:)`, textStorage replacement, `didChangeText()`, and a grouped named undo action. A detached note keeps snapshot undo. External reload and explicit Reload clear that note's undo actions before wholesale body replacement. Snapshot restoration updates a reopened editor with undo registration disabled.
- Tests: full `swift test` passed with 224 VoiceCore tests / 31 suites and 51 BugVoiceMac tests / 11 suites (275 total).
- Self-review: SwiftUI's `updateNSView` reuses the controller-attached body; normal dictation edits no longer assign `editor.string`. Full-string replacement remains only on attach/snapshot restore/external reload, with undo registration suppressed or cleared first.
- Skipped / UNVERIFIED: no real NSWindow was created per the regression requirement; visible window focus/caret behavior remains on the Notes device checklist.

### Review item 3 — Store-owned file versions across overlapping operations

- Test-first: added overlapping shared-baseline saves and stale-baseline refresh tests. The refresh test failed because a clean refresh treated the Store's just-written bytes as external. Added a rename-after-save test; temporarily restoring the prior rename guard made it fail with `.externalChange`, confirming the rename regression.
- Implemented `lastWrittenVersions` in NotesStore. Create, save, and rename record their resulting fingerprint; delete clears it. Save, rename, and external refresh now recognize the exact current Store-owned fingerprint even when a caller still holds an earlier expected version. A later file with a different fingerprint remains an external change.
- Tests: full `swift test` passed with 224 VoiceCore tests / 31 suites and 54 BugVoiceMac tests / 11 suites (278 total), including concurrent saves, save plus stale-baseline refresh, and rename after Store save.
- Self-review: ownership is based on the complete mtime/size/content-hash version, not a time window. The actor serializes version-map updates with its filesystem writes.
- Skipped / UNVERIFIED: no filesystem fault-injection or multi-process stress run was added; the focused actor tests cover overlapping API calls and stale expected versions.

### Review item 4 — Recover dictated text when an unloaded-note save fails

- Test-first: added a VoiceCore pipeline test for failed Notes insertion and a controller test that makes the Notes directory read-only so NotesStore's durable replacement fails. The controller test initially failed to compile because insertion still returned `Bool` and had no recovery state.
- Implemented distinct `.failed` insertion and `.noteSaveFailed` pipeline outcomes. The unloaded-note path treats only `.saved` as success and only `.deleted` as deletion; store errors, conflicts, stale writes, and other non-save outcomes preserve the dictation as a Notes insertion recovery. Notes shows each saved recovery text with an explicit Copy action. Notes save failures remain absent from history and the ordinary clipboard path is never invoked.
- Tests: full `swift test` passed with 225 VoiceCore tests / 31 suites and 55 BugVoiceMac tests / 11 suites (280 total). The read-only Store failure test and Notes pipeline failure/privacy test pass.
- Self-review: ordinary insertion targets continue to return only `.pasted` or `.notConsumed`; the new failure outcome is used by Notes. Deleted captured notes still produce the existing deleted-note message.
- Skipped / UNVERIFIED: no device-level forced disk failure or live Copy interaction was run; the failure is simulated by removing write permission from a temporary Notes directory.
