# Folders and Tags — Design

Date: 2026-10-15. Roadmap item 9 ([roadmap](../../ROADMAP.md)), moved ahead of
item 8 (Scratchpad) so notes, meetings and uploads are organized once.
Mockup: [Folders and tags](../../design/proposal-folders.html).
Builds on [Notes](2026-10-14-notes-design.md), [Meetings](2026-10-14-meetings-design.md)
and [Upload](2026-10-15-upload-design.md).

## 1. Goal

Organize notes, meetings and uploaded recordings into folders such as IT team,
Project A, Finance / client and Personal, and label them with tags such as
`#decision` or `#acme`. The same folders and tags are shared by every page.
Uploads choose their folder before transcription. After a meeting summary, the
Meetings model suggests up to three existing tags; nothing is added without a click.

Success:

- Every note and meeting is in exactly one folder or in Unfiled.
- Meetings and Notes lists filter by folder and by tags; search also matches tags.
- A file uploaded with "Save to Finance / client" appears in that folder.
- Renaming or deleting a folder never moves, rewrites or deletes a note or meeting file.
- Files stay readable by any app; Finder shows the same `Notes/` and `Meetings/`
  layout as today.

### Decisions recorded from maintainer review

| Question | Decision |
|---|---|
| Structure | One level of folders, plus tags. No nested folders. |
| Where to browse | A folder menu and tag filter inside each page (Meetings, Notes). No sidebar Folders section. |
| Adding tags | Typed with autocomplete; AI suggests up to 3 existing tags after a meeting summary; one click adds. |
| On disk | Folders are labels inside BugVoice. Files never move. |
| Scratchpad / floating window | Built later on top of this (item 8); the Notes page is the home. |

### Out of scope

- Nested folders, folder colors, tag colors, tag rename or merge.
- Folders or tags on dictation history.
- A mixed "everything in this folder" view across pages.
- Ask AI filtering by folder (item 6 adds it).
- AI suggestions for notes (Scratchpad Transforms, item 8) or for folders.
- Any new dependency.

## 2. Concepts

| Concept | Meaning |
|---|---|
| Folder | `LibraryFolder { id: FolderID, name: String, createdAt: Date }` stored in `library.json` |
| FolderID | Lowercased UUID string; stable across renames |
| Unfiled | An item whose `folderID` is nil, or names a folder that no longer exists |
| Tag | A normalized string (see 3.3) stored on the item itself, without `#` |
| Tag catalog | All tags in use, derived from loaded notes and meetings, with use counts. Not stored. |
| Labels | `ItemLabels { folderID: FolderID?, tags: [String] }`, the pair every item carries |

## 3. Data

### 3.1 `library.json`

Path: `~/Library/Application Support/BugVoice/library.json`, written atomically.

```json
{
  "version": 1,
  "folders": [
    { "id": "6c1f…", "name": "Project A", "createdAt": "2026-10-15T12:00:00Z" }
  ],
  "lastUploadFolderID": "6c1f…"
}
```

- Folder names are trimmed, 1–40 characters, unique ignoring case and diacritics.
  "Unfiled" and "All" (any case) are reserved. Errors: "A folder with this name
  already exists.", "Enter a folder name.", "This name is reserved."
- Folders list in name order (case- and diacritic-insensitive).
- Delete removes the folder from `library.json` only. Items keeping its id show as
  Unfiled because the id is unknown; a new folder always gets a new id, so a deleted
  folder's items never reattach. No note or meeting file is rewritten.
- `lastUploadFolderID` is the Upload page's default; a deleted id falls back to Unfiled.
- Missing file: start empty. Unreadable or undecodable file: rename it to
  `library.corrupt-<yyyyMMdd-HHmmss>.json`, start empty, and show
  "Folders file was damaged and has been reset. The old file was kept as <name>."
  Items keep their ids and show as Unfiled.
- An unknown higher `version`: open read-only, show "Folders were saved by a newer
  BugVoice. Folder changes are turned off.", and disable folder create/rename/delete.

### 3.2 Item storage

**Meetings.** `MeetingManifest` gains optional fields, decoded with defaults so
older `meeting.json` files load unchanged; `schemaVersion` stays 1:

- `folderID: FolderID?` (default nil)
- `tags: [String]` (default `[]`)
- `suggestedTags: [String]` (default `[]`)

Label writes follow the rename routing exactly: the active recording session, then
the active upload session, then `MeetingStore.save`. A meeting being recorded or
transcribed can be filed and tagged.

**Notes.** A note keeps its Markdown body and `# Title` heading. Labels go in
YAML-style front matter at the top of the same file, which survives note renames
(the note id is derived from the filename and changes on rename) and edits in
other apps:

```markdown
---
folder: 6c1f2a9e-0d4b-4f3e-9a51-2b7c8d0e1f23
tags: [decision, sprint]
---
# Sprint ideas

Body text…
```

Rules for `NotesMarkdownDocument`:

