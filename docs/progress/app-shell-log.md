# App shell execution log

Branch: `feat/app-shell`. Phase B is implemented directly, as authorized by the owner; no merge or push.

## Phase A (already present)

### Task 1 — ShellLayout

`4725f2c` — feat(core): shell layout widths and minimum window size.
Read before Phase B; caps, minimum widths and centered block math are reused unchanged.

### Task 2 — GlobalSearch

`0bc1ced` — feat(core): keyword search across meetings, notes, dictations, and settings.
`7d9f614` — refactor(core): drop unused search helper overload.
Read before Phase B; keyword ranking, title matching, folding and settings lookup are reused unchanged.

### Task 3 — Pages and empty states

`d4bdda4` — feat(app): integrations and help pages, sidebar groups, token empty states.
Read before Phase B; page groups and token empty states are reused. The two Phase A
review notes are addressed in Tasks 4 and 7 below.

## Task 4 — Window frame

Commit: `b77d453` — feat(app): two-panel window with grouped sidebar and title bar.

- Builder's call: a fixed SwiftUI HStack keeps the sidebar separate from the right-panel title bar without introducing a draggable split.
- Builder's call: `PageActions` in the shell will switch on the current page (Task 5); shared action state lives in AppModel. This avoids type-erased view preferences and their update cycles.
- Sidebar uses caption, secondary, uppercase group headings, selected traits, keyboard arrows, hover, and a scrolling minimum-height stack that lets Settings/Help follow the groups at short heights.
- Window-button clearance is measured from the actual zoom-button frame; hidden sidebar uses the same measurement.
- Window minimum follows ShellLayout and text-scale changes.
- Validation: swift build, swift test, Scripts/check-tokens.sh pass.
- Runtime limitation: the UI tool returned “Computer Use was not approved to use BugVoice”. It cannot operate this app for clicks/shortcuts. Browser opening of the local mockup was blocked by URL policy; HTML source was read. No visual pass is inferred from builds.
- Signed app build and dev launch passed. CGWindowListCopyWindowInfo reported no visible BugVoice window after launch; no Task 4 screenshot could be captured without UI access. Shown/hidden clearance, close/reopen, drag/zoom, and sidebar scrolling remain runtime checks.

## Task 5 — Page actions

Commit: `e323c99` — feat(app): page actions in the title bar.

- Task 4 commit: `b77d453` — feat(app): two-panel window with grouped sidebar and title bar.
- Builder's call: split buttons use two adjoining controls, an accent primary button and a caret Menu, so the primary action is explicit on macOS 15.
- `PageActions` switches on Page; Insights range and Dictionary selection/add request live in AppModel. Page headings and relocated controls were removed.
- Preserved Meetings Stop/Transcribing in the title bar, Upload browse in the drop zone and queue/error recovery actions, and Scratchpad Open window in the New note menu.
- Ask AI reuses ScratchpadAssistant.changeScope(.all), the existing AI bottom bar, and per-note assistants, with a question focus request.
- Validation: swift build, swift test (910 VoiceCore + 30 MCPKit + 94 BugVoiceMac), token check pass. Action/menu click checks are blocked by denied UI access; none are claimed passed.
- Signed app build/dev launch passed. Also corrected window-button height measurement for flipped NSHostingView coordinates during action-slot review. No UI interaction or screenshots were possible.

## Task 6 — Round pills

Commit: `e78b130` — feat(app): one round pill control for views and filters.

- Task 5 commit: `e323c99` — feat(app): page actions in the title bar.
- Builder's call: a SwiftUI Layout measures the widest intrinsic pill and wraps whole pills; each row divides its width equally, including the final row. This preserves equal widths with multiline fallback for a single exceptionally long label.
- RoundPills now lives in Components; AppearanceCard stays in SettingsComponents. PillTabs is deleted. Dictation style filter preserves day grouping; empty filtered results have their own empty state.
- Editing line spacing/reading width use the specified square segmented controls. Speech, floating Scratchpad, and meeting-window controls remain their existing tools.
- Validation: swift build, swift test (1,034 tests), token check, signed debug app build and dev launch passed. Required 160% screenshots for Insights, Dictation, Dictionary and meeting pills remain blocked by UI access; no wrapping visual pass is claimed.

## Task 7 — Centered columns and section lists

Commit: `42bd90d` — feat(app): centered page columns and in-page section lists.

