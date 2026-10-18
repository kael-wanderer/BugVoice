# Menu Bar Popover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the native menu bar `NSMenu` with a themed popover (status, 2 × 2 grid, last dictation, in-place submenus) that follows text size, font and theme.

**Architecture:** An `NSStatusItem` opens a borderless, non-activating `NSPanel` that can become key, so it takes the keyboard without activating BugVoice. When it closes, focus goes straight back to the app the owner was using, and Paste last lands there. The SwiftUI content lives under `Sources/BugVoice/UI/Menu/`. Two small pure types go in VoiceCore with tests: the status priority/copy (`MenuStatus`) and the keyboard highlight (`MenuNavigator`). The `MenuBarExtra` scene stays, not inserted, so the View menu commands keep working.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSStatusItem`, `NSPanel`), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-18-menu-popover-design.md` (mockup: `docs/design/proposal-menu.html`)

## Global Constraints

- Swift package, tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only. No new dependencies.
- TDD for VoiceCore: failing test first. `swift test` passes before every commit.
- Colours, fonts and spacing only from foundation tokens (`.bv…` styles, `.bvFont(...)`, `LayoutTokens`, `store.scaled`). `Scripts/check-tokens.sh` exits 0.
- UI copy: plain English, no hedging words, no emoji. Exact strings below are fixed.
- Every action calls the same `AppModel` / `DictationController` / `MeetingController` method the native menu calls today (`Sources/BugVoice/UI/MenuContent.swift` at e341089). Do not copy logic.
- Build with `Scripts/build-app.sh` and run with `Scripts/run-dev-app.sh`. Back up `~/Library/Application Support/BugVoice/settings.json` before running, then restore it and check with `cmp`.
- Commit after each task: `feat(core): …`, `feat(app): …`, `docs: …`, ending with the attribution line.

## Review Focus

1. **Paste last with the popover open from another app.** The text lands in that app's field, not in BugVoice, and nothing in BugVoice takes focus. (Task 3 manual step: paste into TextEdit.)
2. **The status item clicked while the popover is open.** It closes, not closes-then-reopens: the outside-click monitor and the button action must not both fire. (Task 3 step.)
3. **Text at 160% on a small screen.** The panel stops at the screen's visible bottom and scrolls, never off screen. (Task 3 step: `maxHeight` from `visibleFrame`.)
4. **A highlighted control that disappears**, e.g. Paste last becomes disabled, or the meeting strip goes away while highlighted. The next Down starts from the first control, with no crash. (Task 2 test `highlightLostWhenItemDisappears`.)
5. **A shortcut letter changed in Settings.** Hints show the configured letters (`settings.shortcuts.letter(for:)`), not hard-coded B/N. (Task 3: hints read from settings.)

---

### Task 1: `MenuStatus` in VoiceCore

**Files:**
- Create: `Sources/VoiceCore/MenuStatus.swift`
- Test: `Tests/VoiceCoreTests/MenuStatusTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum MenuSpeechState: Equatable, Sendable { case ready, downloading(Double), loading, failed }
  public enum MenuMeetingState: Equatable, Sendable { case idle, recording, paused, transcribing }
  public enum MenuTone: Equatable, Sendable { case good, warning, recording }
  public enum MenuStatusAction: Equatable, Sendable { case fixPermissions, retrySpeech, fixHotkey }
  public enum MenuStatus: Equatable, Sendable {
      case needsPermissions([String]), secureInput(app: String), listening
      case speechDownloading(percent: Int), speechLoading, speechFailed, hotkeyInactive
      case meetingRecording, meetingPaused, ready
      public static func resolve(missingPermissions: [String], secureInputApp: String?, listening: Bool,
                                 speech: MenuSpeechState, hotkeyActive: Bool, meeting: MenuMeetingState) -> MenuStatus
      public var tone: MenuTone
      public var title: String
      public func detail(hotkey: String) -> String?
      public var action: MenuStatusAction?
      public var actionTitle: String?   // "Fix…" or "Retry"
  }
  ```
  `secureInputApp` is nil when secure input is off; the caller passes `"another app"` when it is on with no owner name.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import VoiceCore