- Parse: if the file starts with `---` followed by a newline, read lines until the
  next line that is exactly `---`. Recognize `folder:` (one value) and `tags:`
  (inline list `[a, b]`, values optionally quoted). Keep every other line verbatim,
  in order, as `extraFrontMatter`. Then parse the `# Title` heading and body as today.
- No closing `---`: the file has no front matter; parse it as today (the `---` line
  is part of the body).
- Serialize: write front matter only when `folder`, `tags` or `extraFrontMatter` is
  non-empty, in the order `folder`, `tags`, extra lines; then `# Title`, a blank line
  and the body. A note with no labels serializes byte-for-byte as today.
- The editor never shows front matter; the body excludes it. Notes search excludes it.
- Line endings: accept CRLF inside front matter; write LF.
- Malformed `tags:` value: treat as no tags and keep the line in `extraFrontMatter`.
- `NoteDocument` and `NotesListItem` gain `folderID: FolderID?`, `tags: [String]` and
  `extraFrontMatter: [String]` (document only). Labels change the file through
  `NotesStore` with the same version and conflict checks as a body save.

### 3.3 Tag names

`TagName.normalize(_:) -> String?`:

1. Trim whitespace; drop leading `#` characters.
2. Lowercase with the POSIX locale; keep diacritics (`#họp` stays `họp`).
3. Replace runs of whitespace with one `-`.
4. Keep letters and digits of any script, `-`, `_` and `/`; drop other characters.
5. Trim `-`, `_` and `/` from both ends. Empty or longer than 32 characters → nil.

An item holds at most 10 tags, unique, in the order added. Display adds `#`.
The catalog sorts by use count (descending), then name.

## 4. UI

Copy follows the mockup. Plain English, no emoji.

### 4.1 List header (Meetings and Notes)

- Folder menu button showing the current filter (All meetings / All notes, Unfiled,
  or a folder name). Menu: All (count), Unfiled (count), divider, each folder
  (count), divider, New folder…, Manage folders…. Counts are for that page only.
- Tags button: menu of catalog tags for that page with counts; choosing one adds a
  removable `#tag ✕` chip under the buttons. Several chips mean the item must have
  all of them.
- Search also matches tags: the query `acme` or `#acme` matches an item tagged `acme`.
- The folder filter of each page is remembered in `settings.json`
  (`library.meetingsFolderFilter`, `library.notesFolderFilter`: `"all"`, `"unfiled"`
  or a folder id). Tag chips reset on launch.
- Each row shows its tags as small chips (at most 3, then `+N`). When the filter is
  All, the row also shows its folder name with a folder icon.

### 4.2 Detail labels box

Under the meeting title/meta line and under the note title, a bordered box:

- **Folder:** a picker button with every folder plus Unfiled and New folder….
- **Tags:** chips with `✕`, then `+ Add tag`. Typing opens an autocomplete menu of
  catalog tags containing the text (prefix matches first), then `Create tag "#x"`
  when the normalized text is new. Return picks the highlighted entry; Escape cancels.
  An invalid name shows "Tags use letters, numbers, - _ and /, up to 32 characters."
  The 11th tag shows "A meeting can have up to 10 tags." (or "A note …").
- **Suggested** (meetings only, when `suggestedTags` is non-empty): dashed purple
  chips `+ #todo`, a muted line "From the summary · <model> · click to add", and a
  `✕` that clears all suggestions. Clicking a chip adds the tag and removes it from
  the suggestions.

### 4.3 Context menus

Meetings rows (existing Rename… and Delete…) and Notes rows (new menu) get:
Rename…, Move to folder › (Unfiled, folders with a check on the current one,
New folder…), Tags… (selects the item and focuses its tag field), Delete….
Delete stays hidden while a meeting records, as today.

### 4.4 New items

- New note: goes into the Notes page's current folder filter; Unfiled when the
  filter is All or Unfiled.
- New meeting recording (record button, menu bar or hotkey): goes into the Meetings
  page's current folder filter, same rule.
- Notes dictated into an existing note keep that note's labels.

### 4.5 Upload

- Each file card gets "Save to" (folder picker, default `lastUploadFolderID`, hint
  "Last used") and "Tags" (same tag field as 4.2).
- With two or more cards, an "Apply to all" button under the first card copies its
  folder and tags to every card.
- Transcribe stores the chosen folder in `lastUploadFolderID`. The job carries the
  labels; the meeting manifest is created with them.
- A folder deleted while a job is queued: the meeting is created with that id and
  shows as Unfiled (3.1 rule).

### 4.6 Manage folders

A sheet titled "Folders": one row per folder with its counts ("4 meetings · 6 notes"),
Rename (inline edit, Save) and Delete. Delete asks "Delete folder "<name>"? Its
meetings and notes move to Unfiled. No files are deleted." with Delete / Cancel.
"+ New folder" adds an inline row. Done closes. The footnote reads: "Deleting a
folder moves its meetings and notes to Unfiled. Nothing is deleted, and files on
disk never move."

## 5. AI tag suggestions

