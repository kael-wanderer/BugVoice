# Scratchpad note editor redesign

Date: 2026-10-18. Status: draft for owner review.
Mockup: `docs/design/proposal-editor.html`, the "Floating window (option A,
agreed)" and "Main window" sections.
Roadmap: `docs/ROADMAP.md`, "Next round: the note editor".

## Why

The floating Scratchpad window spreads its controls across four places:
- a Folder/Tags box above the text;
- a row under the text with the view switch, mic, history, Trash and Copy;
- an AI/Formatting bar at the bottom;
- AI and Formatting buttons at the bottom of the note list. One of them is
  always selected, so one bar always takes space.

The owner wants the controls gathered in one row under the title. Formatting
should always be at hand, Confluence style, and AI should be shown only on
request.

## Goals

- **Tab bar.** The top-left glyph is the BugVoice logo, the same image as the
  menu bar icon. The Markdown | Doc switch moves into the tab bar's right
  group, left of the pin.
- **One tool row under the title, in this order:**
  1. AI toggle;
  2. folder menu;
  3. tags;
  4. a spacer;
  5. mic, history, Trash, Copy.
- **Formatting bar.** It sits under the tool row, above the text, and always
  shows. The table size picker opens below its button.
- **AI bar.** It sits under the text and shows only while the AI toggle is on.
  The toggle shows a focus ring while on and none while off. It starts off.
  The "Ask" entry points (`openScratchpadAsk`) and running a chip with ⌘1–⌘3
  turn it on.
- **Note list.** The AI and Formatting buttons leave the bottom of the list,
  which now ends with the notes.
- **Right-click on a note in the list:** Pin or Unpin, Move to folder ›
  (Unfiled, a divider, then each folder by name; no New folder entry), then a
  divider, then Move to Trash…. Move to Trash… asks for confirmation, as the
  Scratchpad page does.
- **AI bar scope.** The scope picker ("This note ⌄") moves to the left of the
  chips. Today it sits on the question row.
- **Main window Scratchpad page.** It stays a read-only preview. "Open in
  window" is renamed "Open Scratchpad editor" and moves to the right end of the
  title row. Double-click still opens the note.

## Non-goals

- An editor in the main window. The owner decided on 2026-10-18 to keep the
  preview. The floating window stays the only editor.
- Changes to dictation into notes, tabs, autosave, the AI actions themselves,
  or the Formatting commands.
- Appearance. The floating window already follows the text size, font family
  and theme from Settings › General, and that stays.

## Anti-goals

- Losing a control. Every current action keeps a place (see the table).
- Less room for text than today in the default state, with AI off.

## Where every current control goes

| Today | New place |
|---|---|
| Tab bar waveform glyph | BugVoice logo (`BrandImages.menuBar(logo:badge:false)` or the app icon glyph) |
| Folder/Tags box (`LabelsBox`) above the text | Tool row: folder menu, then tags (`TagField`, "+ Add tag") |
| View switch (Markdown / Doc) in the action row | Tab bar, left of Keep on top |
| Mic, History, Trash, Copy in the action row | Tool row, right end, same order |
| Bottom bar, AI mode | AI bar under the text, shown while the AI toggle is on |
| Bottom bar, Formatting mode | Formatting bar under the tool row, always shown |
| List-bottom AI / Formatting buttons | Removed. AI is the toggle in the tool row. |
| Scope picker on the AI question row | First item on the chip row |
| Scratchpad page "Open in window" (above the body) | "Open Scratchpad editor", title row, right end |

## Behaviour

**Doc view.** Doc view is read only, so the Formatting bar keeps its place and
shows the existing line "Doc view is read only. Switch to Markdown to edit."
(footnote, secondary) instead of its buttons. The row height stays the same,
so the text does not jump.

**AI toggle.**
- A bordered button with the `sparkles` symbol and the word "AI".
- On: `.bvAccentSoft` fill and an accent focus ring of about 3 pt.
- Off: no fill and no ring.
- State: a new setting replaces `ScratchpadSettings.bottomBar`, a Bool named
  `aiBarShown`, defaulting to false.
  - It is decoded with a default, so old settings files load.
  - The old `bottomBar` key is ignored on read and dropped on the next save.
