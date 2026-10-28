# Usability pass (review Phase 5) — 2026-10-28

Scope: the last open Phase 5 item in
`docs/research/2026-10-27-app-review-and-improvement-plan.md`: text size,
window width, VoiceOver names, non-color status, keyboard traversal. The
other Phase 5 items shipped earlier (readiness card, test sentence, search
aliases, Permissions copy).

Method: dev app (`Scripts/run-dev-app.sh`) on the second display, text size
160% (the maximum) and the window at its minimum width (1,265 pt at 160%).
Screenshots through `orca computer`; VoiceOver names read straight from the
accessibility API (AXDescription, AXHelp) with a small script, because the
orca tree does not show descriptions. No dictation, paste or synthetic hotkey.
The owner's text size (100%) and window size were restored afterwards.

## Results at 160% and minimum width

| Area | Result |
|---|---|
| Settings, all nine tabs | Tab bar fits on one line; cards wrap text; no clipping or horizontal scroll. |
| Readiness card | Each row has a title and a sentence besides the dot; status does not rest on color. |
| Dictation page | Stat cards, style pills and history rows fit; row actions stay on the right. |
| Meetings page | List, player, tabs and transcript fit; the new line menu (…) shows. |
| Native controls | Pop-up menus, segmented controls and switches stay near their normal size beside large text. The app already sets `.controlSize(.large)` at large text; macOS menu-style pickers ignore font size. Known limit, not fixed. |

## Fixed

- **Color-only status (Settings › Models).** The connection dot under each
  "Use for" model and in Connections was a bare green, orange or grey circle,
  explained only by a tooltip. It now shows a symbol and a word: Reachable,
  Not reachable, Not tested; VoiceOver reads the full status. The coding CLI
  rows show a plain checkmark next to their existing "Found" text.
- **VoiceOver names taken from SF Symbol names.** Before: the sidebar button
  read "Split View Horizontally Left", Paste again read "Redo", Delete read
  "Trash". Added labels that match the tooltips: Hide or Show sidebar, Copy,
  Paste again, Paste the raw or cleaned version, Delete, Delete the recording,
  Choose a retry language, Back or Forward 15 seconds, Play or Pause, Search,
  Dismiss suggestions, and Line actions on the transcript line menu (which also
  gets an "Edit this line" tooltip and no menu arrow). Verified on the rebuilt
  app: the sidebar button now reads "Hide sidebar", history rows read "Copy",
  "Paste again", "Delete".

## Not checked (owner)

- **Keyboard traversal.** `orca computer` cannot take keyboard focus while the
  owner is using the Mac, so Tab order was not tested. Full Keyboard Access is
  off on this Mac (`AppleKeyboardUIMode` 0), so Tab reaches text fields and
  lists only, as macOS does by default.
- **Offline and long errors.** Covered by review check 6 (cleanup server off).

Owner check U1: turn on System Settings › Keyboard › Keyboard navigation, open
BugVoice Settings, press Tab through General and Models: every control is
reached in reading order and shows a focus ring.
Owner check U2: with VoiceOver on, move through a Dictation history row and the
Models tab: buttons read as named above; the model status reads "Reachable" or
the failure message.
