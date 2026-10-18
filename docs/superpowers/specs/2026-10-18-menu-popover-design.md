# Menu bar popover — design

Date: 2026-10-18. Status: approved by owner 2026-10-18.
Mockup: `docs/design/proposal-menu.html` (four states). The agreed layout is
also in `docs/design/proposal-appearance.html` (Menu bar surface).
Earlier decision: appearance foundation spec, "Menu bar" (option 2).

## Why

The menu bar menu is a native `NSMenu` (`MenuBarExtra` with `.menu` style).
It ignores the app's text size, font and theme, it is a long flat list, and
the things used most (new note, record, paste last) sit among settings
toggles. The owner chose option 2: a small control panel that follows the
appearance settings and puts the common actions first.

## Goals

- Replace the native menu with a popover in the agreed order:
  1. Status line.
  2. Four buttons in a 2 × 2 grid: New note, Record meeting, Upload, Paste last.
  3. Last dictation: app, time, up to three lines of text, Copy and Retry.
  4. Library ›, Dictation options ›.
  5. Open BugVoice ⌃⌥B, Settings… ⌘,, Tools ›, Quit BugVoice ⌘Q.
- It follows the theme (colours, light/dark). Text size and font family do
  not apply: the popover keeps a fixed size and the system font at 100%
  (owner decision, 2026-10-18).
- Nothing the current menu can do is lost (table below).
- Usable from the keyboard alone and with VoiceOver.

## Non-goals

- The recording HUD (the pill shown while dictating). Unchanged.
- New features in the menu. Every action already exists in `MenuContent`.
- The menu bar icon itself. Unchanged (`MenuBarIcon`, badge dot).
- The editor in the main window. Separate round.

## Anti-goals

- A popover that steals typing from the app the owner works in after it closes.
  When it closes, focus returns to the app that was frontmost.
- Hedged or long copy. UI copy rules apply: plain English, no emoji.

## Where every current item goes

| Current menu item | Popover |
|---|---|
| Status line (all states) | Status line |
| Last · app · time, text | Last dictation block |
| Paste last ⌃⌥V | Grid button Paste last |
| Retry last recording | Last dictation › Retry |
| Meeting start / pause / resume / mark / stop, "Transcribing meeting…" | Grid button Record meeting / Stop meeting, plus a meeting strip under the status line |
| New note ⌃⌥N | Grid button New note |
| Open BugVoice… ⌃⌥B | Open BugVoice |
| "<shortcut>: used by another app" | Orange line under the status line, one per shortcut |
| Clean up with language model, Hands-free, Language, Dictation model | Dictation options › |
| Meetings…, Scratchpad page, Scratchpad… (floating) | Library › Meetings, Scratchpad, Floating scratchpad ⌃⌥N |
| Settings… ⌘, | Settings… |
| Permissions…, Open data folder | Tools › |
| Quit BugVoice ⌘Q | Quit BugVoice |
| (new) Upload | Grid button Upload: opens the main window on Upload |
| (new) Copy last | Last dictation › Copy (`DictationController.copy`) |

## Behaviour

**Status line.** A coloured dot, a bold line and a smaller second line. Same
states, same order of priority as today's `MenuContent.status`:

| State | Dot | Text | Button |
|---|---|---|---|
| Permissions missing | orange | Needs permissions · lists what is off | Fix… opens Permissions |
| Secure input on | orange | Secure input is on · <app> · hotkey paused | none |
| Listening | red | Listening… | none |
| Speech model downloading | orange | Speech model downloading · 40% | none |
| Speech model loading | orange | Speech model loading | none |
| Speech model failed | orange | Speech model failed to load | Retry |
| Hotkey not active | orange | Hotkey not active | Fix… (today's action) |
| Meeting recording or paused | red | Recording a meeting / Meeting paused | none |
| Ready | green | Ready to dictate · Hold <hotkey> to speak · release to paste | none |

Meeting rows sit just above Ready: a problem with dictation still shows first.

**Meeting strip.** Shown only while a meeting is recording, paused or
transcribing, under the status line:
- Recording: elapsed time (`MeetingController.elapsed`, m:ss or h:mm:ss),
  Pause, Mark moment, Stop.
- Paused: time stops, Pause reads Resume.
- Transcribing: "Transcribing meeting…", no buttons.
The second grid button reads Stop meeting (recording colour) while recording
or paused, and Record meeting, disabled, while transcribing.

**Last dictation.** Shown when `model.lastResult` has text. Footnote "Last
dictation · <app or Unknown> · <time>", the text in the reading font clipped
to three lines, Copy and Retry. With no last dictation the block and its
separator are gone and Paste last is disabled.

**Submenus.** Library, Dictation options and Tools replace the popover's
list in place, with a "‹ Back" header and the submenu title. Back, Left
arrow or Escape returns to the main list. Choosing a language or text model,
or flipping a switch, keeps the submenu open so the owner sees the change.
- Dictation options: Clean up with the text model (switch), Hands-free
  (double-tap the hotkey) (switch), Language group (Auto, Vietnamese,
  English, one checked), Text model group (each connection, Apple
  Intelligence when available, None, one checked).
- Library: Meetings, Scratchpad, Floating scratchpad ⌃⌥N.
- Tools: Permissions…, Open data folder.

**Closing.** Any action that opens a window, starts something, pastes or
copies closes the popover first. Toggling a switch, choosing an option,
entering or leaving a submenu, and the meeting strip's Pause / Resume / Mark
moment do not. Clicking outside closes it. Escape on the main list closes it.
Paste last must close the popover and give focus back to the previous app
before it pastes, so the text lands where the cursor was.

**Shortcut hints.** ⌃⌥B, ⌃⌥N, ⌘, and ⌘Q show on the right of their rows as
hints. ⌃⌥B and ⌃⌥N are the app's existing global shortcuts. ⌘, and ⌘Q work
while the popover is open.

**Size and look.** Fixed width 330 pt. Text size and font family settings
do not change it: the popover renders at 100% scale in the system font, and
only the theme colours follow the app. Card colour, separator lines, 14 pt
corners (`largeCardRadius`), a shadow. Fonts at 100%: status bold line
`.bodyStrong`, secondary lines `.footnote`, rows and buttons `.body`, last
dictation text `.reading`. Spacing from `LayoutTokens.spacing`. The popover
grows downward with its content and scrolls if taller than the screen below
the menu bar.

**Keyboard.** When it opens, no row is highlighted. Down arrow highlights the
first control; Up and Down then move through every control in reading order
(grid left to right, top to bottom), wrapping at the ends. Return or Space
runs the highlighted control. Right arrow on a › row opens it. Tab and
Shift-Tab move the same way. Mouse hover moves the highlight.

**VoiceOver.** The popover is one container labelled "BugVoice menu"
(submenus: their title). The status line is read first as one element
("Ready to dictate, hold Right Option to speak"). Buttons read their label;
switches read "on" or "off"; checked options read "selected"; › rows read
"submenu". The last dictation reads app, time and full text.

## Constraints

- macOS 15 floor, Swift 6, no new dependencies.
- Colours, fonts and spacing only from the foundation tokens;
  `Scripts/check-tokens.sh` must pass.
- No new VoiceCore logic is needed. If any is added (for example the
  status priority), it gets tests first.
- Existing behaviour is reused, not copied: every action calls the same
  `AppModel` / `DictationController` / `MeetingController` method the native
  menu calls today.

## Calls I made (owner to check)

- Submenus open in place with Back, instead of a second popover beside the
  first. One surface is simpler to keep keyboard and VoiceOver right.
- The Dictation model picker is titled "Text model", matching "Clean up
  with the text model".
- Upload and Copy are new entry points to existing actions (the agreed
  layout shows them).
- The meeting strip under the status line (not in the first mockup) holds
  Pause and Mark moment, which the agreed layout had no place for.
- Retry in the last dictation block is today's "Retry last recording".

## Left to the builder

- How the popover is hosted: `MenuBarExtra` with `.window` style, or an
  `NSStatusItem` with an `NSPanel`/`NSPopover`. Pick whichever can close on
  demand, return focus to the previous app, and take keyboard focus on open.
  Keep the View menu commands working (today they hang off the
  `MenuBarExtra` scene).
- File layout under `Sources/BugVoice/UI/Menu/`.

## Manual checks

1. Open from the menu bar, light and dark: matches the mockup. At 160% text
   or another font family, the popover looks the same as at 100%.
2. Every row of the table above works from the popover.
3. Paste last pastes into the previously focused app.
4. Keyboard only: Down, Up, Return, Right into a submenu, Escape out, Escape closes.
5. VoiceOver reads the status line, buttons, switches and submenus as above.
6. Start a meeting: strip with time, Pause/Resume, Mark moment, Stop.
7. Permissions off: orange status with Fix…; Paste last disabled with no dictation.
