# Language per app and fix last paste Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pick the dictation language per app, with a menu switch, or with a key tap while recording; keep English words in Vietnamese; replace the last paste with the raw text or a redo in the other language.

**Architecture:** Every decision is a pure VoiceCore type (language resolution, key cycling, gesture input, prompts, replacement guard, history update), test first. The app wires them: Settings cards, popover switch and buttons, HUD label, the hotkey tap reporting raw key-downs, Backspace posting and global shortcuts.

**Tech Stack:** Swift 6 package, SwiftUI/AppKit, Swift Testing, WhisperKit 1.1.1 (unchanged).

**Spec:** `docs/superpowers/specs/2026-10-19-language-and-fix-last-design.md` (mockup `docs/design/proposal-language.html`). Read both before starting.

## Global Constraints

- Swift tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only.
- No new dependency.
- TDD for everything in `VoiceCore`; `swift test` passes before every commit.
- Settings decode tolerantly: a missing or bad key falls back to its default (`c.value(_, default:)`), never fails the whole file.
- UI copy: plain English, no hedging words, no emoji. Strings come from the spec and mockup.
- Build with `Scripts/build-app.sh`; run with `Scripts/run-dev-app.sh`, never a bare `open`.
- Never paste into a secure text field; the replacement uses the existing paste path and its secure check.
- Commit after each task, style `feat(core): …`, `feat(app): …`, `docs: …`. The pre-commit hook raises the build; do not edit `CFBundleVersion` by hand.
- Work on branch `feat/language-fix-last` from `main`.

## Review Focus

1. Synthetic events: BugVoice's own ⌘V and Backspaces reach the listen-only tap and must not count as "typed since the paste" (Task 6 test `syntheticEventsDoNotCountAsTyping`, Task 4 `countsAsTyping` tests).
2. Shift held before the hotkey still blocks a recording; Shift tapped during a hold does not cancel it (Task 2 tests).
3. An old `settings.json` without the new keys loads the default per-app list; a saved empty list stays empty (Task 1 tests).
4. Auto dictations get no Vietnamese example in the speech prompt (Task 3 test `autoGetsNoExample`).
5. Multi-line or long last paste is copied, never Backspaced (Task 4 test `multiLineIsCopied`).

---

### Task 1: Language rules and resolver

**Files:**
- Create: `Sources/VoiceCore/LanguageRules.swift`
- Modify: `Sources/VoiceCore/Settings.swift` (`SpeechSettings` fields and its `init(from:)`)
- Test: `Tests/VoiceCoreTests/LanguageRulesTests.swift`, `Tests/VoiceCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct AppLanguageRule: Codable, Equatable, Sendable, Identifiable {
      public enum Kind: String, Codable, Sendable { case app, website, terminalPanel }
      public var kind: Kind
      public var id: String          // bundle ID, host, or editor bundle ID for terminalPanel
      public var language: SpeechLanguage   // .en or .vi only
      public static let defaults: [AppLanguageRule]
  }
  public enum LanguageKey: String, Codable, Sendable, CaseIterable { case off, shift, option }
  // SpeechSettings gains:
  public var appLanguages: [AppLanguageRule] = AppLanguageRule.defaults
  public var showLanguageSwitch = true
  public var languageKey: LanguageKey = .shift
  public var keepEnglishWords = true
  public struct LanguageResolver: Sendable {
      public init(settings: SpeechSettings)
      /// keyChoice wins, then a non-Auto switch, then the first matching rule, then .auto.
      public func language(for focus: FocusSnapshot, keyChoice: SpeechLanguage? = nil) -> SpeechLanguage
      public func ruleLanguage(for focus: FocusSnapshot) -> SpeechLanguage?
  }
  ```
- `AppLanguageRule.defaults`, in this order: app `com.stablyai.orca` en; app `com.mitchellh.ghostty` en; app `com.apple.Terminal` en; app `com.googlecode.iterm2` en; app `dev.warp.Warp-Stable` en; terminalPanel `com.microsoft.VSCode` en; terminalPanel `com.todesktop.230313mzl4w4u92` en; app `com.anthropic.claudefordesktop` vi; website `chatgpt.com` vi.