- Task 6 commit: `e78b130` — feat(app): one round pill control for views and filters.
- Builder's call: `bvPageColumn` uses a single-child SwiftUI Layout. It consumes the full scroll-view width, applies ShellLayout.blockWidth, and places the block on the centerline without GeometryReader height feedback.
- Settings and Style use vertical in-page section lists. Settings tabs share the page's one scroll view; nested settings scroll views were removed so the scrollbar stays at the right-panel edge.
- Builder's call: Models feature controls stack label, engine, model, thinking/effort, timeout, and status vertically. Their prior six-column Grid could not fit the minimum content column at large text. All controls remain available. Connections/CLI rows also stack; CLI paths have middle truncation, help, and Reveal.
- Storage preserves every clear/reset/retention action. Paths have middle truncation, full-path help and Reveal; metadata uses ViewThatFits with stacked fallback.
- Phase A review fix: Integrations is one AttributedString Text with the inline Settings › Agents link handled locally by OpenURLAction, so the sentence wraps.
- Validation: swift build, swift test (1,034 tests), token check, signed debug build and dev launch pass.
- **Not verified:** the requested Models, Storage, Style, Upload, Dictation matrix (100%/160%, minimum/1600 pt), Integrations link wrapping screenshot, and left/right gap measurements. UI access was denied and no visible main window was available. No screenshot paths or measured gaps are fabricated; calculated centering is not visual evidence.

## Task 8 — List panes and note preview

Commit: `e0c6e74` — feat(app): list panes for meetings and notes, note preview.

- Task 7 commit: `42bd90d` — feat(app): centered page columns and in-page section lists.
- Builder's call: list panes use `.bvSidebar` directly (the spec permits it), sharing the app's sidebar palette without an additional color blend.
- Meetings uses the capped list width and a full-width detail scroll view around the centered reading column. Filter controls stack; transcript line scrolling and all recovery, export, generation and More-menu actions are retained.
- Scratchpad keeps folder/tag filters, search, sort, reload, insertion-recovery Copy, and Edit/Pin/Move to folder/Trash context menus. Former hover actions are available in those menus. Folder/tags are shown in the preview.
- Selection is separate from the floating editor. The preview reads the published notes list; deletion/list reload prunes a missing selection. Double-click and Edit open the floating editor.
- MarkdownDocView has optional non-scrolling/unpadded rendering for the preview; its existing floating-window behavior defaults stay intact. Preview task checkboxes use a no-op callback.
- Validation: swift build, swift test (1,034 tests), token check, signed debug app build/dev launch pass. Select/double-click/edit/save visual checks remain unverified because UI access is denied.

## Task 9 — Global search UI

Commit: `8ed1eeb` — feat(app): search everything from the title bar.

- Task 8 commit: `e0c6e74` — feat(app): list panes for meetings and notes, note preview.
- Uses the existing VoiceCore GlobalSearch ranking and SearchIndexer's local passage builders, plus all meeting/note titles (including unfinished meetings). No model or embedding requests are made by shell search.
- Builder's call: field results are a SwiftUI overlay; compact search uses a popover. Result rows scroll within a height derived from the window, so eight large-text rows do not require a panel taller than the minimum window. Keyboard selection scrolls with them.
- 150 ms debounce, detached ranking, cancellation/stale-query guards, current-page priority, arrow/Return/Escape handling, outside-click close and local settings navigation are implemented. Main-window key state gates the View commands; floating editor/sheets retain their shortcuts.
- MeetingJump.play defaults to true for existing Ask citations. Search explicitly passes false and skips consumeMeetingJump audio loading, seeking and playback, while selecting tabs/lines. Title-only results just select and clear old citation highlights. Transcript tab selection precedes the scroll request for Ask and search.
- Notes/meetings search opening clears list filters/search that would hide the target; their filtering controls remain. Dictation opening resets its style filter, scrolls and fades accentSoft over 1.5 seconds.
- Validation: swift build, swift test (910 VoiceCore/100 suites + 30 MCPKit/2 suites + 94 BugVoiceMac/16 suites), token check, signed debug app build and dev launch pass. No existing tests were edited.
- Runtime matrix remains unverified: meeting line/title/unfinished title, note, dictation, text size, Vietnamese search, search-no-play versus Ask-play, keyboard/sheet scope and VoiceOver. UI tool access remains denied. CGWindowListCopyWindowInfo again reported no visible BugVoice window after the dev launch.

## Task 10 — Shortcuts, docs and handoff

Commit: this documentation commit, `docs: app shell log and handoff` (resolve with
`git log -1 --format='%h %s' -- docs/progress/app-shell-log.md`; its own hash cannot be embedded in itself).

- Search and sidebar shortcut rows are no longer marked coming.
- AGENTS lists the plan and execution log. HANDOFF records implementation on the feature branch,
  with merge/push and runtime passes explicitly unclaimed. Appearance's Models/Storage and
  system empty-state items point to the implementation and pending screenshot gate.
