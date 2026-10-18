# Folders and tags management

Date: 2026-10-18. Status: approved by owner 2026-10-18.
Mockup: `docs/design/proposal-library.html`.
Follows: the note editor redesign (`2026-10-18-note-editor-design.md`, merged
69ad3f0), agreed then as "round 2".

## Why

Folders can be created, renamed and deleted today (`ManageFoldersSheet`), but
tags cannot be managed at all. A tag exists only while some note or meeting
carries it, so a typo such as `#followup` next to `#follow-up` can only be fixed
by opening every item. The owner wants:

- folders to scope what a list shows;
- tags for quick search and metadata across folders;
- one place to add, rename, recolour and delete tags, with a rename or delete
  applied to every note and meeting.

The Scratchpad page has a second problem. Picking tags in the filter adds chips
to the filter row, so it breaks onto two lines. The owner wants the row on one
line, and each card to show its folder and tags.

## Goals

1. **Manage library sheet.** One sheet, two tabs: Folders and Tags. It replaces
   `ManageFoldersSheet`.
2. **Folders tab.** Today's folder management, moved into the sheet: list with
   counts, New folder, Rename, Delete with confirmation. Folders stay one
   level.
3. **Tags tab.** Every tag, with counts. New tag, Rename, Colour, Delete.
   - Rename applies to every note and meeting.
   - Renaming onto a tag that already exists merges the two, after a
     confirmation.
   - Delete removes the tag from every note and meeting, after a confirmation.
4. **Tag colours.** Each tag can have one colour from a fixed palette, or none.
   The colour shows as a dot in tag chips across the app.
5. **One-line filter row.** On the Scratchpad and Meetings pages, picked tags
   show as a count on the Tags button instead of chips in the row.
6. **Card badges.** Scratchpad cards show the folder and tags under the date.
7. **Entry points.** The sheet opens from every place a folder or tag is
   picked (see the table).

## Non-goals

- Nested folders. The owner chose flat folders on 2026-10-18.
- Colours inside Markdown. Markdown has no colours. A note keeps its tags as
  plain names in front matter (`tags: [client, follow-up]`); the colour lives
  only in BugVoice.
- Changing how tag names are written. Names stay lowercase, without `#`,
  following `TagName.normalize`, up to 32 characters, and 10 per item.
- Moving files on disk. Folders stay labels; nothing moves.
- Tag colours in the MCP server or in Ask AI.
- Changes to the meeting list row beyond its tag chips gaining colour dots.

## Anti-goals

- Losing a tag on an item during a rename or merge, or leaving an item with two
  copies of the same tag.
- A rename that half applies: some items renamed, others not, with no message
  saying so.
- Rewriting a note's body. A rename or delete touches front matter `tags` only.
- Touching a meeting a live recording or upload owns, other than through its
  session (`setMeetingLabels` already routes this).

## Data

**`library.json`** gains a tag list next to the folder list:

```json
{ "version": 1,
  "folders": [ … ],
  "tags": [ { "name": "client", "color": "blue" }, { "name": "draft" } ] }
```

- `tags` holds tags created with New tag and tags given a colour. A tag used by
  an item but not listed here is still a tag. It has no colour.
- The Tags tab shows the union of this list and every tag on a note or meeting.
- `color` is one of `red`, `orange`, `yellow`, `green`, `teal`, `blue`,
  `purple`, or absent for none.
- An unknown colour name reads as none.
- `tags` is optional on read, so today's files load unchanged.
- `version` stays 1. A missing field defaults to empty, and no older build is
  in use on this Mac.
- Rename and delete update this list in the same save as the item changes.

**One tag namespace.** Tags are global, as today (`allTagCatalog`): `#client`
on a note and on a meeting is the same tag, with one colour, and a rename or
delete applies to both. Each page's Tags filter menu still lists only the tags
used on that page's items (`noteTagCatalog`, `meetingTagCatalog`). The Tags
tab lists all of them.

**Colours** are theme tokens, readable in light and dark. They go in the theme
layer with the other `.bv…` colours, not as literals in views.
`Scripts/check-tokens.sh` must pass.

