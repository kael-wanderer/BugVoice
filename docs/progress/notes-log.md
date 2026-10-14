# Notes implementation log

## Summary

Implementation is beginning on feat/notes after spec and plan approval. No Notes code has been implemented yet.

- **Documentation commit:** 035a116 — docs: notes design and implementation plan
- **Baseline tests:** swift test passed with 192 VoiceCore tests in 26 suites and 27 BugVoiceMac tests in 7 suites (219 total).
- **Build / launch / manual checks:** not run for Notes.
- **UNVERIFIED:** all Notes UI, editor insertion/undo, external-edit, autosave, quit, shortcut registration, storage size, export, and deletion behavior until implemented and manually checked.

## Approved decisions and costs

- Loaded-note in-memory buffers owned by NotesController are authoritative. NotesStore directly applies an insertion only when a note is not loaded. Successful store writes return the new file version to NotesController so its own writes cannot become external-change warnings.
- One NSUndoManager per loaded note is retained by NotesController for the app run, including while the editor is off screen. Undo history does not survive relaunch.
- The external-change fingerprint checks modification time, size, and a stable 64-bit FNV-1a hash on selection, app activation, and before every save. Hashing reads the whole note file; this linear I/O cost is accepted for expected note sizes.
- If registering ⌃⌥N fails, show “New note shortcut unavailable” in the menu; the menu action remains usable.
- Note files without a leading nonempty H1 derive the title from the filename stem, with hyphens changed to spaces. The entire file remains body content until edited.
- Notes routing is selected only at recording start. Later focus changes do not cancel or reroute the run. An unchanged note uses the captured selection; a changed note appends. A deleted note discards the result. Notes never write dictation history, last.wav, menu last-result, or pasteboard.
- Body saves debounce 500 ms. A title rename commits only on Return or title-field focus out.
- No Notes behavior has been built or manually verified yet.

## Implementation commits and verification

| Commit | Task | Tests | Notes |
|---|---|---|---|
| 035a116 | Approved spec, plan, and scratch ignore | Baseline: 192 VoiceCore + 27 BugVoiceMac passed | Documentation only |

## Decisions made during implementation

None yet.

## Skipped or NOT BUILT

None yet.

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