- `openScratchpadAsk` sets it to true instead of `bottomBar = .ai`.
- The `ScratchpadBottomBar` enum is deleted, and its tests are rewritten for
  `aiBarShown`.
- Shortcuts are unchanged: ⌘↩ stays Copy and close, ⌘⇧C stays Copy, and Esc
  and ⌘1–⌘3 stay in the AI bar. Running ⌘1–⌘3 while the bar is hidden shows
  the bar first, so the reply has a place.

**Bottom area, top to bottom:** the AI reply (Insert / Dismiss), the listening
bar while dictating into the note, and the AI bar.
- The listening bar shows whatever the toggle state.
- Turning the toggle off hides the AI bar and any pending reply. Neither is
  dismissed, and both come back when the toggle is turned on again.
- An Ask answer (`AskAnswerView`) still replaces the body, as today, whatever
  the toggle state.

**Formatting bar.**
- Disabled while an Ask answer covers the body.
- Same `MarkdownToolbar` commands and shortcuts as today: ⌘B, ⌘I, ⌘U, ⌘K and
  the rest.
- Background `.bvCard`, with a 1 pt separator line above and below.
- It wraps to a second line when the window is narrow, and never scrolls
  sideways.
- The table popover uses `arrowEdge: .bottom`.

**Tool row.**
- Uses the folder menu and `TagField` from the existing `LabelsBox`, without
  the "Folder" and "Tags" captions.
- When the window is too narrow for one line, the right group (mic, history,
  Trash, Copy) moves to a second line, right aligned. The AI toggle, folder
  and tags stay on the first line.
- The tags wrap inside their own space.

**List right-click.** It uses the same `AppModel` calls as the Scratchpad page
context menu (`setNotePinned`, `setNoteLabels`, `deleteNote`). It is the same
menu as `NotesPage.card`, minus Edit, because a click already opens the note.

**Compact mode** (Smaller) keeps the same rows. It already hides the side
list. The tool row and the Formatting bar wrap at the 420 pt window minimum.

**Logo.** The image is 16 pt and template-free, so it keeps its colours. It is
hidden from VoiceOver, as today.

## Constraints

- macOS 15 floor, Swift 6, no new dependencies.
- Tokens only. `Scripts/check-tokens.sh` must pass.
- The settings change is in VoiceCore. It needs a test first: an old file with
  `"bottomBar": "ai"` decodes, and `aiBarShown` defaults to false.
- UI copy is plain English, with no hedging words and no emoji.

## Calls I made (owner to check)

- In Doc view the Formatting bar shows the read-only line in its place rather
  than disappearing, so the layout does not shift.
- The AI bar starts hidden for everyone after the update, including people
  whose last state was AI.
- Narrow windows: the right-hand tools wrap to a second line instead of
  shrinking.
- The list menu leaves out "Edit" and "Open in new tab", because a click
  already opens the note in a tab.
- ⌘↩ stays Copy and close. Only ⌘1–⌘3 and the Ask entry points show the
  hidden AI bar.
- Turning AI off hides a pending reply without dismissing it.
- Compact mode keeps the Formatting bar.
- The Formatting bar is disabled while an Ask answer covers the note.

## Left to the builder

- File split inside `UI/Scratchpad/`, for example a `ScratchpadToolRow` view.
- Whether the logo comes from `BrandImages` or `IconImages`.

## Manual checks

1. The floating window matches the mockup in light and dark, at 100% and 160%
   text.
2. AI toggle off: no AI bar and no ring. On: a ring and the AI bar. ⌘1 with it
   off shows the bar and runs Polish. ⌘↩ still copies and closes.
3. In Markdown view the Formatting bar works, and the table picker opens below.
   In Doc view the read-only line shows.
4. Every row of the table works from its new place.
5. Right-click a list note: each item works, and Trash asks first.
6. A narrow window wraps the tool row as described, with nothing clipped.
7. On the Scratchpad page, "Open Scratchpad editor" in the title row opens the
   note.
8. A settings file from before the update loads with AI off.