## Behaviour

### Manage library sheet

- A macOS sheet over the window it was opened from, about 460 pt wide (scaled
  like other sheets), with a Folders | Tags segmented control at the top.
- It opens on the tab its entry point names.
- Done or Escape closes it.
- While `library.json` is read only (written by a newer BugVoice), the sheet
  shows, but every change is disabled, as today.

### Folders tab

The same behaviour as today's `ManageFoldersSheet`:
- rows sorted by `LibraryFolders.sorted`, each with "N notes · N meetings";
- Rename in place;
- Delete asks first, and the folder's items become Unfiled;
- New folder;
- the same footnote about nothing being deleted.

New: the footer shows the Unfiled counts.

### Tags tab

- **Rows.** One row per tag, sorted A–Z. Each row shows:
  - its colour dot, or a hollow dot for none;
  - `#name`;
  - counts: "N notes · N meetings", or one of them, or "not used";
  - Rename and Delete.
- **Colour.** Clicking a row's dot opens the palette under the row: seven
  colours and None. Picking one saves at once.
- **New tag.** Opens an inline field at the top of the list.
  - The name goes through `TagName.normalize`.
  - An invalid name shows the existing message: "Tags use letters, numbers, -
    _ and /, up to 32 characters."
  - A name that already exists selects that row instead.
  - A new tag is saved to `library.json` and shows as "not used".
- **Rename.** Edits the name in place, then Save or Cancel. On Save:
  - an invalid name shows the same message;
  - an unchanged name closes the field;
  - a name no other tag uses renames the tag on every note and meeting that
    has it, and in `library.json`. The colour follows the tag;
  - a name another tag uses asks: "Merge #old into #new? N notes and N
    meetings will use #new." On Merge, each item gets `#new` in place of
    `#old`, without duplicates and keeping the other tags' order. The merged
    tag keeps `#new`'s colour, or `#old`'s if `#new` has none.
- **Delete** asks: "Delete #name? It will be removed from N notes and N
  meetings. The notes and meetings stay." On Delete, the tag leaves every item
  and `library.json`.
- **Filters.** A rename or merge updates any page tag filter holding the old
  name. A delete removes the name from those filters.
- **Partial failure.** If some items fail to save, the others keep the change.
  `saveError` shows "Could not update N items. Try again." Running the same
  rename again finishes the rest, because items already renamed no longer carry
  the old name.
- **Meetings.** A meeting's `suggestedTags` are renamed and removed the same
  way as its `tags`. A suggestion that ends up equal to one of the meeting's
  tags is dropped, as `setMeetingLabels` already does.
- **Tag limit.** Rename, merge and delete never add a tag to an item, so the
  10-tag limit cannot fail them.
- **Order of saves.** Items are saved first, each through
  `NotesController.setLabels` or `setMeetingLabels`, whatever the meeting's
  state. `library.json` is saved last, and only when every item succeeded.
  After a partial failure the old name is still on the failed items, so it
  still shows in the Tags tab, and running the same action again finishes the
  rest.
- **Read only.** While `library.json` is read only, rename, merge, delete, New
  tag and colours are all disabled, not only the folder actions.

### Tag colours in the app

Every `TagChip` shows a small dot in the tag's colour before `#name`. A tag
with no colour shows no dot, as today. Chips appear in:
- the editor tag field;
- the filter menus;
- meeting rows;
- Scratchpad cards and preview;
- Upload.

### Filter row (Scratchpad and Meetings pages)

- `TagFilterBar` no longer puts chips in the row. The Tags button shows a count
  badge when one or more tags are picked.
- The Tags menu lists every tag with a checkmark on picked ones. Clicking
  toggles. Then a divider, "Clear tags" (disabled when none are picked), and
  "Manage tags…".
- Matching is unchanged: an item must have every picked tag.
- The folder menu keeps its entries. "Manage folders…" opens the Folders tab.
- The row is the folder menu, Tags, Sort and Reload, on one line at the list's
  minimum width.

### Scratchpad cards

