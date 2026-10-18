# App shell execution log

Branch: `feat/app-shell`. Phase B is implemented directly, as authorized by the owner; no merge or push.

## Task 4 — Window frame

- Builder's call: a fixed SwiftUI HStack keeps the sidebar separate from the right-panel title bar without introducing a draggable split.
- Builder's call: `PageActions` in the shell will switch on the current page (Task 5); shared action state lives in AppModel. This avoids type-erased view preferences and their update cycles.
- Sidebar uses caption, secondary, uppercase group headings, selected traits, keyboard arrows, hover, and a scrolling minimum-height stack that lets Settings/Help follow the groups at short heights.
- Window-button clearance is measured from the actual zoom-button frame; hidden sidebar uses the same measurement.
- Window minimum follows ShellLayout and text-scale changes.
- Validation: swift build, swift test, Scripts/check-tokens.sh pass.
- Runtime limitation: the UI tool returned “Computer Use was not approved to use BugVoice”. It cannot operate this app for clicks/shortcuts. Browser opening of the local mockup was blocked by URL policy; HTML source was read. No visual pass is inferred from builds.
- Signed app build and dev launch passed. CGWindowListCopyWindowInfo reported no visible BugVoice window after launch; no Task 4 screenshot could be captured without UI access. Shown/hidden clearance, close/reopen, drag/zoom, and sidebar scrolling remain runtime checks.

## Task 5 — Page actions

- Task 4 commit: `b77d453` — feat(app): two-panel window with grouped sidebar and title bar.
- Builder's call: split buttons use two adjoining controls, an accent primary button and a caret Menu, so the primary action is explicit on macOS 15.
- `PageActions` switches on Page; Insights range and Dictionary selection/add request live in AppModel. Page headings and relocated controls were removed.
- Preserved Meetings Stop/Transcribing in the title bar, Upload browse in the drop zone and queue/error recovery actions, and Scratchpad Open window in the New note menu.
- Ask AI reuses ScratchpadAssistant.changeScope(.all), the existing AI bottom bar, and per-note assistants, with a question focus request.
- Validation: swift build, swift test (910 VoiceCore + 30 MCPKit + 94 BugVoiceMac), token check pass. Action/menu click checks are blocked by denied UI access; none are claimed passed.
- Signed app build/dev launch passed. Also corrected window-button height measurement for flipped NSHostingView coordinates during action-slot review. No UI interaction or screenshots were possible.

## Task 6 — Round pills

- Task 5 commit: `e323c99` — feat(app): page actions in the title bar.
- Builder's call: a SwiftUI Layout measures the widest intrinsic pill and wraps whole pills; each row divides its width equally, including the final row. This preserves equal widths with multiline fallback for a single exceptionally long label.
- RoundPills now lives in Components; AppearanceCard stays in SettingsComponents. PillTabs is deleted. Dictation style filter preserves day grouping; empty filtered results have their own empty state.
- Editing line spacing/reading width use the specified square segmented controls. Speech, floating Scratchpad, and meeting-window controls remain their existing tools.
- Validation: swift build, swift test (1,034 tests), token check, signed debug app build and dev launch passed. Required 160% screenshots for Insights, Dictation, Dictionary and meeting pills remain blocked by UI access; no wrapping visual pass is claimed.

## Task 7 — Centered columns and section lists

- Task 6 commit: `e78b130` — feat(app): one round pill control for views and filters.
- Builder's call: `bvPageColumn` uses a single-child SwiftUI Layout. It consumes the full scroll-view width, applies ShellLayout.blockWidth, and places the block on the centerline without GeometryReader height feedback.
- Settings and Style use vertical in-page section lists. Settings tabs share the page's one scroll view; nested settings scroll views were removed so the scrollbar stays at the right-panel edge.
- Builder's call: Models feature controls stack label, engine, model, thinking/effort, timeout, and status vertically. Their prior six-column Grid could not fit the minimum content column at large text. All controls remain available. Connections/CLI rows also stack; CLI paths have middle truncation, help, and Reveal.
- Storage preserves every clear/reset/retention action. Paths have middle truncation, full-path help and Reveal; metadata uses ViewThatFits with stacked fallback.
- Phase A review fix: Integrations is one AttributedString Text with the inline Settings › Agents link handled locally by OpenURLAction, so the sentence wraps.
- Validation: swift build, swift test (1,034 tests), token check, signed debug build and dev launch pass.
- **Not verified:** the requested Models, Storage, Style, Upload, Dictation matrix (100%/160%, minimum/1600 pt), Integrations link wrapping screenshot, and left/right gap measurements. UI access was denied and no visible main window was available. No screenshot paths or measured gaps are fabricated; calculated centering is not visual evidence.

## Task 8 — List panes and note preview

- Task 7 commit: `42bd90d` — feat(app): centered page columns and in-page section lists.
- Builder's call: list panes use `.bvSidebar` directly (the spec permits it), sharing the app's sidebar palette without an additional color blend.
- Meetings uses the capped list width and a full-width detail scroll view around the centered reading column. Filter controls stack; transcript line scrolling and all recovery, export, generation and More-menu actions are retained.
- Scratchpad keeps folder/tag filters, search, sort, reload, insertion-recovery Copy, and Edit/Pin/Move to folder/Trash context menus. Former hover actions are available in those menus. Folder/tags are shown in the preview.
- Selection is separate from the floating editor. The preview reads the published notes list; deletion/list reload prunes a missing selection. Double-click and Edit open the floating editor.
- MarkdownDocView has optional non-scrolling/unpadded rendering for the preview; its existing floating-window behavior defaults stay intact. Preview task checkboxes use a no-op callback.
- Validation: swift build, swift test (1,034 tests), token check, signed debug app build/dev launch pass. Select/double-click/edit/save visual checks remain unverified because UI access is denied.

## Task 9 — Global search UI

- Task 8 commit: `e0c6e74` — feat(app): list panes for meetings and notes, note preview.
- Uses the existing VoiceCore GlobalSearch ranking and SearchIndexer's local passage builders, plus all meeting/note titles (including unfinished meetings). No model or embedding requests are made by shell search.
- Builder's call: field results are a SwiftUI overlay; compact search uses a popover. Result rows scroll within a height derived from the window, so eight large-text rows do not require a panel taller than the minimum window. Keyboard selection scrolls with them.
- 150 ms debounce, detached ranking, cancellation/stale-query guards, current-page priority, arrow/Return/Escape handling, outside-click close and local settings navigation are implemented. Main-window key state gates the View commands; floating editor/sheets retain their shortcuts.
- MeetingJump.play defaults to true for existing Ask citations. Search explicitly passes false and skips consumeMeetingJump audio loading, seeking and playback, while selecting tabs/lines. Title-only results just select and clear old citation highlights. Transcript tab selection precedes the scroll request for Ask and search.
- Notes/meetings search opening clears list filters/search that would hide the target; their filtering controls remain. Dictation opening resets its style filter, scrolls and fades accentSoft over 1.5 seconds.
- Validation: swift build, swift test (910 VoiceCore/100 suites + 30 MCPKit/2 suites + 94 BugVoiceMac/16 suites), token check, signed debug app build and dev launch pass. No existing tests were edited.
- Runtime matrix remains unverified: meeting line/title/unfinished title, note, dictation, text size, Vietnamese search, search-no-play versus Ask-play, keyboard/sheet scope and VoiceOver. UI tool access remains denied. CGWindowListCopyWindowInfo again reported no visible BugVoice window after the dev launch.
