# Note Editor Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rearrange the floating Scratchpad editor so it reads, top to bottom: title; one tool row; an always-on Formatting bar; the text; and an AI bar shown on request. Also rename the Scratchpad page's "Open in window" button.

**Architecture:** One VoiceCore settings change (`aiBarShown` replaces `bottomBar`), with tests. Everything else is SwiftUI rearrangement inside `Sources/BugVoice/UI/Scratchpad/`, reusing the existing pieces: `FolderPicker`, `TagField`, `NotesMicButton`, the history and copy menus, `MarkdownToolbar`, `AIBar` and `AIReplyView`. No new behaviour beyond what the spec lists.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-18-note-editor-design.md` (mockup: `docs/design/proposal-editor.html`, section "Floating window (option A, agreed)").

## Global Constraints

- Swift package, tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only. No new dependencies.
- TDD for VoiceCore: write the failing test first. `swift test` passes before every commit.
- Colours, fonts and spacing come only from foundation tokens (`.bv…` styles, `.bvFont(...)`, `LayoutTokens`, `store.scaled`). `Scripts/check-tokens.sh` exits 0.
- UI copy is plain English, with no hedging words and no emoji. The exact strings below are fixed.
- Shortcuts are unchanged: ⌘↩ is Copy and close, ⌘⇧C is Copy, ⌘1–⌘3 run the chips, Esc cancels in the AI bar, and ⌘B/⌘I/⌘U stay on the Formatting bar.
- Every action calls the method it calls today. Move views; do not copy their logic.
- Commit after each task: `feat(core): …`, `feat(app): …` or `docs: …`. End each message with a blank line, then `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Use `rg` to search. Do not touch `~/Library` or `settings.json`. Do not launch the app unless a task says so.

## Review Focus

1. **Doc view.** The Formatting bar slot shows "Doc view is read only. Switch to Markdown to edit." and does not change height, so the text does not jump when switching views. (Task 2.)
2. **⌘1 while the AI bar is hidden.** The bar appears and the reply shows; nothing is lost. (Task 2.)
3. **The 420 pt minimum width, and compact mode.** The tool row wraps its right group to a second line, right aligned. Nothing is clipped. (Task 2, `ViewThatFits`.)
4. **An old settings file** with `"bottomBar": "formatting"` loads with the AI bar off and no error. (Task 1 test.)
5. **Turning AI off while a reply is pending** hides the reply; turning AI on shows it again. (Task 2: the reply stays in `assistant`, and only its view is gated.)

---

### Task 1: `aiBarShown` setting

**Files:**
- Modify: `Sources/VoiceCore/Settings.swift`
  - Delete `ScratchpadBottomBar` (lines 200–203).
  - In `ScratchpadSettings`, replace `bottomBar` with `aiBarShown`.
- Modify: `Tests/VoiceCoreTests/ScratchpadSettingsTests.swift`: rewrite the `bottomBar` expectations (lines ~33, 39, 46–48).
- Modify: `Sources/BugVoice/AppModel+Scratchpad.swift:100`: `openScratchpadAsk` sets `settings.scratchpad.aiBarShown = true`.
- Modify: `Sources/BugVoice/UI/Scratchpad/ScratchpadWindowView.swift`:
  - Delete the two `barButton` calls and the `Divider()` above them in `sideList`.
  - Delete `barButton(_:title:symbol:)`.
  - The list now ends with the notes.
- Modify: `Sources/BugVoice/UI/Scratchpad/ScratchpadNoteEditor.swift` `bottomBar`, as a temporary bridge so the app compiles. Task 2 replaces it.
  - `if model.settings.scratchpad.aiBarShown { AIBar(...) }`
  - `else if markdown { MarkdownToolbar }`
  - else the read-only line, as today.

**Interfaces:**
- Produces: `ScratchpadSettings.aiBarShown: Bool`, default `false`. It is decoded with `c.value(.aiBarShown, default: aiBarShown)`. The old `bottomBar` key is not in `CodingKeys`, so it is ignored on read and not written.

- [ ] **Step 1: Rewrite the tests** in `ScratchpadSettingsTests.swift`:

```swift
// default
#expect(decoded.scratchpad.aiBarShown == false)
// round trip
changed.scratchpad.aiBarShown = true   // encode, decode, expect true
// old files
let old = #"{"scratchpad":{"bottomBar":"formatting","sort":"size","keepOnTop":false}}"#
// decodes: aiBarShown == false, keepOnTop == false, sort == .editedNewest
let oldAI = #"{"scratchpad":{"bottomBar":"ai"}}"#
// decodes: aiBarShown == false
// encoding never writes "bottomBar"
#expect(!String(decoding: try JSONEncoder().encode(Settings()), as: UTF8.self).contains("bottomBar"))
```

  Keep every other existing expectation in that file unchanged.
