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