@Suite struct MenuStatusTests {
    func resolve(missing: [String] = [], secure: String? = nil, listening: Bool = false,
                 speech: MenuSpeechState = .ready, hotkey: Bool = true, meeting: MenuMeetingState = .idle) -> MenuStatus {
        MenuStatus.resolve(missingPermissions: missing, secureInputApp: secure, listening: listening,
                           speech: speech, hotkeyActive: hotkey, meeting: meeting)
    }
    @Test func priorityMatchesTheNativeMenu() {
        #expect(resolve(missing: ["Microphone"], secure: "1Password", listening: true) == .needsPermissions(["Microphone"]))
        #expect(resolve(secure: "1Password", listening: true) == .secureInput(app: "1Password"))
        #expect(resolve(listening: true, speech: .loading) == .listening)
        #expect(resolve(speech: .downloading(0.404), hotkey: false) == .speechDownloading(percent: 40))
        #expect(resolve(speech: .loading, hotkey: false) == .speechLoading)
        #expect(resolve(speech: .failed, hotkey: false) == .speechFailed)
        #expect(resolve(hotkey: false, meeting: .recording) == .hotkeyInactive)
        #expect(resolve(meeting: .recording) == .meetingRecording)
        #expect(resolve(meeting: .paused) == .meetingPaused)
        #expect(resolve(meeting: .transcribing) == .ready)
        #expect(resolve() == .ready)
    }
    @Test func copyAndTone() {
        #expect(MenuStatus.ready.title == "Ready to dictate")
        #expect(MenuStatus.ready.detail(hotkey: "Right Option") == "Hold Right Option to speak · release to paste")
        #expect(MenuStatus.ready.tone == .good)
        #expect(MenuStatus.meetingRecording.title == "Recording a meeting")
        #expect(MenuStatus.meetingPaused.title == "Meeting paused")
        #expect(MenuStatus.meetingRecording.detail(hotkey: "Right Option") == "Dictation still works · hold Right Option")
        #expect(MenuStatus.meetingRecording.tone == .recording)
        #expect(MenuStatus.listening.title == "Listening…")
        #expect(MenuStatus.listening.tone == .recording)
        #expect(MenuStatus.listening.detail(hotkey: "x") == nil)
        #expect(MenuStatus.secureInput(app: "1Password").title == "Secure input is on")
        #expect(MenuStatus.secureInput(app: "1Password").detail(hotkey: "x") == "1Password · hotkey paused")
        #expect(MenuStatus.speechDownloading(percent: 40).title == "Speech model downloading")
        #expect(MenuStatus.speechDownloading(percent: 40).detail(hotkey: "x") == "40%")
        #expect(MenuStatus.speechLoading.title == "Speech model loading")
        #expect(MenuStatus.speechFailed.title == "Speech model failed to load")
        #expect(MenuStatus.hotkeyInactive.title == "Hotkey not active")
        #expect(MenuStatus.hotkeyInactive.tone == .warning)
    }
    @Test func permissionsDetailListsWhatIsOff() {
        #expect(MenuStatus.needsPermissions(["Microphone"]).title == "Needs permissions")
        #expect(MenuStatus.needsPermissions(["Microphone"]).detail(hotkey: "x") == "Microphone is off")
        #expect(MenuStatus.needsPermissions(["Microphone", "Accessibility"]).detail(hotkey: "x") == "Microphone and Accessibility are off")
        #expect(MenuStatus.needsPermissions(["Microphone", "Accessibility", "Input Monitoring"]).detail(hotkey: "x")
                == "Microphone, Accessibility and Input Monitoring are off")
        #expect(MenuStatus.needsPermissions([]).detail(hotkey: "x") == nil)
    }
    @Test func actions() {
        #expect(MenuStatus.needsPermissions(["Microphone"]).action == .fixPermissions)
        #expect(MenuStatus.needsPermissions(["Microphone"]).actionTitle == "Fix…")
        #expect(MenuStatus.speechFailed.action == .retrySpeech)
        #expect(MenuStatus.speechFailed.actionTitle == "Retry")
        #expect(MenuStatus.hotkeyInactive.action == .fixHotkey)
        #expect(MenuStatus.secureInput(app: "a").action == nil)
        #expect(MenuStatus.ready.actionTitle == nil)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter MenuStatusTests`. Expected: build failure, `MenuStatus` not found.
- [ ] **Step 3: Implement `MenuStatus` in `Sources/VoiceCore/MenuStatus.swift`** to the interface above. Downloading percent = `Int(fraction * 100)`. Tone: ready → good; listening, meetingRecording, meetingPaused → recording; the rest → warning.
- [ ] **Step 4: Run** `swift test --filter MenuStatusTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): menu status priority and copy`.

---

### Task 2: `MenuNavigator` in VoiceCore

**Files:**
- Create: `Sources/VoiceCore/MenuNavigator.swift`
- Test: `Tests/VoiceCoreTests/MenuNavigatorTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct MenuNavigator<ID: Hashable & Sendable>: Equatable, Sendable {
      public private(set) var highlighted: ID?
      public init(highlighted: ID? = nil)
      public mutating func next(in ids: [ID])      // Down, Tab
      public mutating func previous(in ids: [ID])  // Up, Shift-Tab
      public mutating func hover(_ id: ID)
      public mutating func clear()
  }
  ```
  `ids` is the enabled controls in reading order. Disabled controls are left out by the caller.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import VoiceCore

@Suite struct MenuNavigatorTests {
    let ids = ["a", "b", "c"]
    @Test func startsWithNothingHighlighted() { #expect(MenuNavigator<String>().highlighted == nil) }
    @Test func downStartsAtFirstAndWraps() {
        var nav = MenuNavigator<String>()
        nav.next(in: ids); #expect(nav.highlighted == "a")
        nav.next(in: ids); nav.next(in: ids); #expect(nav.highlighted == "c")
        nav.next(in: ids); #expect(nav.highlighted == "a")
    }
    @Test func upStartsAtLastAndWraps() {
        var nav = MenuNavigator<String>()
        nav.previous(in: ids); #expect(nav.highlighted == "c")
        nav.previous(in: ids); nav.previous(in: ids); #expect(nav.highlighted == "a")
        nav.previous(in: ids); #expect(nav.highlighted == "c")
    }
    @Test func hoverMovesTheHighlight() {
        var nav = MenuNavigator<String>()
        nav.hover("b"); nav.next(in: ids); #expect(nav.highlighted == "c")
        nav.clear(); #expect(nav.highlighted == nil)
    }
    @Test func highlightLostWhenItemDisappears() {
        var nav = MenuNavigator(highlighted: "b")
        nav.next(in: ["a", "c"]); #expect(nav.highlighted == "a")
        nav = MenuNavigator(highlighted: "b")
        nav.previous(in: ["a", "c"]); #expect(nav.highlighted == "c")
    }
    @Test func emptyListHighlightsNothing() {
        var nav = MenuNavigator(highlighted: "a")
        nav.next(in: []); #expect(nav.highlighted == nil)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter MenuNavigatorTests`. Expected: build failure.
- [ ] **Step 3: Implement `MenuNavigator`** to the interface. A highlighted id missing from `ids` counts as no highlight.
- [ ] **Step 4: Run** `swift test --filter MenuNavigatorTests`. Expected: PASS. Then run the full `swift test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): menu keyboard highlight`.

---

### Task 3: Panel host and main list

Swaps the native menu for the popover with the main list. Submenu rows are present but inert until Task 4. Keyboard handling comes in Task 5.

**Files:**
- Create: `Sources/BugVoice/UI/Menu/MenuPanelController.swift`: status item, panel, open/close, outside click, icon.
- Create: `Sources/BugVoice/UI/Menu/MenuPopover.swift`: root view, main list, routing between main list and submenus.
- Create: `Sources/BugVoice/UI/Menu/MenuSections.swift`: `MenuStatusLine`, `MenuMeetingStrip`, `MenuActionGrid`, `MenuLastDictation`.
- Create: `Sources/BugVoice/UI/Menu/MenuRow.swift`: row components (plain row with icon and hint, submenu row with ›, switch row, check row, group header, separator).
- Modify: `Sources/BugVoice/BugVoiceApp.swift`: hide the `MenuBarExtra`, create the controller.
- Delete: `Sources/BugVoice/UI/MenuContent.swift` (`MenuBarIcon` goes too; the controller sets the image).
- Modify: `Scripts/check-tokens.sh:7`: `ALLOW=''` (MenuContent is gone).

**Interfaces:**
- Consumes: `MenuStatus`, `MenuSpeechState`, `MenuMeetingState` (Task 1). `MeetingTimeText.text(_:)` (`MeetingDetectionController.swift:250`).
- Produces:
  ```swift
  @MainActor final class MenuPanelController {
      init(model: AppModel)
      func toggle()
      func close()
  }
  enum MenuSubmenu: Hashable { case library, dictationOptions, tools }
  enum MenuControl: Hashable, Sendable {     // every highlightable control, used by Task 5
      case statusAction, meetingPause, meetingMark, meetingStop
      case newNote, meeting, upload, pasteLast, copyLast, retryLast
      case submenu(MenuSubmenu), openApp, settings, quit
      case back, item(String)                 // submenu rows; item ids are stable strings, e.g. "cleanup", "lang.vi", "engine.none"
  }
  struct MenuPopover: View { init(model: AppModel, close: @escaping () -> Void) }
  ```
  `MenuPopover` keeps `@State var submenu: MenuSubmenu?` and `@State var nav = MenuNavigator<MenuControl>()`. Every row and button takes `highlighted: Bool` (the `.focus`/`.hl` look in the mockup: `.bvHover` fill for rows, a 2 pt `.bvAccent` outline for buttons) and sets `nav.hover(id)` in `.onHover`.

- [ ] **Step 1: Write `MenuPanelController`.**
  - `NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)`. `button.action` calls `toggle()`. Image = `BrandImages.menuBar(logo: model.settings.appearance.menuBarIcon, badge: !model.permissionsGranted)`, kept current with a re-arming `withObservationTracking`. `button.setAccessibilityLabel("BugVoice")`.
  - Panel: private `MenuPanel: NSPanel` with `styleMask: [.borderless, .nonactivatingPanel]`, `canBecomeKey = true`, `canBecomeMain = false`, `level = .popUpMenu`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`, `hidesOnDeactivate = false`, `collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]`. Host the view in an `NSHostingView` wrapped in `.bvTheme(model.appearance)`. Size it from `fittingSize` and resize on intrinsic-size changes, the way `HUDController`'s `SizingHostingView` does. Call `model.appearance.attach(panel)`.
  - Position: top edge 4 pt below the status button's screen frame. Centre on the button, clamped inside `screen.visibleFrame` with an 8 pt margin.
  - `toggle()`: open if closed, else `close()`. On open: `model.refreshPermissions()`, `Task { await model.refreshSpeechState() }`, then `panel.makeKeyAndOrderFront(nil)` **without** `NSApp.activate`.
  - Close on: `NSWindow.didResignKeyNotification` for the panel, and a global `leftMouseDown`/`rightMouseDown` monitor installed while open. Remove the monitor on close. A click on the status button must only toggle once: in the monitor, ignore events whose location is inside the button's screen frame.
  - `close()`: `panel.orderOut(nil)`, remove the monitor, and reset the popover state (submenu and highlight) by giving the hosting view a fresh `MenuPopover` on each open.
- [ ] **Step 2: Write `MenuPopover` main list and `MenuSections`** to the mockup, state 1/3/4.
  - Width `min(store.scaled(330), 520)`. Padding `spacing[1]`, background `.bvCard`, 1 pt `.bvSeparator` border, corner `store.scaled(LayoutTokens.largeCardRadius)` capped at 20, shadow like `SearchResults`.
  - Wrap the content in `ScrollView` with `.frame(maxHeight:)` = the screen's visible height below the menu bar minus 16 pt, passed in by the controller as `maxHeight: CGFloat`. `ScrollView(.vertical)` with `.scrollBounceBehavior(.basedOnSize)`.
  - Fonts: status title `.bodyStrong`, secondary lines `.footnote`, rows and buttons `.body`, last text `.reading` with `.lineLimit(3)`, group headers `.caption` uppercased.
  - Status: `MenuStatus.resolve(...)` from the model, in the same order as the old `MenuContent.status`. `missingPermissions` comes from `model.permissionStatus` for `.microphone` "Microphone", `.accessibility` "Accessibility", `.inputMonitoring` "Input Monitoring", false entries only. `secureInputApp` is `SecureInputMonitor.isActive ? (SecureInputMonitor.owningAppName ?? "another app") : nil`. Speech is from `model.settings.speech.engine == .whisperKit ? model.speechState : nil`, mapped to `MenuSpeechState` (nil or loaded → `.ready`). Hotkey name is `model.settings.hotkey.displayName`. Dot colour by tone: `.bvSuccess`, `.bvWarning`, `.bvRecording`.
  - Status actions:
    - `.fixPermissions` → `close(); model.openPermissionsWindow()`.
    - `.retrySpeech` → `model.retrySpeech()`; stays open.
    - `.fixHotkey` → today's two lines (`retryHotkey`, then open Permissions if Input Monitoring is off), then close.
  - Under the status: one `.bvWarning` footnote line per `model.unavailableShortcuts` entry: `"\(shortcut) is used by another app"`.
  - Meeting strip:
    - Shown when `meetings?.isRecording`, `isPaused` or `isTranscribing`.
    - Time `MeetingTimeText.text(meetings.elapsed)` in `.bodyStrong` with `.monospacedDigit()`.
    - Buttons Pause/Resume (`pause()`/`resume()`), Mark moment (`mark()`) and Stop (`stop()`, `.bvRecording` text, closes). Pause, Resume and Mark moment stay open.
    - While transcribing: only `"Transcribing meeting…"` in `.footnote` `.bvSecondary`.
  - Grid: two columns, `spacing[1]` gaps. Buttons use `.bvBackground` fill and a `.bvSeparator` border at `LayoutTokens.controlRadius`, with SF Symbols in `.bvSecondary`:
    - New note `square.and.pencil` → `close(); Task { await model.openScratchpadWindow(newNote: true) }`.
    - Record meeting `record.circle` (`.bvRecording`) → `close(); Task { await model.meetings?.start() }`. While recording or paused it shows Stop meeting `stop.fill` (`.bvRecording`) → `close(); Task { await model.meetings?.stop() }`. While transcribing it shows Record meeting, disabled.
    - Upload `square.and.arrow.up` → `close(); model.openMainWindow(.upload)`.
    - Paste last `doc.on.clipboard` → `close()`, then `Task { try? await Task.sleep(for: .milliseconds(60)); model.dictation?.pasteLast() }`. Disabled when `model.lastResult?.finalText.isEmpty ?? true`.
  - Last dictation, when the last result has text:
    - Footnote: `"Last dictation · \(appName ?? "Unknown") · \(startedAt.formatted(date: .omitted, time: .shortened))"`.
    - Then the text.
    - Copy → `close(); model.dictation?.copy(text)`. Retry → `close(); model.dictation?.retryLast()`.
    - With no last dictation, the block and its separator are hidden.
  - Rows:
    - Library `books.vertical`, Dictation options `mic` (both ›, setting `submenu`).
    - Separator.
    - Open BugVoice `macwindow`, hint `"⌃⌥\(settings.shortcuts.letter(for: .openApp))"` → `close(); model.openMainWindow(.dictation)`.
    - Settings… `gearshape`, hint `⌘,` → `close(); model.openMainWindow(.settings)`.
    - Tools ›.
    - Quit BugVoice, hint `⌘Q` → `NSApp.terminate(nil)`.
  - Hints are `.footnote` `.bvSecondary`, right aligned.
- [ ] **Step 3: Wire the app.**
  - In `BugVoiceApp`: `MenuBarExtra("BugVoice", isInserted: .constant(false)) { EmptyView() }.commands { delegate.installViewMenu() }`.
  - In `AppDelegate`: `private var menuPanel: MenuPanelController?`, created at the start of `applicationDidFinishLaunching` after `FontRegistry.registerBundledFonts()`.
  - Delete `MenuContent.swift` and set `ALLOW=''` in `Scripts/check-tokens.sh`.
- [ ] **Step 4: Verify.**
  - `swift build`: no errors. `Scripts/check-tokens.sh`: exit 0. `swift test`: PASS.
  - `Scripts/build-app.sh`, then `Scripts/run-dev-app.sh` (settings backed up).
  - In the dev app:
    - (a) The popover opens under the icon and matches mockup state 1 in light and dark.
    - (b) Clicking the icon again closes it, and does not reopen it.
    - (c) Clicking outside closes it.
    - (d) Focus TextEdit, open the popover, click Paste last: the text lands in TextEdit (Review Focus 1).
    - (e) With the main window open, ⌘K and ⌘+ still work (View menu commands survived). If they do not, replace the hidden `MenuBarExtra` with `Window("BugVoice", id: "commands") { EmptyView() }.defaultLaunchBehavior(.suppressed).commands { … }` and check again.
    - (f) Set text size to 160%: the panel fits on screen and scrolls if needed.
    - (g) New note, Upload, Open BugVoice and Settings… each open the right window.
  - Restore settings.json and `cmp` it.
- [ ] **Step 5: Commit** `feat(app): menu bar popover replaces the native menu`.

---

### Task 4: Submenus

**Files:**
- Modify: `Sources/BugVoice/UI/Menu/MenuPopover.swift`
- Create: `Sources/BugVoice/UI/Menu/MenuSubmenus.swift`: `MenuSubmenuView` for the three submenus.

**Interfaces:**
- Consumes: `MenuSubmenu`, `MenuControl`, the row components (Task 3).
- Produces: `struct MenuSubmenuView: View { let submenu: MenuSubmenu; …; let back: () -> Void; let close: () -> Void }`.

- [ ] **Step 1: Implement the submenus** to mockup state 2. The header is a `‹ Back` button in `.bvAccent` plus the title in `.bodyStrong`. Titles are "Library", "Dictation options" and "Tools".
  - Dictation options. These stay open:
    - Switch row "Clean up with the text model" bound to `$model.settings.cleanupEnabled`.
    - Switch row "Hands-free (double-tap the hotkey)" bound to `$model.settings.handsFreeEnabled`.
    - Group "Language": check rows Auto `.auto`, Vietnamese `.vi`, English `.en`, writing `model.settings.speech.language`.
    - Group "Text model": one check row per `model.settings.models.connections` (`.connection(id)`, title `name`), then Apple Intelligence when `model.appleIntelligenceAvailable`, then None. These write `model.settings.models.dictation.engine`.
    - The switch is a small capsule: `.bvAccent` when on, `.bvSeparator` when off, with a `.bvBackground` knob.
  - Library. These close the popover:
    - Meetings → `openMainWindow(.meetings)`.
    - Scratchpad → `openMainWindow(.notes)`.
    - Floating scratchpad, hint `"⌃⌥\(letter(for: .newNote))"` → `Task { await model.openScratchpadWindow(newNote: false) }`.
  - Tools. These close the popover:
    - Permissions… → `model.openPermissionsWindow()`.
    - Open data folder → `NSWorkspace.shared.open(model.paths.root)`.
  - Item ids for `MenuControl.item`: `cleanup`, `handsFree`, `lang.auto`, `lang.vi`, `lang.en`, `engine.<connection id>`, `engine.apple`, `engine.none`, `meetings`, `scratchpad`, `floating`, `permissions`, `dataFolder`.
- [ ] **Step 2: Route in `MenuPopover`.**
  - A submenu row sets `submenu` and calls `nav.clear()`.
  - Back sets `submenu = nil` and highlights the submenu row it came from, via `nav.hover(.submenu(that))`.
- [ ] **Step 3: Verify.**
  - `swift build` and `Scripts/check-tokens.sh` pass.
  - In the dev app (settings backed up):
    - Each submenu opens in place.
    - Flipping each switch and picking each language and text model keeps the submenu open and moves the check.
    - Library and Tools rows open the right window and close the popover.
    - The native-menu behaviour from the spec table is all reachable.
  - Restore settings.json and `cmp` it.
- [ ] **Step 4: Commit** `feat(app): popover submenus for library, dictation options and tools`.

---

### Task 5: Keyboard and VoiceOver

**Files:**
- Modify: `Sources/BugVoice/UI/Menu/MenuPopover.swift`, `MenuSections.swift`, `MenuRow.swift`, `MenuSubmenus.swift`

**Interfaces:**
- Consumes: `MenuNavigator` (Task 2), `MenuControl` (Task 3).
- Produces: `func controls() -> [MenuControl]` in `MenuPopover`: the enabled controls of the visible list, in reading order.
  - Main list order: status action, meeting strip buttons, the grid (left to right, top to bottom), Copy, Retry, then the rows.
  - Submenu order: Back, then the rows.
  - Also `func activate(_ control: MenuControl)`, which runs the same closure as a click.

- [ ] **Step 1: Keys.** The root is `.focusable()`, `.focusEffectDisabled()`, `@FocusState` set true in `.onAppear`, and handles keys with `.onKeyPress(phases: .down)`:
  - Down or Tab → `nav.next(in: controls())`. Up or Shift-Tab → `nav.previous(in:)`.
  - Return or Space → `activate(highlighted)`.
  - Right on `.submenu(x)` → open it, then `nav.next` so its first row after Back is highlighted. Use `nav.hover` on the second id.
  - Left or Escape in a submenu → Back. Escape on the main list → `close()`.
  - ⌘, → Settings… action. ⌘Q → `NSApp.terminate(nil)`.
  - Keep the highlight in view with a `ScrollViewReader`: `scrollTo(id)` on change.
- [ ] **Step 2: VoiceOver.**
  - Root `.accessibilityElement(children: .contain)`, labelled "BugVoice menu", or the submenu title while a submenu is open.
  - Status: `.accessibilityElement(children: .combine)`, label `"\(title), \(detail)"` with "·" replaced by ",", read first. The Fix…/Retry button stays a separate element after it.
  - Switch rows: `.accessibilityAddTraits(.isToggle)` and value "on" / "off".
  - Check rows: `.isSelected` when checked.
  - › rows: value "submenu".
  - Last dictation: one element, label `"Last dictation, \(app), \(time), \(full text)"`; Copy and Retry stay separate.
  - Hint text and SF Symbols are `.accessibilityHidden(true)`.
- [ ] **Step 3: Verify.** In the dev app:
  - Keyboard only: Down from nothing highlights New note (or the status Fix… when shown), Up wraps to Quit, Return runs, Right opens Dictation options with Clean up highlighted, Left returns with Dictation options highlighted, Escape closes.
  - ⌘, opens Settings.
  - VoiceOver (⌘F5) reads the status line, a switch's state and "submenu" on › rows.
  - `swift build` and `Scripts/check-tokens.sh` pass.
- [ ] **Step 4: Commit** `feat(app): popover keyboard navigation and VoiceOver`.

---

### Task 6: Log and manual checks

**Files:**
- Create: `docs/progress/menu-popover-log.md`: one line per task with commit, plus the spec's seven manual checks as an owner checklist with what was verified in the dev app.
- Modify: `AGENTS.md`: add `Menu popover execution log and manual checks: docs/progress/menu-popover-log.md` under the spec line. Also modify `docs/progress/HANDOFF.md` with one line under current state: popover on `feat/menu-popover`, owner checks pending.

- [ ] **Step 1: Run the spec's manual checks 1–7 in the dev app** (settings backed up, restored and `cmp`'d). Record pass or fail per check in the log. VoiceOver and 160% go in the log as done by the agent or left for the owner.
- [ ] **Step 2: Final** `swift test` PASS and `Scripts/check-tokens.sh` exit 0.
- [ ] **Step 3: Commit** `docs: menu popover log and manual checks`.
