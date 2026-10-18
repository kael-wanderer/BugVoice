# Folders and Tags Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One Manage library sheet (Folders and Tags tabs) with tag rename, merge, delete and colours applied across notes and meetings, a one-line filter row, and folder and tag badges on Scratchpad cards.

**Architecture:** VoiceCore gains the tag list in `library.json`, the colour enum, pure tag edits on a list of names, and the Tags tab projection, all test first. `AppModel` applies those edits to every note (`NotesController.setLabels`) and meeting (`setMeetingLabels`), then saves `library.json`. The UI replaces `ManageFoldersSheet` with `ManageLibrarySheet`, and `TagChip` reads colours from the environment.

**Tech Stack:** Swift 6, SwiftUI, macOS 15, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-18-library-management-design.md` (mockup `docs/design/proposal-library.html`).

## Global Constraints

- Swift package, tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only. No new dependencies.
- TDD for everything in `VoiceCore`: failing test first. `swift test` passes before every commit.
- Tokens only: no literal colours, fonts or spacing in views. Colour values live in `Sources/BugVoice/UI/Theme/`. `Scripts/check-tokens.sh` exits 0.
- UI copy: plain English, no hedging words, no emoji. Copy strings below are exact.
- Tag names follow `TagName.normalize` (lowercase, no `#`, ≤ 32 characters); an item holds ≤ 10 tags.
- `library.json` stays `version: 1`. A file without `tags` loads unchanged.
- A rename or delete touches front matter `tags` (and a meeting's `tags` and `suggestedTags`) only, never a note body.
- Commit after each task: `feat(core): …`, `feat(app): …`, `docs: …`. Do not push.

## Review Focus

1. Rename onto a name that normalizes to the same tag (`#Client` for `client`): it is a no-op, with no dialog and no writes. Test: `renameToSameNameIsNoChange` (Task 1).
2. Merge where an item already has both tags: one copy stays, in the target's position, and the other tags keep their order. Test: `mergeKeepsOneCopyInOrder` (Task 1).
3. A `library.json` from before this change, or one with an unknown colour, loads; the folders are unchanged and the colour reads as none. Tests: `oldFileWithoutTagsLoads`, `unknownColourReadsAsNone` (Task 1).
4. A delete or rename of a tag held in a page's tag filter: the filter follows, so the list does not show "No results" for a tag that no longer exists. Test: `filterFollowsRenameAndDelete` (Task 1, on `TagEdit.apply` used by both filters).
5. A note open in the floating editor with unsaved typing during a rename: the typing survives, because `NotesController.setLabels` edits the loaded state. Manual check 4 (Task 5).

---

### Task 1: Tag list, colours and tag edits in VoiceCore

**Files:**
- Modify: `Sources/VoiceCore/Library.swift`
- Create: `Sources/VoiceCore/LibraryTags.swift`
- Test: `Tests/VoiceCoreTests/LibraryTagsTests.swift`

**Interfaces:**
- Produces:
  - `public enum TagColor: String, Codable, CaseIterable, Sendable { case red, orange, yellow, green, teal, blue, purple }`
  - `public struct LibraryTag: Codable, Equatable, Sendable { public var name: String; public var color: TagColor? }`. Decoding an unknown `color` string gives `nil`, not an error.
  - `LibraryFile.tags: [LibraryTag]`, default `[]`. `LibraryFile` gets a custom `init(from:)` that uses `decodeIfPresent` for `tags` and keeps `version`, `folders` and `lastUploadFolderID` as today. The `init(version:folders:lastUploadFolderID:)` initializer gains `tags: [LibraryTag] = []`.
  - `public enum TagEdit` with:
    - `rename(_ old: String, to new: String, in tags: [String]) -> [String]`. Replaces `old` with `new` at `old`'s index. If `new` is already present, removes `old` instead. Order is otherwise unchanged.
    - `remove(_ name: String, from tags: [String]) -> [String]`.
  - `public enum LibraryTags` with:
    - `color(of name: String, in file: LibraryFile) -> TagColor?`
    - `create(_ raw: String, inUse: Set<String>, in file: inout LibraryFile) -> TagCreateResult`, with `public enum TagCreateResult: Equatable, Sendable { case created(String), exists(String), invalid }`. `exists` covers both a name already in `file.tags` and a name in `inUse` (tags on items).
    - `setColor(_ color: TagColor?, for name: String, in file: inout LibraryFile)`. Adds an entry if missing. Setting `nil` on an entry keeps the entry, because it may be an unused New tag.
    - `rename(_ old: String, to new: String, in file: inout LibraryFile)`. Removes `old`'s entry. If `old` or `new` had an entry, `new` gets one with colour `new.color ?? old.color`.
    - `delete(_ name: String, in file: inout LibraryFile)`.
  - `public struct TagRow: Equatable, Sendable, Identifiable { public let name: String; public let color: TagColor?; public let notes: Int; public let meetings: Int; public var id: String { name } }`
  - `LibraryProjection.tagRows(notes: [TagCount], meetings: [TagCount], file: LibraryFile) -> [TagRow]`. The union of the three name sets, sorted by name ascending.
  - `TagRow.countText: String`. One of "N notes · N meetings", "N notes", "N meetings" or "not used", with "1 note" and "1 meeting" in the singular.

- [ ] **Step 1: Write the failing tests** in `LibraryTagsTests.swift`:

```swift
@Test func oldFileWithoutTagsLoads() throws {
    let json = #"{"version":1,"folders":[{"id":"f1","name":"Client A","createdAt":"2026-10-01T00:00:00Z"}]}"#
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    let file = try d.decode(LibraryFile.self, from: Data(json.utf8))
    #expect(file.folders.map(\.name) == ["Client A"])
    #expect(file.tags.isEmpty)
}
@Test func unknownColourReadsAsNone() throws {
    let json = #"{"version":1,"folders":[],"tags":[{"name":"client","color":"magenta"}]}"#
    let file = try JSONDecoder().decode(LibraryFile.self, from: Data(json.utf8))
    #expect(file.tags == [LibraryTag(name: "client", color: nil)])
}
@Test func tagsRoundTrip() throws {
    var file = LibraryFile(); LibraryTags.setColor(.blue, for: "client", in: &file)
    let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    #expect(try d.decode(LibraryFile.self, from: e.encode(file)) == file)
}
@Test func renameReplacesInPlace() {
    #expect(TagEdit.rename("followup", to: "follow-up", in: ["a", "followup", "b"]) == ["a", "follow-up", "b"])
    #expect(TagEdit.rename("x", to: "y", in: ["a"]) == ["a"])
}
@Test func mergeKeepsOneCopyInOrder() {
    #expect(TagEdit.rename("old", to: "new", in: ["old", "a", "new", "b"]) == ["a", "new", "b"])
}
@Test func renameToSameNameIsNoChange() {
    #expect(TagEdit.rename("client", to: "client", in: ["client", "a"]) == ["client", "a"])
}
@Test func filterFollowsRenameAndDelete() {
    #expect(TagEdit.rename("old", to: "new", in: ["old"]) == ["new"])
    #expect(TagEdit.remove("old", from: ["a", "old"]) == ["a"])
}
@Test func createNormalizesAndReportsExisting() {
    var file = LibraryFile()
    #expect(LibraryTags.create("#Draft Notes", inUse: [], in: &file) == .created("draft-notes"))
    #expect(LibraryTags.create("draft-notes", inUse: [], in: &file) == .exists("draft-notes"))
    #expect(LibraryTags.create("client", inUse: ["client"], in: &file) == .exists("client"))
    #expect(LibraryTags.create("  ", inUse: [], in: &file) == .invalid)
    #expect(file.tags == [LibraryTag(name: "draft-notes", color: nil)])
}
@Test func renameMovesColourAndMergeKeepsTargetColour() {
    var file = LibraryFile()
    LibraryTags.setColor(.red, for: "old", in: &file)
    LibraryTags.rename("old", to: "new", in: &file)
    #expect(file.tags == [LibraryTag(name: "new", color: .red)])
    LibraryTags.setColor(.blue, for: "other", in: &file)
    LibraryTags.rename("new", to: "other", in: &file)
    #expect(file.tags == [LibraryTag(name: "other", color: .blue)])
}
@Test func deleteRemovesEntry() {
    var file = LibraryFile(); LibraryTags.setColor(.green, for: "a", in: &file)
    LibraryTags.delete("a", in: &file)
    #expect(file.tags.isEmpty)
}
@Test func tagRowsUnionSortedWithCounts() {
    var file = LibraryFile()
    _ = LibraryTags.create("draft", inUse: [], in: &file)
    LibraryTags.setColor(.teal, for: "client", in: &file)
    let rows = LibraryProjection.tagRows(
        notes: [TagCount(name: "client", count: 2), TagCount(name: "idea", count: 1)],
        meetings: [TagCount(name: "client", count: 1)], file: file)
    #expect(rows.map(\.name) == ["client", "draft", "idea"])
    #expect(rows[0] == TagRow(name: "client", color: .teal, notes: 2, meetings: 1))
    #expect(rows.map(\.countText) == ["2 notes · 1 meeting", "not used", "1 note"])
}
```

`TagRow` needs a public memberwise `init(name:color:notes:meetings:)`.

- [ ] **Step 2:** Run `swift test --filter LibraryTagsTests`. Expected: build failure on the missing types.
- [ ] **Step 3:** Implement `Library.swift` (custom decoding and the new initializer parameter) and `LibraryTags.swift` (everything else) to the interfaces above.
- [ ] **Step 4:** Run `swift test`. Expected: all pass, including the existing `LibraryTests`.
- [ ] **Step 5:** Commit `feat(core): tag list and colours in library.json; tag rename, merge and delete`.

---

### Task 2: AppModel tag actions and coloured chips

**Files:**
- Modify: `Sources/BugVoice/AppModel.swift`, next to `createFolder` / `deleteFolder`.
- Create: `Sources/BugVoice/UI/Theme/TagColors.swift`.
- Modify: `Sources/BugVoice/UI/Library/FolderControls.swift` (`TagChip`).
- Modify: the hosting roots that show tags: `UI/MainWindow.swift:112`, `UI/Scratchpad/ScratchpadWindowController.swift:77`, `MeetingWindowController.swift:142` (each calls `.bvTheme(model.appearance)`).

**Interfaces:**
- Consumes: everything Task 1 produces.
- Produces, on `AppModel`:
  - `var tagRows: [TagRow]`: `LibraryProjection.tagRows(notes: noteTagCatalog, meetings: meetingTagCatalog, file: library)`.
  - `var tagColors: [String: TagColor]`, built from `library.tags`.
  - `func createTag(_ raw: String) async -> TagCreateResult`. `inUse` is the `allTagCatalog` names. It saves only on `.created`.
  - `func setTagColor(_ color: TagColor?, for name: String) async`
  - `func renameTag(_ old: String, to raw: String) async -> TagRenameOutcome`, where `enum TagRenameOutcome: Equatable { case renamed, unchanged, invalid, needsMerge(target: String, notes: Int, meetings: Int), failed(count: Int) }`. It normalizes `raw`:
    - nil gives `.invalid`;
    - equal to `old` gives `.unchanged`;
    - a name in `allTagCatalog` or `library.tags` gives `.needsMerge(...)`, with the counts of items carrying `old`, and changes nothing;
    - otherwise it applies the rename and returns `.renamed` or `.failed(count:)`.
  - `func mergeTag(_ old: String, into new: String) async -> TagRenameOutcome`. Applies without the merge check.
  - `func deleteTag(_ name: String) async -> TagRenameOutcome`. Returns `.renamed` on success; the name is reused to keep one type.
  - `var librarySheet: LibrarySheetTab?` with `enum LibrarySheetTab: Identifiable { case folders, tags }`. Task 3 presents it.
- Apply rule, shared by rename, merge and delete:
  1. For each note in `notesController.notes` whose `frontMatter.tags` contains `old`, call `notesController.setLabels(id:folderID:tags:)` with `TagEdit.rename` or `TagEdit.remove`.
  2. For each meeting in `meetingManifests` whose `tags` or `suggestedTags` contains `old`, call `setMeetingLabels(id:folderID:tags:suggestedTags:)`. Pass the edited `suggestedTags` minus any name now in the edited `tags`. Count a failure when the meeting's manifest still carries `old` after `reloadMeetings()`, because `setMeetingLabels` reports errors through `saveError`, not by throwing.
  3. Count thrown note errors the same way.
  4. With zero failures, apply `LibraryTags.rename` or `LibraryTags.delete` to `library` and `saveLibrary()`. Then set `notesTagFilter` and `meetingTagFilter` through `TagEdit` (rename), or remove the name from them (delete).
  5. With failures, leave `library.json` alone, set `saveError = "Could not update \(n) items. Try again."`, and return `.failed(count:)`.
- Every tag action returns early, with no change, while `libraryReadOnly`. Rename, merge and delete return `.failed(count: 0)` then; `createTag` returns `.invalid`.
- `TagColors.swift`, modelled on `SpeakerColors.swift`:
  - `enum TagColors { static func color(_ c: TagColor) -> Color; static func dot(_ c: TagColor) -> Image }`, with a light and a dark sRGB value per case through `NSColor(name:)`;
  - an `EnvironmentValues.tagColors: [String: TagColor]` entry, default `[:]`.
- `TagChip` shows `Circle().fill(TagColors.color(c)).frame(width: store.scaled(8), height: store.scaled(8))` before `#name` when `tagColors[name]` is set, and is unchanged otherwise.
- Each of those roots wraps its view in `.tagColors(model)`, a `ViewModifier` holding `let model: AppModel` whose `body` sets `.environment(\.tagColors, model.tagColors)`. The read happens inside `body`, so Observation updates the colours when `library` changes. Passing `model.tagColors` as a value at hosting-controller creation would freeze it, so do not.

- [ ] **Step 1:** Implement the model actions and the colours to the interfaces above.
- [ ] **Step 2:** Run `swift build`, `swift test` and `Scripts/check-tokens.sh`. Expected: all pass, with no new token hits outside `UI/Theme/`.
- [ ] **Step 3:** Commit `feat(app): tag rename, merge, delete and colours across notes and meetings`.

---

### Task 3: Manage library sheet and entry points

**Files:**
- Create: `Sources/BugVoice/UI/Library/ManageLibrarySheet.swift` (sheet, `FoldersTab`, `TagsTab`).
- Delete: `Sources/BugVoice/UI/Library/ManageFoldersSheet.swift`. Move its folder rows into `FoldersTab` unchanged.
- Modify:
  - `NotesPage.swift`, `MeetingsPage.swift`: replace the `managingFolders` sheets with `.sheet(item:)` on a local `LibrarySheetTab?`.
  - `FolderControls.swift`: `FolderFilterMenu` "Manage folders…" opens Folders. `FolderPicker` gains "Manage folders…" after "New folder…".
  - `TagField.swift`: when suggestions show, add a divider and a "Manage tags…" row last.
  - `Shell/PageActions.swift` (`.notes`): after "Ask AI about my notes", add a `Divider()` and "Manage folders and tags…", which sets `model.librarySheet = .folders`.
  - The view that hosts `PageActions` presents `.sheet(item: $model.librarySheet)`.
  - `Settings/GeneralTab.swift`: a new `SettingsCard(title: "Folders and tags")` with `SettingsRow(title: "\(folders) folders · \(tags) tags") { Button("Manage…") }`, which opens the sheet on Folders over the Settings window. Folders is `library.folders.count`; tags is `tagRows.count`.
- `FolderPicker` and `TagField` take a new closure parameter, `onManage: (() -> Void)?` (nil hides the entry). Each caller presents the sheet from its own window: the Scratchpad tool row, the meeting detail and Upload.

**Sheet layout** (mockup "Tags tab" and "Folders tab"):
- Title "Manage library", then a segmented `Picker` with Folders | Tags.
- Width `store.scaled(460)`. Done is the default action, and Escape closes the sheet.
- Every control is disabled while `model.libraryReadOnly`.

**FoldersTab:** today's rows. The footer has "+ New folder" and, on the right, "Unfiled: N notes · N meetings" from `LibraryProjection.counts(...).unfiled`. Keep the existing footnote and delete dialog.

**TagsTab:**
- One row per `model.tagRows`:
  - a dot button: filled in `TagColors.color`, or a hollow `Circle().stroke(.bvSeparator)` for none. It toggles a swatch row under the tag row with the seven colours and "None". Picking one calls `setTagColor`;
  - `#name`;
  - `countText`, in secondary footnote;
  - Rename and Delete.
- Rename turns the name into a `TextField` with Save (prominent) and Cancel. Save calls `renameTag`:
  - `.invalid` shows "Tags use letters, numbers, - _ and /, up to 32 characters." under the list in `.bvRecording`;
  - `.unchanged` and `.renamed` close the field;
  - `.needsMerge` shows `confirmationDialog("Merge #\(old) into #\(target)?")`, with the message "\(notes) notes and \(meetings) meetings will use #\(target)." and the buttons "Merge" and "Cancel". Merge calls `mergeTag`;
  - `.failed` keeps the field open; `saveError` already shows.
- Delete shows `confirmationDialog("Delete #\(name)?")`, with the message "It will be removed from \(notes) notes and \(meetings) meetings. The notes and meetings stay." and the buttons "Delete" (destructive) and "Cancel".
- The footer has "+ New tag". It shows an inline `TextField("#tag")` at the top of the list. Return calls `createTag`:
  - `.exists(name)` scrolls to and highlights that row;
  - `.invalid` shows the message above.
- With no tags at all, the tab shows "No tags yet."

- [ ] **Step 1:** Implement the sheet, then wire every entry point in the spec's table.
- [ ] **Step 2:** Run `swift build`, `swift test` and `Scripts/check-tokens.sh`. Expected: all pass. Also run `rg ManageFoldersSheet Sources`. Expected: no hits.
- [ ] **Step 3:** Commit `feat(app): Manage library sheet with Folders and Tags tabs`.

---

### Task 4: One-line filter row and card badges

**Files:**
- Modify: `Sources/BugVoice/UI/Library/FolderControls.swift` (`TagFilterBar`)
- Modify: `Sources/BugVoice/UI/NotesPage.swift` (`card`, filter row)
- Modify: `Sources/BugVoice/UI/MeetingsPage.swift` (passes `onManage`)

**Interfaces:** `TagFilterBar(catalog: [TagCount], selected: Binding<[String]>, onManage: () -> Void)`.

- **TagFilterBar** is one `Menu`, with no chips in the row. Its menu, in order:
  1. One `Toggle` per catalog tag. The label is `#name  count`, with `TagColors.dot` before it when coloured, because menus drop SwiftUI shapes. Toggling adds or removes the tag in `selected`.
  2. With an empty catalog, the text "No tags yet".
  3. `Divider()`.
  4. "Clear tags", disabled when `selected` is empty.
  5. "Manage tags…".
- **Label:** `Label("Tags", systemImage: "tag")`. When `selected` is not empty, a count badge follows: `Text("\(selected.count)")` in caption, `.bvOnAccent` on a `.bvAccent` capsule. The accessibility label is "Tags, \(n) selected".
- **Filter row:** on NotesPage it is now four fixed-size controls: folder menu, Tags, Sort and Reload. Keep `FilterRow`. It must fit on one line at `ShellLayout.listPaneRange.lowerBound`; check this in Task 5.
- **Card badges:** in `NotesPage.card`, between the date and the preview, when the note has a known folder or tags, add a `FlowLayout(spacing: LayoutTokens.spacing[0])` with:
  - `Label(folderName, systemImage: "folder")` in footnote and secondary, only for a known folder;
  - `ForEach(tags.prefix(3)) { TagChip(name:) }`;
  - `"+\(tags.count - 3)"` in footnote and secondary when there are more.

  `NotesListItem` has `tags` but no folder, and lives in VoiceCore. Leave it unchanged. In `NotesPage`, build `[NoteID: FolderID]` from `controller.notes` (`frontMatter.folderID`) next to `items`, and pass the name from `model.folderName(_:)` into `card`.

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** Run `swift build`, `swift test` and `Scripts/check-tokens.sh`. Expected: all pass.
- [ ] **Step 3:** Commit `feat(app): one-line tag filter with a count; folder and tag badges on Scratchpad cards`.

---

### Task 5: Manual checks and log

**Files:**
- Create: `docs/progress/library-management-log.md`. Write one line per task with its commit, then the spec's manual checks 1–10, each marked passed or "not verified, left to the owner".
- Modify: `AGENTS.md`. Under the "Folders and tags management spec" line, add ``- Folders and tags management plan: `docs/superpowers/plans/2026-10-18-library-management.md` `` and ``- Folders and tags execution log and manual checks: `docs/progress/library-management-log.md` ``.

- [ ] **Step 1: Run the checks in the dev app.**
  - Back up `~/Library/Application Support/BugVoice/settings.json` and `library.json` first. Afterwards restore both and confirm with `cmp`.
  - Build with `Scripts/build-app.sh`, then run `Scripts/run-dev-app.sh`. Windows open on the second display. Click only there.
  - Use test tags and a test folder you create, such as `zz-test` and `zz-merge`, on notes you create for the test. Remove them at the end: delete the test tags and folder, and move the test notes to the Trash.
  - Never rename, merge or delete the owner's existing tags or folders.
  - Include Review Focus 5: type in a test note in the floating editor, then rename one of its tags from the sheet without waiting. The typing must still be there.
- [ ] **Step 2: Final run.** `swift test` passes and `Scripts/check-tokens.sh` exits 0.
- [ ] **Step 3:** Commit `docs: folders and tags log and manual checks`.
