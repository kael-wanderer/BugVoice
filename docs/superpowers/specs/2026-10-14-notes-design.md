# BugVoice — Notes design

Date: 2026-10-14
Status: approved with maintainer amendments
Scope: sub-project 3 of 3 — Markdown notes and dictation into the in-app editor. Dictation core and Meetings are already implemented. No timeline or note audio recording.

## 1. Purpose

Notes is a private, local Markdown editor inside BugVoice. A user can keep short or long notes and dictate at the text caret without switching to another app. Notes reuse speech-to-text and cleanup providers, but note audio and note dictation results are not saved to dictation history, last.wav, or the menu's last-result preview.

### Success criteria

- Create, search, edit, export, copy, and delete Markdown notes in the Notes page.
- Notes are UTF-8 files at ~/Library/Application Support/BugVoice/Notes/<slug>.md.
- Right Option dictation and the Notes mic button write to the active selection/caret through an in-app InsertionTarget; no pasteboard access or synthetic ⌘V occurs.
- One dictation insertion is one undo step.
- After a Notes run starts, it remains bound to the captured note regardless of app/editor focus; it never sends dictated text to another app.
- Note reads, writes, directory scans, synchronization, and size measurement stay off MainActor.
- Every write to a note file is serialized through one NotesStore actor and is durably replaced.

## 2. Scope

### In scope

- A Notes page with searchable note list and a Markdown editor.
- New note from the Notes page or menu (⌃⌥N).
- Hold Right Option while the Notes editor is focused, or press the editor's mic button, to record. The mic button toggles recording; the hotkey keeps the existing hold / hands-free gesture behavior.
- A live Listening bar with level meter, elapsed time, and stop control at the bottom of the editor.
- Autosave, external file change handling, Markdown export, Copy as Markdown, confirmed deletion, and Notes size in Settings → Storage.
- Notes style is always document; it uses the configured cleanup setting/provider for that style and existing vocabulary replacements.

### Out of scope

- A dictation timeline or note-specific history.
- Saving or replaying note dictation audio; Retry last and Paste last for note dictations.
- Rich text storage, cloud sync, attachments, collaboration, folders, tags, or a model-generated note summary.
- Notes retention or automatic deletion.

## 3. Architecture and data flow

### 3.1 Note files and ownership

Use AppPaths.notes, already reserved at ~/Library/Application Support/BugVoice/Notes/, and create it from AppPaths.ensureExists().