- [ ] **Step 1: Write failing tests** in `LanguageRulesTests.swift`:
  - `defaultsMatchSpec`: `AppLanguageRule.defaults.count == 9`, Orca rule is `.en`, `chatgpt.com` rule is `.website` / `.vi`.
  - `websiteBeatsApp`: rules [app `com.google.Chrome` en, website `chatgpt.com` vi]; focus bundle `com.google.Chrome`, url `https://chatgpt.com/c/1` → `.vi`.
  - `subdomainMatches`: website `chatgpt.com`, url `https://www.chatgpt.com/` → `.vi`; url `https://notchatgpt.com/` → `.auto`.
  - `terminalPanelOnlyInPanel`: terminalPanel `com.microsoft.VSCode` en; VS Code focus with `isTerminalPanel: true` → `.en`, with `false` → `.auto`.
  - `switchBeatsRules`: `settings.language = .vi`, Orca focus → `.vi`.
  - `keyBeatsSwitch`: `settings.language = .vi`, `keyChoice: .en` → `.en`; `keyChoice: .auto` → `.auto`.
  - `unlistedAppIsAuto`: Notion focus → `.auto`.
- [ ] **Step 2: Add to `SettingsTests.swift`:**
  - `oldSettingsGetDefaultRules`: decode `{"speech":{"language":"auto"}}` → `appLanguages == AppLanguageRule.defaults`, `languageKey == .shift`, `keepEnglishWords`, `showLanguageSwitch`.
  - `emptyRuleListStaysEmpty`: decode `{"speech":{"appLanguages":[]}}` → `appLanguages.isEmpty`.
  - `badRuleIsDroppedAlone`: decode two rules, one with `"language":"xx"`, one valid → one rule kept.
  - `rulesRoundTrip`: encode then decode equals.
- [ ] **Step 3: Run** `swift test --filter "LanguageRulesTests|SettingsTests"`. Expected: fails to compile (types missing).
- [ ] **Step 4: Implement.** Decode `appLanguages` element by element (like `StyleSettings` overrides) so one bad entry drops alone; a rule whose language is not `.en`/`.vi` is dropped. Match websites with the same host rule as `StyleRouter.style(for:)` (equal or `hasSuffix("." + host)`, lowercased).
- [ ] **Step 5: Run** `swift test`. Expected: all pass.
- [ ] **Step 6: Commit** `feat(core): language per app rules and resolver`.

### Task 2: Language key in the hotkey gesture

**Files:**
- Modify: `Sources/VoiceCore/KeyEventMapper.swift`, `Sources/VoiceCore/HoldGestureDetector.swift`
- Create: `Sources/VoiceCore/LanguageKeyCycler.swift`
- Test: `Tests/VoiceCoreTests/KeyEventMapperTests.swift`, `Tests/VoiceCoreTests/HoldGestureDetectorTests.swift`, `Tests/VoiceCoreTests/LanguageKeyCyclerTests.swift`

**Interfaces:**
- Consumes: `LanguageKey` (Task 1).
- Produces:
  ```swift
  // KeyInput gains:
  case languageKeyDown(TimeInterval)
  case languageKeyUp(TimeInterval)
  // GestureAction gains:
  case languageTap
  // KeyEventMapper.map gains a parameter (default .off keeps existing callers):
  languageKey: LanguageKey = .off
  public struct LanguageKeyCycler: Sendable, Equatable {
      public init(start: SpeechLanguage)          // start = language without the key
      public private(set) var current: SpeechLanguage
      public private(set) var changed: Bool       // true after the first tap
      public mutating func tap()                  // Auto → EN → VI → Auto; from EN → VI; from VI → Auto
  }
  ```
- Mapping: with `languageKey == .shift`, flagsChanged for key codes 56/60 maps to `languageKeyDown`/`Up` (by the side bit going down/up). `.option` uses 58/61, except the key that is the hotkey itself (Right Option hotkey + Option language key: only Left Option counts). Anything else unchanged.
- Detector: in `.holding`, `.handsFree`, `.handsFreePressed`: `languageKeyDown` marks a pending tap; `languageKeyUp` with a pending tap returns `[.languageTap]`; `otherKeyDown` between them clears the pending tap and keeps today's behavior (cancel in `.holding`). In `.idle` and `.pressed`, `languageKeyDown` behaves exactly like `otherKeyDown` (chord rule unchanged) and `languageKeyUp` does nothing.