- [ ] **Step 2: Run** `swift test --filter ScratchpadSettingsTests`. Expected: the build fails because `aiBarShown` does not exist yet.
- [ ] **Step 3: Implement** the `Settings.swift` change, then the app-side edits listed under Files.
- [ ] **Step 4: Run** `swift test --filter ScratchpadSettingsTests` (PASS), then `swift build` (no new warnings), `swift test` (PASS) and `Scripts/check-tokens.sh` (exit 0).
- [ ] **Step 5: Commit** `feat(core): Scratchpad AI bar shown on request (aiBarShown)`.

---

### Task 2: Editor layout

**Files:**
- Create: `Sources/BugVoice/UI/Scratchpad/ScratchpadToolRow.swift`.
- Modify: `Sources/BugVoice/UI/Scratchpad/ScratchpadNoteEditor.swift`.
- Modify: `Sources/BugVoice/UI/Scratchpad/ScratchpadTabBar.swift` (logo and view switch).
- Modify: `Sources/BugVoice/UI/Scratchpad/AIBar.swift` (scope picker position).
- Modify: `Sources/BugVoice/UI/Scratchpad/MarkdownToolbar.swift:67` (`arrowEdge: .bottom`).

**Interfaces:**
- Consumes: `aiBarShown` (Task 1).
- Produces:
  ```swift
  struct ScratchpadToolRow<Trailing: View>: View {
      init(model: AppModel, note: NoteDocument, @ViewBuilder trailing: () -> Trailing)
  }
  ```
  `trailing` is the right group: mic, history, Trash and Copy. They stay in `ScratchpadNoteEditor`, which owns their state (`confirmDelete`, `dictate`, `historyMenu`, `copyMenu`), and are passed in.

- [ ] **Step 1: Tab bar** (`ScratchpadTabBar`).
  - Logo: replace `Image(systemName: "waveform")` with `Image(nsImage:)` of `IconImages.menuGlyph(model.settings.appearance.menuBarIcon)`.
    - Use `.resizable()` and a 16 pt frame (`store.scaled(16)`), with `.foregroundStyle(store.theme.accent)`.
    - Fall back to the waveform symbol when the glyph is nil.
    - Keep `.accessibilityHidden(true)`.
  - View switch: move the existing view `Picker` (segmented, `NoteViewMode`, bound to `model.scratchpadView`) from `ScratchpadNoteEditor.actionRow`. Place it right after `Spacer(minLength: 8)` and before the Keep on top toggle. Use `.controlSize(.small)`, `.fixedSize()` and `.labelsHidden()`.
- [ ] **Step 2: `ScratchpadToolRow`.**
  - Left group, in this order:
    1. **AI toggle.** A `Button` with label `Label("AI", systemImage: "sparkles")` that toggles `model.settings.scratchpad.aiBarShown`.
       - On: `.bvAccentSoft` background in a `RoundedRectangle(cornerRadius: LayoutTokens.controlRadius)`, plus an overlay ring: `RoundedRectangle(cornerRadius: LayoutTokens.controlRadius + 2).stroke(store.theme.accent.opacity(0.5), lineWidth: 3).padding(-2)`.
       - Off: a `.bvSeparator` 1 pt border and no ring.
       - Padding: `spacing[1]` horizontal, `spacing[0]` vertical.
       - Accessibility: `.accessibilityAddTraits(.isToggle)`, `.accessibilityValue(on ? "on" : "off")`, `.help("AI (show or hide the AI bar)")`.
    2. **Folder.** `FolderPicker(model:folderID:onChange)`.
    3. **Tags.** `TagField(tags:catalog: model.allTagCatalog, noun: "note")`.
    - Both write through `model.setNoteLabels(id:folderID:tags:)`, exactly as `LabelsBox` does today.
  - Right group: `trailing`.
  - Layout: `ViewThatFits(in: .horizontal)` with two candidates:
    - one line: `HStack { left; Spacer(minLength: spacing[2]); trailing }`;
    - two lines: `VStack(alignment: .trailing, spacing: spacing[0]) { left (leading aligned, full width); trailing }`.
  - Padding: `spacing[3]` horizontal, `spacing[0]` bottom.
