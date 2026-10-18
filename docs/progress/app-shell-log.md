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