- [ ] **Step 1: Write failing tests:**
  - Mapper `shiftMapsToLanguageKey`: languageKey `.shift`, keyCode 56 flags `shift|leftShift` → `.languageKeyDown`; flags 0 → `.languageKeyUp`.
  - Mapper `shiftIgnoredWhenOff`: languageKey `.off`, keyCode 56 down → `.otherKeyDown` (today's value).
  - Mapper `hotkeyOptionNotLanguageKey`: hotkey `.rightOption`, languageKey `.option`, keyCode 61 → hotkey events; keyCode 58 → language key.
  - Detector `shiftTapDuringHoldDoesNotCancel`: hotkeyDown 0, tick 0.2 → `.startHold`; languageKeyDown 0.5 → `[]`; languageKeyUp 0.6 → `[.languageTap]`; hotkeyUp 1.0 → `[.stop]`.
  - Mapper `hotkeyWithShiftHeldIgnored`: languageKey `.shift`, hotkey `.rightControl`, keyCode 62 with flags `control|rightControl|shift|leftShift` → nil (chord rule unchanged).
  - Detector `shiftDuringPressTaints`: hotkeyDown 0, languageKeyDown 0.05, tick 0.2 → `[]`, hotkeyUp 0.3 → `[]`.
  - Detector `letterAfterShiftDownStillCancels`: holding; languageKeyDown; otherKeyDown → `[.cancel]`.
  - Detector `shiftTapInHandsFree`: start hands free by double tap; languageKeyDown/Up → `[.languageTap]`; still recording.
  - Cycler: `start .en`, tap → `.vi`; tap → `.auto`; tap → `.en`. `start .auto`, tap → `.en`. `changed` false before the first tap, true after.
- [ ] **Step 2: Run** `swift test --filter "KeyEventMapperTests|HoldGestureDetectorTests|LanguageKeyCyclerTests"`. Expected: compile failure.
- [ ] **Step 3: Implement** as above. Existing tests stay unchanged and pass.
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(core): language key taps while recording`.

### Task 3: Prompts and the pipeline language

**Files:**
- Modify: `Sources/VoiceCore/Vocabulary.swift`, `Sources/VoiceCore/PromptBuilder.swift`, `Sources/VoiceCore/DictationPipeline.swift`
- Test: `Tests/VoiceCoreTests/VocabularyTests.swift`, `Tests/VoiceCoreTests/PromptTests.swift`, `Tests/VoiceCoreTests/DictationPipelineTests.swift`

**Interfaces:**
- Consumes: `LanguageResolver` (Task 1).
- Produces:
  ```swift
  // Vocabulary
  public static let mixedExample = "Mình đang sửa cái module này, check lại API với neuron layer nhé."
  public func whisperPrompt(maxCharacters: Int = 600, example: String? = nil) -> String
  // PromptBuilder
  public static let keepEnglishRule = "Keep words the speaker said in English in English. Never rewrite them in Vietnamese spelling (nơ-ron, mô-đun)."
  public func systemPrompt(style:vocabulary:focus:hasPlaceholders:language: SpeechLanguage = .auto, keepEnglishWords: Bool = false) -> String
  public func request(raw:style:focus:vocabulary:modelID:disableThinking:language: SpeechLanguage = .auto, keepEnglishWords: Bool = false) -> CleanupRequest
  // DictationPipeline.run gains:
  languageChoice: SpeechLanguage? = nil   // a key choice or a forced redo language
  // DictationResult gains:
  public var requestedLanguage: SpeechLanguage   // what the pipeline asked speech-to-text for
  ```
- Rules: `whisperPrompt(example:)` puts the example first, then `", "`-joined terms; the example counts toward `maxCharacters` and is never cut; terms are cut first. Cleanup prompt adds `"The speaker spoke English."` / `"The speaker spoke Vietnamese."` when `language` is `.en`/`.vi`, and `keepEnglishRule` when `keepEnglishWords` and `language` is `.vi` or `.auto`. The pipeline resolves `LanguageResolver(settings: settings.speech).language(for: startFocus, keyChoice: languageChoice)`, passes it as `TranscriptionOptions.language`, passes `example: Vocabulary.mixedExample` only when the resolved language is `.vi` and `keepEnglishWords` is on (and vocabulary hints on, as today), and passes the resolved language and `keepEnglishWords` to `PromptBuilder.request`.

- [ ] **Step 1: Write failing tests:**
  - Vocabulary `exampleComesFirst`: terms ["Orca"], example "E" → `"E, Orca"`.
  - Vocabulary `exampleNeverCut`: maxCharacters 10, example of 9 characters, terms ["LongTerm"] → equals the example.
  - Prompt `englishLine`: `language: .en` → contains "The speaker spoke English." and not `keepEnglishRule` even with `keepEnglishWords: true`.
  - Prompt `vietnameseKeepsEnglish`: `.vi`, keep on → contains "The speaker spoke Vietnamese." and `keepEnglishRule`.
  - Prompt `autoKeepsEnglishNoLine`: `.auto`, keep on → contains `keepEnglishRule`, no "The speaker spoke".
  - Prompt `keepOffNoRule`: `.vi`, keep off → no `keepEnglishRule`.
  - Pipeline `ruleLanguageReachesTranscriber`: settings with Orca rule en; focus Orca; recording fake transcriber captures options → `language == .en`, prompt has no example.
  - Pipeline `vietnameseGetsExample`: Claude focus (default rule vi) → prompt starts with `Vocabulary.mixedExample`.
  - Pipeline `autoGetsNoExample`: Notion focus → `language == .auto`, prompt lacks the example.
  - Pipeline `choiceOverridesRule`: Orca focus, `languageChoice: .vi` → `.vi`, `result.requestedLanguage == .vi`.
- [ ] **Step 2: Run** `swift test --filter "VocabularyTests|PromptTests|DictationPipelineTests"`. Expected: compile failure.
- [ ] **Step 3: Implement** as above. Existing calls keep compiling through the defaults.
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(core): dictation language from rules, keep English words`.

### Task 4: Fix last paste logic

**Files:**
- Create: `Sources/VoiceCore/FixLast.swift`
- Modify: `Sources/VoiceCore/ShortcutSettings.swift`, `Sources/VoiceCore/History.swift`
- Test: `Tests/VoiceCoreTests/FixLastTests.swift`, `Tests/VoiceCoreTests/ShortcutSettingsTests.swift`, `Tests/VoiceCoreTests/HistoryTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum FixKind: String, Codable, Sendable { case raw, otherLanguage }
  public enum FixLast {
      /// "en" → .vi; anything else (vi, nil, zh…) → .en
      public static func otherLanguage(of detected: String?) -> SpeechLanguage
      public static let syntheticEventMarker: Int64 = 0x4256_5043   // 'BVPC', set on BugVoice's own key events
      /// False for BugVoice's ⌃⌥ shortcuts (control and option held, key code in shortcutKeyCodes) and for synthetic events.
      public static func countsAsTyping(keyCode: Int64, flags: UInt64, userData: Int64, shortcutKeyCodes: Set<Int64>) -> Bool
  }
  public struct LastInsertion: Sendable, Equatable {
      public var text: String
      public var processID: Int32
      public var at: Date
      public init(text: String, processID: Int32, at: Date)
  }
  public enum ReplacementDecision: Sendable, Equatable {
      case replace(backspaces: Int)
      case copyOnly
  }
  public struct ReplacementGuard: Sendable {
      public static let maxAge: TimeInterval = 120
      public static let maxCharacters = 500
      public private(set) var last: LastInsertion?
      public private(set) var typedSince = false
      public init()
      public mutating func recordInsertion(_ insertion: LastInsertion)   // clears typedSince
      public mutating func keyTyped()
      public mutating func clear()
      /// sameFocus: same frontmost process and same focused element (the app compares AX elements).
      public func decide(now: Date, frontProcessID: Int32, sameFocus: Bool) -> ReplacementDecision?
      // nil when nothing is recorded
  }
  // ShortcutAction gains: pasteRaw ("R", title "Paste raw"), redoOtherLanguage ("L", title "Redo in other language")
  // HistoryEntry gains: public var replacedBy: FixKind?   (encoded key "replacedBy", omitted when nil)
  // HistoryLog gains: public func replace(_ entry: HistoryEntry) throws   // same id, rewrites that line; missing id is a no-op
  ```
- `decide` returns `.replace(backspaces: last.text.count)` (Character count) only when `sameFocus`, `frontProcessID == last.processID`, `!typedSince`, `now - last.at < maxAge`, `last.text` has no `\n`/`\r`, and `last.text.count <= maxCharacters`; otherwise `.copyOnly`.

- [ ] **Step 1: Write failing tests** in `FixLastTests.swift`:
  - `otherLanguage`: "en" → `.vi`; "vi" → `.en`; nil → `.en`; "zh" → `.en`.
  - `replaceCountsGraphemes`: record "Xin chào" (precomposed) → `.replace(backspaces: 8)`.
  - `typingBlocks`: record, `keyTyped()` → `.copyOnly`.
  - `recordClearsTyping`: `keyTyped()`, then record → `.replace`.
  - `otherAppBlocks`: different `frontProcessID` → `.copyOnly`; `sameFocus: false` → `.copyOnly`.
  - `oldPasteBlocks`: `now = at + 120` → `.copyOnly`; `at + 119` → `.replace`.
  - `multiLineIsCopied`: "a\nb" → `.copyOnly`; 501 characters → `.copyOnly`; 500 → `.replace(backspaces: 500)`.
  - `nothingRecorded`: → nil.
  - `countsAsTyping`: plain "a" (keyCode 0, flags 0) → true; ⌃⌥R (keyCode 15, flags control|option, set [15, 37, 9]) → false; ⌃⌥A (keyCode 0, set without 0) → true; ⌘Z → true; userData `syntheticEventMarker` → false.
- [ ] **Step 2: Add tests:**
  - Shortcuts `newDefaults`: `letter(for: .pasteRaw) == "R"`, `.redoOtherLanguage == "L"`; old JSON without the keys decodes to them; setting `.pasteRaw` to "V" fails (taken).
  - History `replaceRewritesOneLine`: append A, B; replace B with `text: "new"`, `replacedBy: .raw` → load returns B'(new, .raw), A unchanged; JSON line for A has no `replacedBy` key.
  - History `replaceMissingIsNoOp`.
- [ ] **Step 3: Run** `swift test --filter "FixLastTests|ShortcutSettingsTests|HistoryTests"`. Expected: compile failure.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run** `swift test`. Expected: all pass.
- [ ] **Step 6: Commit** `feat(core): fix last paste guard, shortcuts and history replace`.

### Task 5: App — language settings, switch, key and HUD

**Files:**
- Modify: `Sources/BugVoice/UI/Settings/SpeechTab.swift` (Language card and Language per app card; mockup screen 1)
- Create: `Sources/BugVoice/UI/Settings/AppLanguagesCard.swift`
- Modify: `Sources/BugVoice/UI/Menu/MenuSections.swift`, `Sources/BugVoice/UI/Menu/MenuPopover.swift` (Auto · EN · VI row under the tiles when `showLanguageSwitch`; mockup screen 2)
- Modify: the status item code that draws the menu bar icon (find it with `rg -n "NSStatusItem|statusItem" Sources/BugVoice`): `EN`/`VI` badge while `speech.language` is `.en`/`.vi`.
- Modify: `Sources/BugVoice/HUD/HUDState.swift`, `Sources/BugVoice/HUD/HUDView.swift`: `.listening` gains `language: String` (`"Auto"`, `"EN"`, `"VI"`) and `languageChanged: Bool` (flash); `.transcribing(language:)` shows the resolved language name.
- Modify: `Sources/BugVoice/DictationController.swift`, `Sources/BugVoiceMac/HotkeyMonitor.swift`

**Interfaces:**
- Consumes: `AppLanguageRule`, `LanguageKey`, `LanguageResolver` (Task 1); `KeyInput.languageKey*`, `GestureAction.languageTap`, `LanguageKeyCycler` (Task 2); `DictationPipeline.run(languageChoice:)` (Task 3).
- `HotkeyMonitor` gains `public var languageKey: LanguageKey` passed to `KeyEventMapper.map`; `DictationController.applySettings()` sets it from `settings.speech.languageKey`.
- `DictationController.begin` creates `LanguageKeyCycler(start: LanguageResolver(settings:).language(for: startFocus))` and shows it in the listening HUD; `.languageTap` calls `tap()` and re-shows the HUD with `languageChanged: true` (flash once, about 0.4 s, then false); `finish` passes `cycler.changed ? cycler.current : nil` as `languageChoice`.
- Add app…: an `NSOpenPanel` on `/Applications` for `.app` bundles (read the bundle ID with `Bundle(url:)`) plus a menu of running regular apps. Add website…: a text field; store the lowercased host (strip scheme, path, `www.`). Rows show the app name from `NSWorkspace` (fallback: the ID); terminalPanel rows read "VS Code terminal" / "Cursor terminal".
- Copy, exactly from the mockup: "Auto uses the per-app list below, then detects the language. English or Vietnamese applies everywhere.", "Show language switch in menu", "Language key while recording", "Tap the key while speaking to change the language for that dictation: Auto, English, Vietnamese.", "Keep English words in Vietnamese", "Words like module, API and neuron stay in English. Add words you always say in English to the Dictionary.", "Apps not listed use Auto. The language switch overrides this list."

- [ ] **Step 1:** Implement settings cards and the per-app list editing.
- [ ] **Step 2:** Implement the popover switch row (bound to `settings.speech.language`) and the menu bar badge.
- [ ] **Step 3:** Implement the HUD language label and flash, the language key wiring, and the resolved language in the transcribing stage.
- [ ] **Step 4: Run** `swift test` and `Scripts/build-app.sh`. Expected: tests pass, build succeeds.
- [ ] **Step 5: Smoke check** with `Scripts/run-dev-app.sh`: Settings › Speech shows both cards with the 9 defaults; the popover shows the switch; setting VI shows the badge. Screenshot the BugVoice window (find its position first) and compare with mockup screens 1–2.
- [ ] **Step 6: Commit** `feat(app): language per app, menu switch and language key`.

### Task 6: App — fix last paste

**Files:**
- Modify: `Sources/BugVoiceMac/PasteboardInserter.swift`: set `eventSourceUserData = FixLast.syntheticEventMarker` on the posted ⌘V; add `public func deleteBackward(_ count: Int) async` posting Backspace (key code 51) down/up pairs with the same marker and explicit empty flags, in batches of 50 with a 10 ms pause between batches.
- Modify: `Sources/BugVoiceMac/HotkeyMonitor.swift`: `public var onKeyDown: (@MainActor (Int64, UInt64, Int64) -> Void)?` called for every keyDown with key code, flags and `eventSourceUserData`.
- Modify: `Sources/BugVoiceMac/FocusInspector.swift`: `public static func focusedElement() -> AXUIElement?` and `public static func isSameElement(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool` (`CFEqual`).
- Modify: `Sources/BugVoice/DictationController.swift`: a `ReplacementGuard` plus the focused element at insertion; `pasteRaw()`, `redoInOtherLanguage()`.
- Modify: `Sources/BugVoice/AppModel+Models.swift` (register the two shortcuts beside `.pasteLast`; `func replaceLast(_ result: DictationResult, kind: FixKind) async` updating `lastResult` and the history entry through `HistoryLog.replace`).
- Modify: `Sources/BugVoice/UI/Settings/ShortcutsSettingsView.swift` (two rows), `Sources/BugVoice/UI/Menu/MenuSections.swift` and `MenuPopover.swift` (`MenuControl.rawLast`, `.redoLast`; buttons **Raw** and **Vietnamese**/**English** in `MenuLastDictation`, hover hints with the shortcuts; mockup screen 2).
- Modify: `Sources/BugVoice/HUD/HUDState.swift`: states from the spec.

**Interfaces:**
- Consumes: Task 4 types; `DictationPipeline.run(languageChoice:)` and `requestedLanguage` (Task 3).
- After every `.inserted` ordinary dictation: `guard.recordInsertion(LastInsertion(text: result.finalText, processID: <frontmost pid>, at: Date()))` and keep `FocusInspector.focusedElement()`. Any other outcome, a notes or meeting-notes run, or a new recording start: `guard.clear()`.
- `HotkeyMonitor.onKeyDown` → `if FixLast.countsAsTyping(...) { guard.keyTyped() }`, with `shortcutKeyCodes` = the key codes of the pasteLast, pasteRaw and redoOtherLanguage letters.
- `pasteRaw()`: nothing recorded, busy or recording → HUD "Nothing to fix". `lastResult.raw == finalText` → HUD "Already raw" with detail "cleanup is off for \(style.title)" when `rawReason == .cleanupOff`. Else apply `decide`: `.replace(n)` → `deleteBackward(n)`, then `paste(raw)`, HUD "Replaced with raw text" (detail "\(words) words"), `replaceLast(kind: .raw)`; `.copyOnly` → copy, HUD warning "Copied — press ⌘V" / "text changed since the paste".
- `redoInOtherLanguage()`: missing `last.wav` → "Nothing to fix". Language = `FixLast.otherLanguage(of: lastResult.language)`. Run the pipeline on `last.wav` with `languageChoice:` that language and an `InsertionTarget` adapter whose `insert` performs the `decide` → delete-and-paste or copy above (decision taken before the run starts, and re-checked just before deleting). HUD "Replaced — Vietnamese" / "Replaced — English" with word count. Do not record insights for a replacement.
- After a replacement, `recordInsertion` with the new text so ⌃⌥R/⌃⌥L can repeat.

- [ ] **Step 1: Write a failing BugVoiceMac test** `syntheticEventsDoNotCountAsTyping` in `Tests/BugVoiceMacTests/` that builds the ⌘V and Backspace `CGEvent`s through the same helper the inserter uses (expose `static func makeKeyEvent(keyCode:keyDown:flags:) -> CGEvent?`) and asserts `getIntegerValueField(.eventSourceUserData) == FixLast.syntheticEventMarker`.
- [ ] **Step 2: Run** `swift test --filter BugVoiceMacTests`. Expected: fails.
- [ ] **Step 3: Implement** the inserter, monitor and inspector changes; run the test. Expected: pass.
- [ ] **Step 4: Implement** the controller, model, shortcuts, popover and HUD changes.
- [ ] **Step 5: Run** `swift test` and `Scripts/build-app.sh`. Expected: pass, build succeeds.
- [ ] **Step 6: Smoke check** in TextEdit with the dev app: dictate, press ⌃⌥R, see the text replaced; type a letter, press ⌃⌥R, see "Copied — press ⌘V".
- [ ] **Step 7: Commit** `feat(app): paste raw and redo in other language`.

### Task 7: Docs and device checks

**Files:**
- Create: `docs/progress/language-log.md`
- Modify: `AGENTS.md` (key documents: spec, mockup, plan, log), `docs/progress/HANDOFF.md`, `docs/ROADMAP.md`, `docs/propose-new-features.md` (mark 4 and 8 as built)

- [ ] **Step 1:** Write the log: per task what was built, test counts, deviations. Then the device checklist, each with result and evidence:
  - L1 Defaults: Settings › Speech lists the 9 default rules; an old settings file gets them.
  - L2 Orca dictation in Vietnamese speech comes out English words (rule en); the HUD shows EN.
  - L3 Claude desktop: Vietnamese with "module", "API", "neuron" keeps them in English.
  - L4 chatgpt.com in Chrome uses VI; another Chrome tab uses Auto.
  - L5 Popover switch VI: badge shows; Orca now uses VI; back to Auto removes the badge.
  - L6 Shift tap during a hold: HUD cycles EN → VI → Auto, recording continues; Shift held before the hotkey starts nothing.
  - L7 ⌃⌥R in Notion replaces cleaned with raw; ⌃⌥R in Terminal says "Already raw".
  - L8 ⌃⌥L redoes in the other language; pressing again flips back.
  - L9 Type a key after the paste, then ⌃⌥R: copied, nothing deleted.
  - L10 A multi-line dictation in Claude Code, then ⌃⌥R: copied, nothing deleted.
  - L11 History shows the replacement; Paste last pastes the replacement.
  - L12 Light and dark theme match the mockup.
- [ ] **Step 2: Run** `swift test`. Expected: all pass.
- [ ] **Step 3: Commit** `docs: language and fix last paste log and handoff`.