- [ ] **Step 3: `ScratchpadNoteEditor` body, top to bottom:**
  1. Title field (unchanged).
  2. `ScratchpadToolRow(model:note:) { mic; historyMenu; trash button; copyMenu }`. The views move out of `actionRow`, which is deleted along with `LabelsBox` here.
  3. Formatting slot: `formattingBar`. Full width, `.bvCard` background, a 1 pt `.bvSeparator` line above and below. It contains:
     - in Markdown view: `MarkdownToolbar { run($0) }`, `.disabled(askShowing)`, where `askShowing = assistant.askStep != nil || assistant.askResult != nil || assistant.askError != nil`;
     - in Doc view: `Text("Doc view is read only. Switch to Markdown to edit.")` (footnote, secondary), centred.
     - `.frame(minHeight:)` set to the toolbar's single-line height (measure it once with `onGeometryChange` and keep the max), so switching views does not move the text.
  4. `statusRow` (unchanged).
  5. Body `ZStack` (unchanged).
  6. Bottom `VStack`, in this order:
     - `AIReplyView` if `aiBarShown` and a reply exists for this note;
     - the listening bar if `model.notesIsListening`, whatever the toggle state;
     - `AIBar` in today's card styling, only if `aiBarShown`.
- [ ] **Step 4: ⌘1–⌘3.** In `shortcuts`, each transform button first sets `model.settings.scratchpad.aiBarShown = true`, then runs as today. ⌘⇧C and ⌘↩ stay as they are.
- [ ] **Step 5: `AIBar` scope picker.** In `.idle`, move `scopeMenu` from the question row to the first item of the chip `HStack`, before the chips. The question row becomes the text field and the send button.
- [ ] **Step 6: Table popover.** `MarkdownToolbar.swift:67`: `arrowEdge: .bottom`.
- [ ] **Step 7: Doc comments.** Update the comments at the top of `ScratchpadNoteEditor` and `ScratchpadWindowView` to the new layout.
- [ ] **Step 8: Verify.** `swift build` (no new warnings), `swift test` (PASS), `Scripts/check-tokens.sh` (exit 0).
- [ ] **Step 9: Commit** `feat(app): Scratchpad editor tool row, formatting bar on top, AI bar on request`.

---

### Task 3: List menu and page button

**Files:**
- Modify: `Sources/BugVoice/UI/Scratchpad/ScratchpadWindowView.swift` (side list rows).
- Modify: `Sources/BugVoice/UI/Scratchpad/NotePreview.swift`.

- [ ] **Step 1: Side list `.contextMenu`.** On each row `Button`, use the same calls as `NotesPage.card`'s menu (`NotesPage.swift:150-165`), without Edit:
  - `Button(item.pinned ? "Unpin" : "Pin")` calls `model.setNotePinned(item.id, pinned: !item.pinned)`.
  - `Menu("Move to folder")` holds `Button("Unfiled")`, a `Divider()`, then `ForEach(model.sortedFolders)`. Each item calls `model.setNoteLabels(id:folderID:tags: item.tags)`.
  - A `Divider()`.
  - `Button("Move to Trash…", role: .destructive)` sets `@State pendingDelete: NotesListItem?`.
  - A `.confirmationDialog` copied in shape from `NotesPage`: title "Move \(title) to the Trash?", buttons "Move to Trash" (destructive, calls `model.deleteNote`, puts errors in `saveError` with the same message) and "Cancel".
- [ ] **Step 2: `NotePreview`.**
  - Remove the `HStack { Spacer; Button("Open in window") }` row.
  - Make the title row `HStack(alignment: .firstTextBaseline) { Text(note.title).bvFont(.title2); Spacer(minLength: spacing[2]); Button("Open Scratchpad editor") { … same call … }.buttonStyle(.borderedProminent) }`.
- [ ] **Step 3: Copy check.** Run `rg -n "Open in window" Sources docs/progress/HANDOFF.md`. Update every UI string that names the old button. Leave older specs as they are.
- [ ] **Step 4: Verify.** `swift build`, `swift test`, `Scripts/check-tokens.sh`.
- [ ] **Step 5: Commit** `feat(app): Scratchpad list menu in the floating window; Open Scratchpad editor`.

---

### Task 4: Manual checks and log

**Files:**
- Create: `docs/progress/note-editor-log.md`, with one line per task and its commit, then the spec's manual checks 1–8, each marked passed or "not verified, left to the owner".
- Modify: `AGENTS.md`. Under the "Note editor redesign spec" line, add `- Note editor execution log and manual checks: \`docs/progress/note-editor-log.md\``.

- [ ] **Step 1: Run the checks in the dev app.**
  - Back up `settings.json` first. Afterwards restore it and confirm with `cmp`.
  - Build with `Scripts/build-app.sh`, then run `Scripts/run-dev-app.sh`.
  - Open the floating Scratchpad on the second display.
  - Do not create notes, and do not move real notes to the Trash.
- [ ] **Step 2: Final run.** `swift test` passes and `Scripts/check-tokens.sh` exits 0.
- [ ] **Step 3: Commit** `docs: note editor log and manual checks`.
