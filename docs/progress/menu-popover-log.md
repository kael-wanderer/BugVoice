# Menu popover execution log

Branch: `feat/menu-popover`. Not merged or pushed.
Spec: `docs/superpowers/specs/2026-10-18-menu-popover-design.md`. Mockup: `docs/design/proposal-menu.html`.

## Tasks

### Task 1 — Menu status priority and copy
`596c892` — feat(core): menu status priority and copy.

### Task 2 — Menu keyboard highlight
`afe0c8e` — feat(core): menu keyboard highlight.

### Task 3 — Panel host and main list
`0751ce9` — feat(app): menu bar popover replaces the native menu.
Owner decision `f7844d4` (docs): the popover keeps a fixed size (330 pt, system font, 100%); only theme colours follow the app.
Fixes: `8a5a87e` fixed size, closes only on outside click; `081bb61` closes when another app activates or the Space changes.
The popover is an `NSStatusItem` plus a non-activating `NSPanel`. `MenuBarExtra` stays as a hidden scene that holds the View menu commands. `UI/MenuContent.swift` is deleted.

### Task 4 — Submenus
`34322c4` — feat(app): popover submenus for library, dictation options and tools.
Fix `e1e202e`: the popover opens on the main list every time.

### Task 5 — Keyboard and VoiceOver
`7f3cc25` — feat(app): popover keyboard navigation and VoiceOver.

### Task 6 — Log and manual checks
`74e8179` (log), plus the wording fix commit `docs: menu popover log wording`.

## Verification

`swift test` passes (925 VoiceCore, 30 MCPKit, 94 BugVoiceMac). `Scripts/check-tokens.sh` exits 0 with an empty allow list.
All runtime checks used the second (non-primary) display's menu bar icon, at about global (3978, 15).
Settings were backed up before each run and restored byte for byte (`cmp` silent). Screenshots: `.superpowers/sdd/2026-10-18-menu-popover/task-6-shots/` (`dark.png`, `light160serif.png`); earlier ones in `task-3-shots/`.

## Manual checks

Agent column: what the agent ran in the dev app. Boxes are for the owner.

- [ ] 1. Light and dark match the mockup (`docs/design/proposal-menu.html` state 1; the comparison with the mockup is left to the owner); 160% text and Serif look the same as 100%.
  Agent: compared a 330 x 300 pt panel in the system font at dark (nord) 100% and at light (bv-light) 160% Serif; size and font are the same. Not compared against the mockup.
- [ ] 2. Every row of the table works from the popover.
  Agent: passed for New note, Upload, Open BugVoice, Settings…, Library > Meetings, Tools > Permissions…, Tools > Open data folder, both switches, Language and Text model choices, Paste last (seeded dictation), Back. Not verified: Library > Scratchpad, Floating scratchpad (avoided on purpose), Record meeting, Quit by click, Retry, Copy, Fix…, Upload with a file. Quit was only checked through ⌘Q.
- [ ] 3. Paste last pastes into the previously focused app.
  Agent: passed in TextEdit with a seeded dictation (Task 3). Owner: check once with a real dictation.
- [ ] 4. Keyboard only: Down, Up, Return, Right into a submenu, Escape out, Escape closes.
  Agent: passed (Task 5): Down, Up wrap, Tab and Shift-Tab, Return toggles a switch, Right opens a submenu, Left and Escape go Back, Escape closes (re-checked here), Return on a › row opens the submenu with no row highlighted and Right highlights its first row (both follow the spec, which only says Return runs the control), disabled Paste last is skipped, ⌘, and ⌘Q work.
- [ ] 5. VoiceOver reads the status line, buttons, switches and submenus.
  Agent: the accessibility tree matches (container "BugVoice menu", status as one element, switches with on/off, checked rows selected, › rows "submenu"). VoiceOver speech itself was not heard. Owner: turn VoiceOver on (⌘F5) and listen. Group headers show in capitals; VoiceOver reading not checked.
- [ ] 6. Start a meeting: strip with time, Pause/Resume, Mark moment, Stop.
  Not verified. Recording starts real audio capture, so the agent did not run it. Owner check.
- [ ] 7. Permissions off: orange status with Fix…; Paste last disabled with no dictation.
  Agent: Paste last is disabled with no dictation (passed). The orange Fix… state was not verified; permissions were left as granted. Owner check.

## Also left to the owner

- Switching Spaces closes the popover. This could not be automated (no Space-change notification fired from synthetic keys). Try ⌃→ or a swipe with the popover open.
- The last dictation block with real text, the Fix… and Retry status buttons, and the meeting strip in a real meeting.
- Scrolling on a short screen. The panel never exceeded the screen (563 pt at most).
- Back-row highlight after leaving a submenu with the mouse (synthetic clicks could not test it).
- Return on a › row opens the submenu with no highlight; Right highlights its first row.
- An empty "Untitled" note was created in the owner's Scratchpad by the Task 3 New note check. It was left in place; delete it if unwanted.
- The status item can be reached from the primary display's menu bar too (not clicked: Record meeting would start a recording and New note would create a note).

## Data and environment

- Original settings copied before each run; restored with `cmp` identical. To check light, change the app's `theme` key together with `mode`: `theme` overrides `lightTheme`/`darkTheme`. This run changed mode, theme, text size and font on the live file for the 160% light check, then restored.
- ⌘Tab in an earlier check left Chrome frontmost.
- `.vscode/` was pre-existing and left untracked. Nothing pushed.