- Trigger: a Summary is generated and saved for a meeting (any engine), and the tag
  catalog is not empty. Action items do not trigger it.
- Request to the Meetings model, after the summary is saved:
  - System: "You label meeting notes. From the allowed tags, pick at most 3 that
    fit the summary. Answer with tag names only, one per line, or the word none.
    Never invent a tag."
  - User: "Allowed tags:\n<one per line>\n\nSummary:\n<summary>"
  - Max tokens 64; allowed list capped at the 200 most-used tags.
- Parse with `TagSuggestionParser`: split lines, strip bullets, numbering and `#`,
  normalize, keep only catalog tags not already on the meeting, unique, first 3.
- Store as `suggestedTags`. Any failure, timeout or empty result leaves the
  suggestions unchanged and shows nothing. No retry.
- Generating a new summary replaces `suggestedTags`. Adding a tag manually removes
  it from `suggestedTags`.
- Privacy: the request goes only to the configured Meetings provider, exactly as
  the summary did.

## 6. Architecture

| Unit | Module | Responsibility |
|---|---|---|
| `FolderID`, `LibraryFolder`, `LibraryFile` | VoiceCore | Codable model of `library.json`, version handling |
| `LibraryFolders` | VoiceCore | Pure operations: create, rename, delete, validate names, sort |
| `LibraryStore` | VoiceCore (actor) | Load/save `library.json`, corrupt-file backup, newer-version read-only |
| `TagName` | VoiceCore | Normalize and validate tag names |
| `ItemLabels` | VoiceCore | Folder id + tags with add/remove rules (limit 10, dedupe) |
| `LibraryFilter`, `LibraryProjection` | VoiceCore | Folder/tag/search filtering, counts, tag catalog for meetings and notes |
| `NotesMarkdownDocument` | VoiceCore | Front matter parse/serialize (3.2) |
| `TagSuggestionParser`, `TagSuggestionPrompt` | VoiceCore | Prompt text and answer parsing (5) |
| `MeetingManifest` fields | VoiceCore | `folderID`, `tags`, `suggestedTags` with tolerant decoding |
| `MeetingSession.setLabels` | VoiceCore | Label writes for an active session |
| `NotesStore.setLabels` | BugVoiceMac | Label writes with version/conflict checks |
| `UploadJob` fields | VoiceCore | `folderID`, `tags` carried into manifest creation |
| `AppModel` | App | `library`, filters, `setMeetingLabels`, `setNoteLabels`, routing, suggestions |
| `LibraryFilterBar`, `LabelsBox`, `TagField`, `FolderPicker`, `ManageFoldersSheet` | App UI | Shared views used by Meetings, Notes and Upload |

`VoiceCore` imports Foundation only. No new dependency.

## 7. Errors

| Case | Behavior |
|---|---|
| `library.json` damaged | Backup + reset + message (3.1) |
| `library.json` newer version | Read-only folders + message (3.1) |
| Folder name invalid/duplicate/reserved | Inline message in the sheet or picker; nothing saved |
| Note changed on disk before a label write | Same conflict handling as a body save; labels not lost from the editor state |
| Meeting manifest save fails | `saveError` "Could not update meeting: <reason>" |
| Suggestion request fails | Silent; nothing shown |

## 8. Testing

TDD in VoiceCore, failing test first:

- `TagName`: `#Decision` → `decision`; `  Họp  team ` → `họp-team`; `a/b` kept;
  emoji dropped; 33 characters → nil; `###` → nil.
- `ItemLabels`: dedupe, order kept, 11th tag refused.
- `LibraryFolders`: create/rename/delete; duplicate ignoring case and diacritics;
  reserved names; 41 characters refused; name sort.
- `LibraryStore`: missing file; round trip; corrupt file backed up and reset;
  newer version read-only.
- `NotesMarkdownDocument`: no front matter unchanged byte-for-byte; folder + tags
  round trip; unknown keys preserved in order; CRLF accepted; unclosed `---` treated
  as body; malformed `tags:` kept as extra; labels removed → front matter removed.
- `MeetingManifest`: old JSON decodes with nil folder and empty tags; new fields
  round trip.
- `LibraryProjection`: All / Unfiled / folder; dangling folder id counts as Unfiled;
  tag chips AND; search matches `acme` and `#acme`; counts per folder; catalog order.
- `TagSuggestionParser`: bullets/numbers/`#` stripped; unknown tags dropped; tags
  already on the item dropped; `none` → empty; max 3.
- `MeetingSession.setLabels` persists during recording.
- `UploadJob` labels reach the created manifest.
- BugVoiceMac: `NotesStore.setLabels` writes front matter, keeps body, survives
  rename; external edit conflict path.

Manual checklist rows (appended after the last row in
`docs/testing/manual-checklist.md`): create/rename/delete folder; filter Meetings
and Notes; move by right-click; tags with autocomplete; upload with Save to and
Apply to all; suggestion chips after a summary; delete a folder and see items in
Unfiled; open a labelled note in another editor and confirm the front matter.