Under the date line, a card shows a badge line when it has a folder or tags:
- the folder name with a `folder` icon. Unfiled shows nothing;
- up to three tag chips with their colour dots, then "+N" for the rest, the
  same rule as meeting rows;
- the line wraps on a narrow list.

A card with neither shows title, date and preview only, as today.

The note preview on the right shows all its tag chips, now with colour dots.

## Entry points

| Place | Entry | Opens |
|---|---|---|
| Scratchpad and Meetings pages, folder filter menu | Manage folders… (exists) | Folders tab |
| Scratchpad and Meetings pages, Tags filter menu | Manage tags… (new, last item) | Tags tab |
| Scratchpad page, New note ⌄ menu | Manage folders and tags… (new, last item, after a divider) | Folders tab |
| Floating editor, folder menu (`FolderPicker`) | Manage folders… (new, after New folder…) | Folders tab, over the floating window |
| Floating editor, tag suggestions (`TagField`) | Manage tags… (new, after a divider at the end of the list) | Tags tab, over the floating window |
| Settings › General | New card "Folders and tags": "N folders · N tags", button "Manage…" | Folders tab |

`FolderPicker` and `TagField` are shared with meetings and Upload, so these
entries appear there too. Each place already holds the `AppModel` and presents
sheets (`FolderPicker` shows `NewFolderSheet` this way), so the floating window
gets the sheet the same way.

`TagChip` reads the tag colours from the SwiftUI environment, set once near
the root of each window from `AppModel`, so no call site passes them.

## Constraints

- macOS 15 floor, Swift 6, no new dependencies.
- VoiceCore imports Foundation only. Data rules go in VoiceCore and are built
  test first:
  - the `library.json` tag list and colours;
  - rename, merge and delete applied to a list of tags (`ItemLabels`);
  - the Tags tab rows (union and counts).
- Tokens only; `Scripts/check-tokens.sh` exits 0.
- UI copy is plain English, with no hedging words and no emoji.

## Calls I made (owner to check)

- The sheet replaces `ManageFoldersSheet`, so there is one place for both.
- The one-line Tags button with a count also applies to the Meetings page,
  because both pages share `TagFilterBar`.
- Seven colours plus None. Tags with no colour look exactly as today.
- New tag stores unused tags in `library.json`. Before this, a tag existed only
  on items.
- Merge keeps the target's colour, or the source's if the target has none.
- Cards show at most three tags plus "+N", as meeting rows do.
- Settings › General gets the entry rather than a new Settings tab.
- `library.json` stays version 1.
- The Tags tab sorts A–Z with no sort control. The mockup's sort menu is
  dropped.
- `library.json` is saved only after every item succeeded. After a partial
  failure, running the action again finishes it.
- Read-only `library.json` disables every tag change too, not only folders.

## Left to the builder

- File layout inside `UI/Library/` (for example `ManageLibrarySheet.swift`, with
  `FoldersTab` and `TagsTab`).
- How bulk changes are batched, as long as each item is saved through
  `NotesController.setLabels` or `setMeetingLabels`.
- The exact colour values, chosen to read on both themes.

## Manual checks

1. Each entry point in the table opens the sheet on the right tab, including
   over the floating Scratchpad window.
2. Folders tab: create, rename and delete a test folder. Delete asks first, and
   the counts are right.
3. Tags tab: New tag shows "not used". Colour a tag, and the dot shows in the
   editor, filter menu, card and meeting row.
4. Rename a test tag used by two notes and one meeting: all three change, and a
   page filter on the old name follows.
5. Rename a test tag onto another existing tag: the confirmation shows counts,
   and no item ends up with a duplicate.
6. Delete a test tag: the confirmation shows counts, the tag leaves every item,
   and the note bodies are unchanged.
7. Scratchpad page: pick two tags. The row stays on one line with a "2" badge.
   Clear tags empties the filter.
8. Scratchpad cards show the folder and up to three coloured tags. An Unfiled
   card with no tags shows no badge line.
9. Light and dark, at 100% and 160% text.
10. A `library.json` from before this change loads, and the folders are
    unchanged.