- No existing tests were changed; no new VoiceCore logic or dependencies were introduced in Phase B.
- Final validation: swift build, swift test (910 VoiceCore/100 suites, 30 MCPKit/2 suites,
  94 BugVoiceMac/16 suites; 1,034 total), Scripts/check-tokens.sh all pass.

## Screenshots and gap measurements

Screenshot directory: `build/screenshots/app-shell/` (empty).

No screenshots were captured. The UI tool denied BugVoice access, and the permitted
CGWindowListCopyWindowInfo script found no visible BugVoice window after dev launches.
The required `screencapture -l <windowID>` command therefore had no target. In particular,
Task 7 has **no measured left/right gaps** at any of the requested sizes. Geometry code
and passing ShellLayout tests do not substitute for screenshot measurements.

Required outstanding captures: Task 4 sidebar shown/hidden at 100%; Task 6 Insights,
Dictation, Dictionary and a meeting at 160%; Task 7 Models, Storage, Style, Upload and
Dictation at 100% and 160%, minimum and 1600 pt widths, plus Integrations at 160% minimum.

## Data and environment

- Original settings copied to `~/Library/Application Support/BugVoice/settings.json.bak-app-shell`
  before app builds/launches. Original text scale was 100%.
- Dev app stopped before final settings restore; `cmp` is silent (exit 0), confirming byte-for-byte restore.
- No notes, meetings, or history were intentionally created, edited or deleted during runtime checks.
- `.vscode/` was pre-existing and left untracked. No merge or push was performed.
- The local HTML mockup's requested functions/CSS were read from disk; opening its file URL
  in the browser was blocked by tool URL policy. No alternate browser path was attempted.

## Remaining limitations

- 160% minimum-window and 100% 1600 pt fit have not been visually verified. Clipping/overlap
  status is unknown; this branch is not declared to pass the spec's first anti-goal.
- Action/menu execution, drag/zoom, sidebar persistence/clearance, search and Ask playback,
  text-size keyboard checks, VoiceOver, and floating-editor preview refresh need runtime checks.
- The spec's full feature/runtime matrix remains an owner gate; automated checks cover the existing
  pure logic and package suites, not SwiftUI event routing or rendered geometry.

## Review (Claude, 2026-10-18)

Built and ran the branch, captured the main window with `screencapture -l`, and
clicked through every page at 100% (1637 × 1005) and at 160% on the minimum window.

Fixed in the review commit:
- **Crash** on Style, Settings, Integrations, and Help: `ShellTitleLayout` read
  `subviews[2]`, but a page with no action supplied no third subview. The action
  slot is now always wrapped in one `HStack`.
- **Window minimum not enforced**: a drag shrank the window to 586 × 417 at 160%.
  `NSHostingController` overwrote `contentMinSize`; now `sizingOptions = []` and
  `windowWillResize(_:to:)` clamps to the minimum. `updateMinimum` also grows the
  height to 560. Checked: at 160% the window stops at 1048 × 560.
- **Compact search** (icon at narrow widths): the popover's field never took focus,
  so typing was lost, and the popover was a fixed 420 pt (scaled) tall, opened
  upward, and clipped. It now has its own focus state, opens below the icon, and
  sizes to its content.
- Insights range pills now read 7 days, 30 days, All time (spec order).
- Meetings pane filters are left-aligned like the Scratchpad pane.

Seen working: grouped sidebar, window buttons above the brand, title bar actions per
page, centered columns (left gap = right gap on Dictation, Insights, Upload, Settings),
Settings section list, Style section list, round pills wrapping at 160%, Scratchpad
list plus preview, Coming soon pages with the wrapping Agents link, ⌘K search with
Vietnamese folding ("tieng viet"), opening a meeting result on the right tab without
playing audio, ⌘K in the floating Scratchpad not raising the main window.

Still open:
- The split button's menu half draws as a plain button, not primary colored
  (macOS styles `Menu` its own way). Cosmetic.
- Not exercised: VoiceOver, ⌃⌘S persistence across relaunch, the preview refreshing
  after a floating-window save, Ask AI menu item, Dictionary Add menu.

## Manual checks (owner)

- [ ] Sidebar groups and order match the mockup; Settings and Help at the bottom.
- [ ] Each page's title-bar action works, including menu items.
- [ ] ⌘K search finds a meeting line, a meeting by title, a note, a dictation, and "text size".
- [ ] ⌃⌘S and the button hide and show the sidebar; state kept after relaunch.
- [ ] Content centered at 100% and 160%, window narrow and wide.
- [ ] Integrations and Help show Coming soon; the Agents link works.
- [ ] VoiceOver reads sidebar groups, pills, and search results.
- [ ] Scratchpad: select a note, see the preview; Open in window edits it; the preview shows the edit after it saves.
