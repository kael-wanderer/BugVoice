# Note editor execution log

Branch: `feat/note-editor`, merged to `main` 2026-10-18 (69ad3f0), pushed 2026-10-19.
Spec: `docs/superpowers/specs/2026-10-18-note-editor-design.md`. Mockup: `docs/design/proposal-editor.html`.
Plan: `docs/superpowers/plans/2026-10-18-note-editor.md`. Tasks 1–3 built by Codex (Sol), reviewed and checked by Claude.

## Tasks

### Task 1 — AI bar shown on request
`17799b0` — feat(core): `aiBarShown` replaces `ScratchpadSettings.bottomBar`; the enum is deleted. An old `bottomBar` key is ignored and dropped on the next save.

### Task 2 — Tool row, Formatting bar, tab bar
`b5b7da4` — feat(app): `ScratchpadToolRow` (AI, folder, tags, then mic, history, Trash, Copy), Formatting bar under it, AI bar under the text, logo and Markdown | Doc in the tab bar, scope menu first in the chip row, table picker opens below.

### Task 3 — List menu and main window button
`b98abb5` — feat(app): right-click on a list note (Pin, Move to folder, Move to Trash… with confirmation); "Open Scratchpad editor" in the Scratchpad page title row.

### Review and check fixes
- `de7cd64` — The Formatting bar remembered its tallest height, so widening the window after it wrapped left an empty line. The AI toggle missed clicks on its padding while off.
- `8b6e321` — ⌘1–⌘3 did nothing. The hidden shortcut buttons kept the action from their first render, which held the window's placeholder assistant (scope `note("")`), so `run` returned early. The buttons now rebuild when the assistant changes. This bug was older than this branch.
- `3826a2e` — At 440 pt the scope menu and chips shared one row and the chips shrank to "…". In a narrow window the scope menu now takes its own line and the chips wrap.

## Manual checks

Run 2026-10-18 in the dev app on the second display, dark theme, 100% text. `settings.json` was backed up first and restored afterwards (`cmp` identical). No notes were created or moved to the Trash; one test note was polished, moved to a folder and back, and pinned and unpinned.

1. Matches the mockup in light and dark, at 100% and 160% text. Dark at 100%: passed. Light and 160%: not verified, left to the owner.
2. AI toggle off: no bar, no ring. On: ring and bar. ⌘1 with it off shows the bar and runs Polish (after `8b6e321`). ⌘↩ copies the note and closes the window. Passed.
3. Formatting bar in Markdown view; table picker opens below its button; Doc view shows the read-only line at the same height. Passed. Formatting commands themselves were not clicked.
4. Every row of the table works from its new place. Logo, folder menu, view switch, Copy, AI bar, scope menu and the main window button: passed. Mic, History and the Trash button were not clicked (dictation and deletion): not verified, left to the owner.
5. Right-click a list note: Pin and Unpin, Move to folder (Client A, then Unfiled), Move to Trash… asks first (Cancel used). Passed.
6. Narrow window (440 pt): the right group moves to a second line, right aligned; the Formatting bar takes two lines; the AI chips wrap under the scope menu (after `3826a2e`). Nothing clipped. Passed.
7. On the Scratchpad page, "Open Scratchpad editor" in the title row opens the note in the floating window. Passed.
8. A settings file from before the update (`"bottomBar": "formatting"`) loads with AI off. Passed; also covered by `ScratchpadSettingsTests`.

`swift test`: 1,049 tests pass. `Scripts/check-tokens.sh`: exit 0.
