# Folders and tags management execution log

Branch: `feat/library-management`, merged to `main` 2026-10-18 (d54202e), pushed 2026-10-19.
Spec: `docs/superpowers/specs/2026-10-18-library-management-design.md`. Mockup: `docs/design/proposal-library.html`.
Plan: `docs/superpowers/plans/2026-10-18-library-management.md`. Tasks 1–4 built by Codex (Sol), reviewed and checked by Claude.

## Tasks

### Task 1 — Tag list, colours and tag edits in VoiceCore
`aba6fde` — feat(core): `library.json` gains an optional `tags` list (name, optional colour, seven colours); `TagEdit` rename, merge and delete on `ItemLabels`; `tagRows` builds the Tags tab rows (union and counts).

### Task 2 — AppModel tag actions
`27d011d` — feat(app): `createTag`, `setTagColor`, `renameTag`, `mergeTag`, `deleteTag`. Items save through `NotesController.setLabels` and `setMeetingLabels`; `library.json` saves last, only when every item saved. Page tag filters follow a rename and drop a deleted tag.

### Task 3 — Manage library sheet and entry points
`b17e50b` — feat(app): one sheet with Folders and Tags tabs replaces `ManageFoldersSheet`. Opens from the folder and Tags filter menus, New note ⌄, the editor's folder menu and tag suggestions, and a new Settings › General card.

### Task 4 — Filter row and card badges
`2c0b392` — feat(app): the Tags filter is one button with a count, with Clear tags and Manage tags…; Scratchpad cards show the folder and up to three tags with colour dots.

### Review and check fixes
- `54b5ea2` — The merge dialog counted meetings that only suggested the target tag. It now counts meetings that carry it.
- `455b2fa`:
  - The Tags button showed no count. A menu label draws only its icon and title, so the count is now an overlay.
  - The New tag field was not focused, so Return pressed Done and closed the sheet. The New tag and Rename fields now take focus.
  - The hollow colour dot took clicks only on its outline. Its outline was also hard to see in light themes.
  - Tags made with New tag were missing from the editor's tag suggestions.
  - Counts read "1 notes" and "1 folders" in the dialogs, the Unfiled footer and the Settings card.

## Manual checks

Run 2026-10-18 in the dev app on the second display. `settings.json`, `library.json` and `Notes/` were backed up first and restored afterwards (`cmp` and `diff -r` identical). Only `zz-` test tags and a "ZZ Folder" test folder were created, changed and deleted. One existing note was used for the tests and restored from the backup.

1. Entry points. Each one opens the sheet on its tab: the Scratchpad and Meetings Tags menus, New note ⌄ "Manage folders and tags…", Settings › General "Manage…", and the floating editor's folder menu and tag suggestions (over the floating window). Passed. The Scratchpad folder menu entry existed before this branch and was not clicked again.
2. Folders tab: create, rename and delete a test folder. Delete asks first. Counts and the Unfiled footer are right. Passed.
3. Tags tab: New tag shows "not used" and is saved to `library.json`. A blue colour shows in the editor chip, the card and the preview, and green saves in light theme. Passed. The meeting row dot was not checked: no meeting was tagged, to leave meeting files untouched.
4. Rename a test tag: the note's front matter, the editor chip and the colour follow. Passed with one note. Two notes and a meeting, and a page filter on the old name, were not run.
5. Rename onto an existing tag: the dialog shows counts. After Merge the note has one copy of the tag and the colour carries over. Passed.
6. Delete a test tag: the dialog shows counts, the tag leaves the note and `library.json`, and the body is unchanged. Passed.
7. Scratchpad page: two picked tags give a "2" badge on one line; Clear tags empties the filter. Passed (after `455b2fa`).
8. Cards show the folder and coloured tags; an Unfiled card with no tags has no badge line. Passed.
9. Dark at 100%, light at 100% and light at 160%: the filter row stays on one line and the sheet scales. Passed. The segmented control and menu items use system text and do not scale, as elsewhere in the app.
10. A `library.json` without `tags` loads with folders unchanged. Passed: the owner's file had no `tags` field. Also covered by `LibraryTagsTests`.

Review Focus 5: text typed in the floating editor, then a tag renamed and merged from the sheet right away. The typed text was still in the file. Passed.

`swift test`: 1,060 tests pass. `Scripts/check-tokens.sh`: exit 0.