Each note is one UTF-8 Markdown file named <slug>.md. BugVoice-written files use a first-line Markdown H1 containing the title (# <title>), a blank line, then the editable Markdown body. The H1 is note metadata for the list/editor and is included in Markdown export and Copy as Markdown. A new note starts with a title and an empty body. Editing the title changes the H1 and filename together when title editing ends. Editing the body never changes the title. For an empty file or a file whose first line does not begin with # followed by a space and at least one title character, derive the title from the filename stem (replace hyphens with spaces, preserving the stem case) and treat the entire file as body text. Do not rewrite that file merely because it was opened or selected. The first user edit saves it in the BugVoice-written format.

NotesStore is the sole owner of note directory reads and note file writes. It is an actor used by NotesController. No view, text view, or other service writes note files directly. The actor performs directory scans, reads, writes, external-change checks, and deletion off MainActor. While a note is loaded in NotesController, its in-memory buffer is authoritative; edits, dictation insertion, and undo mutate that buffer, and the normal save path persists it. NotesStore applies a dictation insertion directly only when the note is not loaded in NotesController.

A save writes a unique temporary file in the Notes directory, writes all UTF-8 bytes, synchronizes the temporary file, atomically renames it over the target, and synchronizes the Notes directory. The actor serializes saves and renames so a delayed autosave cannot overwrite a newer title or body. Each successful NotesStore write returns the new file version, which NotesController records before any later external-change check; an app-owned write must never be reported as Changed outside BugVoice. A failed save leaves the editor dirty and reports Could not save note; it does not report the note as saved. Computing the content hash before every save reads the entire note file; this linear read is accepted for expected note sizes.

### 3.2 Slugs, collisions, rename, and external edits

Create a slug from the title by applying Unicode canonical decomposition, explicitly mapping đ and Đ to d before folding case and diacritics with the POSIX locale, replacing every run outside ASCII a-z and 0-9 with one hyphen, and trimming hyphens. Empty output becomes note. Thus Đường đi becomes duong-di. This keeps Vietnamese titles readable in the H1 while producing portable filenames.

Slug collisions are resolved case-insensitively against existing .md filenames. The first available name is <slug>.md, then <slug>-2.md, <slug>-3.md, and so on. The collision check and final rename happen in one NotesStore actor operation. Renaming a note keeps its stable in-memory note ID, updates its H1, and chooses the first available slug; if its current path already has that slug, no suffix is added. Deleting a note asks for confirmation, then moves the .md file to the macOS Trash.

There is no polling. On note selection, app activation, and before every save, the store checks each relevant file version using modification time, byte size, and a stable 64-bit FNV-1a hash of the bytes. If a file changes outside BugVoice while its editor is clean, reload its title/body and refresh the list. If a file changes while its editor is dirty, keep the in-memory edits and show Changed outside BugVoice with Reload and Keep mine actions. Reload discards local unsaved edits after an explicit user action. Keep mine asks for confirmation that the external version will be replaced, then writes the current in-memory note through the same store actor. A deleted externally edited note is treated as a conflict; Keep mine recreates it using the normal collision rule. Never silently discard dirty local text or silently overwrite an external edit.

### 3.3 Dictation routing

The Notes dictation route is selected only at hotkey-down or mic-button start when all these conditions are true:

1. BugVoice is the active/frontmost application.
2. The active main window is on the Notes page.
3. The Notes editor for the selected note is first responder and has a valid insertion point/selection.
4. No note save/conflict state blocks editing.

The Notes editor is an AppKit text view hosted by the Notes page so the app can identify the exact editor instance, selected range, note ID, and undo manager. Clicking the mic button does not make the button first responder; it preserves the editor's selection. At recording start, the controller captures the note ID and editor identity. Notes style is forced to document; style routing for other apps is unchanged.

When a Notes recording starts, show the Listening bar in the editor and bind the run to the captured note ID, editor, and caret/selection. Later loss of app or editor focus does not cancel recording or discard its result. Never fall through to the ordinary paste target or clipboard.

At insertion, if the captured note still exists, apply the text to its in-memory note buffer and save through NotesStore even when its editor is no longer on screen. If the note content revision is unchanged since recording began, insert at the captured caret/selection, replacing selected text. If its content changed since recording began, append at the end of the note body. Editor visibility does not change this position rule: when the editor is off screen, apply the same edit to the note buffer and NotesStore. NotesController owns one NSUndoManager per loaded note for the current app run. The visible text view obtains that manager from undoManager(for:). Group the complete insertion as exactly one undo step on that manager whether the editor is visible or off screen; reopening the note in the same app run retains the manager. Undo history does not survive app relaunch. If the captured note was deleted before insertion, discard the result and show Note deleted — dictation was not added. Do not insert into a different selected note. Nothing from a Notes run is copied to the pasteboard.

In-editor dictation results are not written to history.jsonl, do not replace the menu's last-result preview, do not create or replace last.wav, and do not expose text to Retry last or Paste last. Those commands continue to refer only to the latest ordinary dictation. If the previous ordinary result is pasted while a note is focused, it follows the existing generic Paste last behavior and is not treated as a Notes dictation.

The ordinary dictation path remains byte-for-byte equivalent in output, cleanup, history, secure-field checks, pasteboard handling, retry audio, and HUD behavior. The app chooses an in-editor target only for the Notes route above. A failure to select the Notes route at start leaves the ordinary dictation route unchanged.

### 3.4 Recording and providers

The global Right Option gesture starts Notes dictation when the Notes route conditions are met; otherwise it follows current ordinary dictation behavior. The Notes mic button starts/stops a recording using the same AudioRecorder, readiness checks, time cap, and transcription pipeline. The mic button is disabled while another dictation is running. Stop finishes transcription and applies the result to the captured note under the insertion rules in §3.3, regardless of current focus.

The recording clip is held only in memory for this run. Never write it to last.wav or another file. Reuse the existing shared transcriber and TextModel; Notes does not change provider construction or shared scheduling. Notes transcription has document style and normal document cleanup/replacement rules. No timeline or note-dictation record is created.

### 3.5 Search and Markdown operations

Search is a VoiceCore projection over note title and body. Match a literal query as a case- and diacritic-insensitive substring; an empty or whitespace-only query returns every note. Search does not interpret Markdown syntax or operators. Sort the unfiltered list and matches by modification time, newest first, with case-insensitive title as a deterministic tie-breaker.

Copy as Markdown places the selected note's complete saved-format Markdown (# title, blank line, body) on the clipboard. Export presents a save panel, writes the same UTF-8 Markdown to the chosen .md URL, and asks before replacing an existing destination. Copy/export do not modify the saved note. Export formatting is a pure VoiceCore operation; file dialogs and destination I/O are in the app layer.

## 4. Autosave and interruption behavior

After each body edit, schedule a save 500 ms after the most recent edit. A later body edit resets the debounce. Editing the title does not rename the file on each debounce: commit the title and rename only when title editing ends by Return or focus leaving the title field. A committed title change updates the H1 and saves the rename through NotesStore. The body debounce remains 500 ms. The debounce policy is represented in VoiceCore and covered by deterministic clock-driven tests. When a note is selected away or the Notes page closes, request an immediate save; completion is awaited before switching/closing. On quit, the existing applicationShouldTerminate handler combines the active Meetings decision with an immediate Notes save in one handler. A failed save keeps the note dirty and exposes Retry save. Do not block MainActor on file I/O or fsync.

The store serializes immediate, title-commit, and debounced saves by note ID and monotonically increasing in-memory revision. Only the latest revision may become the file's visible contents. If the app crashes before a debounced save begins, up to 500 ms of body edits may be lost; show a Saving indicator while dirty and Saved only after durable rename and directory synchronization complete.

## 5. UI

### 5.1 Notes page

Add Notes to the main-window sidebar and Page; the page has a search field and New note action above a two-column list/editor layout.

The list shows title, last-edited time, and word count, newest first. Selecting a row opens that note. The editor header shows editable title, Markdown · saved to Notes/<slug>.md · style: document, and Export / Copy as Markdown actions. The body is a plain Markdown editor: Markdown source is saved without rich-text conversion. The title is displayed separately from the body but is stored in the file's H1 as specified in §3.1. The bottom Listening bar shows mic level, elapsed time, a stop action, and that text will be added to this note. When idle, the mic button starts dictation. Show Saving, Saved, save errors, external-change conflicts, and deleted-note outcomes in plain English.

New note creates a note titled Untitled with slug untitled. If occupied, use the collision rule (untitled-2, etc.). The editor selects its title and places focus in the body after creation. While the title field is being edited, body autosaves continue to use the last committed title and path; Return or focus leaving the title field commits the new title and performs the rename. The menu item and global shortcut ⌃⌥N open/activate the Notes page, create the note, and focus its body. If system registration of ⌃⌥N fails, the menu shows New note shortcut unavailable; the menu New note action still works. If a dirty note needs saving before switching, wait for the serialized immediate save before changing selection.

### 5.2 Delete, copy, and export

Delete is available for the selected note and requires confirmation that names it. Confirm moves only that file to the macOS Trash. Cancel preserves it. Export uses an NSSavePanel with Markdown as the default format and extension; replacing an existing file requires confirmation. Copy as Markdown copies the full exported content and does not change selection or saved state.

### 5.3 Settings and storage

Add Notes to Settings → Storage. Show total allocated size for the Notes/ directory, including all .md files, and a Show in Finder action. Display note count as detail. Measure using the existing detached directory-size approach; never scan or size the Notes directory on MainActor.

## 6. Error handling and interruption safety

| Condition | Behavior |
|---|---|
| Notes directory cannot be created or read | Keep other BugVoice pages usable; show a Notes error with Retry |
| Durable save or directory sync fails | Keep text dirty, show Could not save note, and allow Retry; don't report Saved |
| External edit while clean | Reload the file and refresh title/body/list metadata |
| External edit while dirty | Keep local text and show Reload / Keep mine resolution; no silent overwrite |
| Note file removed externally | Mark missing; dirty content requires the same explicit conflict resolution |
| BugVoice/editor loses focus while recording | Continue the captured Notes run; apply its result to the captured note under §3.3, without clipboard or paste fallback |
| Captured note is deleted before insertion | Discard result; show Note deleted — dictation was not added |
| Secure text field or ordinary app route | Notes target is never selected; keep the existing secure-field and paste behavior |
| User deletes a note | Confirm, then move only the selected file to Trash |

## 7. Testing

VoiceCore unit tests cover title-to-slug Unicode/case/diacritic normalization including the explicit Đường đi → duong-di mapping, punctuation/empty-title fallback, case-insensitive collision suffixes, stable rename allocation, parsing an H1 file, filename-derived title and whole-file body for a file without a leading # H1 (including empty files), and no rewrite until edit. Test debounce reset and 500 ms body-save firing with an injected clock, title rename only on edit end, revision ordering, file-version comparison using mtime/size/content hash, checks on selection/activation/before-save without polling, literal case/diacritic-insensitive search, empty-query behavior, deterministic modified-time ordering, H1/body Markdown serialization and export, and the pure insertion-route policy. The routing policy tests require active BugVoice, Notes page, selected note, first-responder editor identity, valid selection, and no blocking save/conflict state; after the route starts, focus changes do not change the captured note target.

App integration tests cover direct insertion at the captured selection, captured-selection insertion while off screen when unchanged, append-at-end after note changes, one per-note undo manager across editor dismissal/reopen, focus loss mid-recording still inserting into the captured note, deleted-note discard, no pasteboard/⌘V calls or pasteboard writes, no history/last-result/last.wav writes for Notes, an insertion during a pending 500 ms body save preserving both edits, NotesStore writes updating the controller file version without a false external-change warning, external edit conflicts and resolution, visible ⌃⌥N registration failure, combined Notes/Meetings quit handling, and Notes size listing. Undo history is not expected to survive relaunch. Add a regression test proving an ordinary dictation that starts outside BugVoice still reaches the same paste target and retains the same bytes, cleanup, history, and secure-field outcome.

Use fakes for the clock and note-store filesystem boundary in VoiceCore tests. App-layer tests must verify all note file access and fsync execute off MainActor and all note writes route through the single NotesStore actor. No external package is added.

Manual checklist covers note creation/list/search, English/Vietnamese Markdown typing and dictation, mic button and Right Option, captured-caret insertion and append-after-edit, focus loss during recording, one-step undo, autosave/relaunch persistence, external edits while clean and dirty, conflict resolution, title rename on Return/focus out and collisions, non-H1 external files, Copy as Markdown, export/overwrite confirmation, confirmed delete to Trash, Notes storage size, combined Meetings/Notes quit behavior, and ordinary dictation in Terminal/browser/secure fields after Notes is enabled.

## 8. Implementation seams

- Keep slug allocation, note-file parsing, route policy, debounce scheduling, file-version comparison, search, and Markdown serialization/export as deterministic Foundation-only VoiceCore units with tests.
- Add a Notes-specific InsertionTarget in the app layer that holds the captured note ID, insertion point/selection, and optional editor identity; it applies the result to the captured note buffer even after focus changes, using captured selection only if the note is unchanged, otherwise appending. It mutates a visible AppKit text view only on MainActor and writes through NotesStore.
- Keep DictationPipeline behavior shared for transcription and document cleanup, but add an explicit Notes execution context/result path so note dictations can suppress ordinary history/last-result behavior and dispatch to the captured note target without invoking the paste target. Do not globally alter the ordinary insertion path.
- DictationController checks route only at start, avoids last.wav on a Notes run, retains the captured note target through transcription regardless of focus, and does not call AppModel.record for Notes results. Any shared controller change gets the outside-BugVoice byte-for-byte regression test.
- NotesStore is the only writer and performs filesystem work away from MainActor. Its durable save uses same-directory temp, file synchronization, atomic rename, and directory synchronization.
- AppPaths.ensureExists() creates Notes/; the Notes size row uses detached directory measurement.
- Add NotesPage and editor view; keep edit buffer and focus identity in the page/controller while the actor owns disk state. Use an AppKit-backed text view to preserve selected ranges and obtain the loaded note's NSUndoManager from NotesController; keep that manager for the app run when the editor is off screen.
- Add menu New note and ⌃⌥N registration without changing existing hotkey behavior. Surface registration failure in the menu as New note shortcut unavailable.
- Use the already configured ProviderFactory and shared TranscriptionRouter; do not rebuild providers for note changes.
- No new dependency. VoiceCore imports Foundation only.

## 9. Decisions recorded from maintainer review

1. Each note is a Markdown file. BugVoice-written files start with # <title>, a blank line, and body. A file with no leading nonempty # H1 uses its filename stem, with hyphens replaced by spaces, as title and its entire contents as body until the first edit.
2. Slugs use Unicode decomposition and POSIX folding, with explicit Đ/đ → d mapping, then lowercase ASCII normalization. Empty slug becomes note; collisions use -2, -3, case-insensitively. Rename occurs only when title editing ends; it updates the H1 and path.
3. External edits are checked on selection, app activation, and before each save by modification time, size, and content hash. There is no polling. Clean buffers reload; dirty buffers require explicit Reload or confirmed Keep mine. Confirmed delete moves the note to Trash.
4. Select the Notes route only at start when BugVoice is frontmost, Notes is selected, and that note editor is first responder with a valid selection and no blocking save/conflict. Once started, bind the run to that note. Focus loss does not cancel it. Insert at the captured selection if unchanged, otherwise append; update the note buffer and NotesStore even when the editor is off screen. If the note was deleted, discard with a plain-English message. Never fall through to paste or clipboard. No history, last.wav, Retry last, or Paste last.
5. Debounce body saves by 500 ms. Commit title changes and rename on Return or title-field focus out. Use one NotesStore actor off MainActor for all note I/O and durable temp-file/sync/rename/directory-sync writes. The existing applicationShouldTerminate handler combines Notes immediate-save and the Meetings quit decision.
6. NotesController owns the authoritative in-memory buffer for every loaded note. Loaded-note insertions mutate that buffer and use the normal save path; NotesStore applies directly only for an unloaded note. Store writes return and refresh the controller's file-version baseline. One NotesController-owned NSUndoManager is retained per loaded note for the app run, including while off screen; undo history resets at relaunch. The 64-bit hash check reads the whole note before each save; this cost is accepted. If ⌃⌥N registration fails, show New note shortcut unavailable in the menu.
