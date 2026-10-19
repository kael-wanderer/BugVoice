# Command Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Select text, hold the command key, speak an instruction; the text model's rewrite replaces the selection (or, with nothing selected, new text is written at the cursor), with a way to put the original back.

**Architecture:** VoiceCore gains the command key setting, the prompt, the output checks, a `CommandPipeline` that returns a ready-to-paste result without pasting, the paste-or-copy decision, and history fields; all test first. The app adds a `CommandController` with its own hotkey tap and gesture detector, the selection capture with a ⌘C fallback, and reuses the dictation HUD, paste path and fix-last guard.

**Tech Stack:** Swift 6 package, SwiftUI/AppKit, Swift Testing. No new dependency.

**Spec:** `docs/superpowers/specs/2026-10-19-command-mode-design.md` (mockup `docs/design/proposal-command.html`). Read both first.

## Global Constraints

- Swift tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only. No new dependency.
- TDD in `VoiceCore`; `swift test` passes before every commit.
- Settings decode tolerantly (`c.value(_, default:)`).
- UI copy: plain English, no hedging, no emoji; strings exactly as in the spec and mockup.
- Never paste into a secure field; never press Return; never send text off the Mac unless the user configured a remote model.
- BugVoice's own posted key events carry `FixLast.syntheticEventMarker`.
- Build with `Scripts/build-app.sh`; run with `Scripts/run-dev-app.sh`.
- Branch `feat/command-mode` from `main`; one commit per task (`feat(core): …`, `feat(app): …`, `docs: …`); the pre-commit hook raises the build.

## Review Focus

1. The ⌘C fallback must always put the user's clipboard back, also when the copy produced nothing (Task 4 tests `fallbackRestoresClipboard`, `noChangeMeansNoSelection`).
2. A selection changed during the rewrite must never be pasted over (Task 3 test `changedSelectionCopies`).
3. Model preambles and quotes must not reach the document (Task 2 tests `dropsAnnouncingLine`, `dropsWrappingQuotes`, `keepsQuotesFromSelection`).
4. The command key equal to the dictation hotkey must not create two handlers for one key (Task 1 test `conflictTurnsCommandOff`).
5. Original after a multi-line rewrite selects back instead of sending Backspaces, and refuses over 2,000 characters (Task 3 tests `selectBackAllowsNewlines`, `selectBackLimit`).

---

### Task 1: Command key setting

**Files:**
- Modify: `Sources/VoiceCore/Settings.swift` (`AppSettings`)
- Test: `Tests/VoiceCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum CommandKey: String, Codable, Sendable, CaseIterable {
      case rightOption, rightCommand, off
      public var hotkeyKey: HotkeyKey?        // .rightOption / .rightCommand / nil
      public var displayName: String          // "Right ⌥", "Right ⌘", "Off"
  }
  // AppSettings gains:
  public var commandKey: CommandKey = .rightOption
  /// .off when commandKey's key is the dictation hotkey.
  public var effectiveCommandKey: CommandKey
  ```

- [ ] **Step 1: Write failing tests:** `commandKeyDefaultsToRightOption` (old JSON without the key → `.rightOption`); `badCommandKeyFallsBack` (`"commandKey":"xx"` → `.rightOption`, rest of settings kept); `conflictTurnsCommandOff` (hotkey `.rightOption`, commandKey `.rightOption` → `effectiveCommandKey == .off`; hotkey `.rightControl` → `.rightOption`); `commandKeyRoundTrips`.
- [ ] **Step 2: Run** `swift test --filter SettingsTests`. Expected: compile failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(core): command key setting`.

### Task 2: Command prompt and output checks

**Files:**
- Create: `Sources/VoiceCore/CommandPrompt.swift`
- Test: `Tests/VoiceCoreTests/CommandPromptTests.swift`

**Interfaces:**
- Consumes: `PromptBuilder.defaultRules(for:)`, `PromptBuilder.keepEnglishRule`, `Vocabulary`, `SpeechLanguage`.
- Produces:
  ```swift
  public enum CommandPrompt {
      public static let maxSelection = 8_000
      public static let rewriteRules: String   // spec §What happens 4, first system text, verbatim
      public static let writeRules: String     // "You write text for the user. Write the text the instruction asks for. Output only the text: no preamble, no quotes, no tags, no explanation. Write in the language of the instruction unless it asks for another."
      public static func request(
          instruction: String, selection: String?, style: Style, focus: FocusSnapshot,
          vocabulary: Vocabulary, language: SpeechLanguage, keepEnglishWords: Bool,
          modelID: String, disableThinking: Bool
      ) -> CleanupRequest
  }
  public enum CommandOutput {
      public enum Rejection: Equatable, Sendable { case empty, tooLong }
      public static func sanitize(_ output: String, selection: String?) -> Result<String, Rejection>
  }
  ```
- `request`: system = rules (rewrite when `selection` is non-empty, else write) + `"App style, for tone: " + defaultRules(for: style)` + `keepEnglishRule` when `keepEnglishWords` and language is `.vi`/`.auto` + `"Spell these terms exactly: …"` when vocabulary has terms + (write only) the last 500 characters of `focus.beforeText` in `<before>…</before>` "for context only". User = `"<instruction>\n\(instruction)\n</instruction>"` plus `"\n<text>\n\(selection)\n</text>"` when rewriting; `/no_think` appended like `PromptBuilder` for qwen models with `disableThinking`. `maxTokens = min(8_192, max(512, (selection?.count ?? 0) + 1_024))`, `temperature = 0.3`.
- `sanitize`: strip think blocks and `<text>`/`<instruction>` tags (reuse `OutputSanitizer`'s regexes by extracting a shared `static func stripReasoning(_:) -> String` there), trim; drop a first line that ends with ":" and has at most 12 words when more lines follow; drop one pair of wrapping `"…"`, `“…”` or `'…'` when the selection does not itself start with that quote; empty → `.empty`; longer than `4 * (selection?.count ?? 0) + 2_000` → `.tooLong`.

- [ ] **Step 1: Write failing tests:**
  - `rewriteHasTextBlock`: selection "abc", instruction "make formal" → user contains `<instruction>\nmake formal\n</instruction>` and `<text>\nabc\n</text>`; system starts with `CommandPrompt.rewriteRules`.
  - `writeHasNoTextBlock`: selection nil, focus beforeText "Lan: join at 3?" → user lacks `<text>`; system starts with `writeRules` and contains `<before>Lan: join at 3?</before>`.
  - `emptySelectionIsWrite`: selection "" → write rules.
  - `keepEnglishOnlyForViAndAuto`: `.vi` and `.auto` contain the rule; `.en` does not.
  - `maxTokensScales`: selection of 10 characters → 1_034; nil → 1_024; 9_000 characters → 8_192.
  - `dropsAnnouncingLine`: "Here is the formal version:\nDear team," → "Dear team,"; a single line "Note: done" stays.
  - `dropsWrappingQuotes`: "\"Hello there.\"" with selection "hello there" → "Hello there."; "“Xin chào”" → "Xin chào".
  - `keepsQuotesFromSelection`: selection "\"quoted\"" and output "\"Quoted\"" → unchanged.
  - `rejectsEmptyAndTooLong`: "<think>x</think>" → `.empty`; selection "a" and output of 2_005 characters → `.tooLong`; selection nil and output of 2_000 → accepted.
- [ ] **Step 2: Run** `swift test --filter CommandPromptTests`. Expected: compile failure.
- [ ] **Step 3: Implement.** Existing `OutputSanitizer` tests must still pass after extracting `stripReasoning`.
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(core): command prompt and output checks`.

### Task 3: Command pipeline, paste decision, select-back, history

**Files:**
- Create: `Sources/VoiceCore/CommandPipeline.swift`
- Modify: `Sources/VoiceCore/DictationPipeline.swift` (`DictationResult.command`), `Sources/VoiceCore/History.swift` (`HistoryEntry.command`), `Sources/VoiceCore/FixLast.swift` (select-back)
- Test: `Tests/VoiceCoreTests/CommandPipelineTests.swift`, `Tests/VoiceCoreTests/FixLastTests.swift`, `Tests/VoiceCoreTests/HistoryTests.swift`

**Interfaces:**
- Consumes: Task 2; `LanguageResolver`; `Transcriber`, `TranscriptionOptions`, `CleanupModel`, `HallucinationFilter`, `DictationPipeline.stripPlaceholders`, `withTimeout`.
- Produces:
  ```swift
  // DictationResult gains: public var command: String? = nil
  // HistoryEntry gains: public var command: String?  (key "command", omitted when nil); historyEntry copies it
  public enum CommandFailure: Equatable, Sendable {
      case noModel, selectionTooLong, transcriptionFailed, modelFailed, outputTooLong, emptyOutput
      public var title: String
      public var detail: String?
  }
  public enum CommandRun: Equatable, Sendable {
      case ready(DictationResult)   // command, raw = original (or ""), uncleanedText = original, finalText = output, outcome not yet set
      case failed(CommandFailure)
      case nothingHeard
      case cancelled
  }
  public struct CommandPipeline: Sendable {
      public static let timeoutSeconds: Double = 30
      public init(transcriber: any Transcriber, model: CleanupModel?, settings: AppSettings, vocabulary: Vocabulary)
      public func run(clip: AudioClip, selection: String?, startFocus: FocusSnapshot, startedAt: Date,
                      languageChoice: SpeechLanguage? = nil,
                      onStage: @escaping @Sendable (PipelineStage) -> Void) async -> CommandRun
  }
  public enum CommandPasteDecision: Equatable, Sendable {
      case paste
      case copy(reason: String)
      case secure
  }
  public enum CommandPaste {
      public static let selectionChanged = "the selection changed while rewriting"
      public static let terminal = "terminals do not replace a selection"
      /// sameElement: the app compared AX elements and process IDs.
      public static func decide(start: FocusSnapshot, now: FocusSnapshot, sameElement: Bool, style: Style) -> CommandPasteDecision
  }
  // ReplacementGuard gains:
  public static let maxSelectBackCharacters = 2_000
  public enum SelectBackDecision: Equatable, Sendable { case selectBack(characters: Int), copyOnly }
  public func decideSelectBack(now: Date, frontProcessID: Int32, sameFocus: Bool) -> SelectBackDecision?
  ```
- `CommandFailure` copy, from the mockup: noModel "Command mode needs a text model" / "choose one in Settings › Models"; selectionTooLong "Selection too long" / "8,000 characters at most"; transcriptionFailed "Command failed" / "could not transcribe"; modelFailed "Command failed" / "model unavailable"; outputTooLong "The model's answer was too long" / "nothing was changed"; emptyOutput "Command failed" / "the model returned nothing".
- `run` order: no model → `.failed(.noModel)`; selection over `CommandPrompt.maxSelection` → `.failed(.selectionTooLong)`; clip shorter than 0.3 s or silent → `.nothingHeard`; transcribe with `LanguageResolver` language and Dictionary hint prompt (no example sentence, no replacements on the instruction); empty or hallucinated instruction → `.nothingHeard`; model call with `timeoutSeconds` → error or timeout → `.failed(.modelFailed)`; sanitize → `.failed(.emptyOutput/.outputTooLong)`; else `.ready`. Cancellation → `.cancelled`. Stages: `.transcribing`, `.cleaning(model:)`.
- `decide`: `now.isSecure` → `.secure`; `style == .terminal` → `.copy(terminal)`; `!sameElement` → `.copy(selectionChanged)`; when `start.selectedText` is non-nil and differs from `now.selectedText` → `.copy(selectionChanged)`; else `.paste`.
- `decideSelectBack`: same conditions as `decide` except newlines are allowed and the limit is `maxSelectBackCharacters`; returns `.selectBack(characters: last.text.count)`.

- [ ] **Step 1: Write failing tests** (`CommandPipelineTests`, fakes like `DictationPipelineTests`):
  - `rewriteReady`: transcript "make it formal", selection "hi team", model output "Hello team." → `.ready` with `command == "make it formal"`, `raw == "hi team"`, `uncleanedText == "hi team"`, `finalText == "Hello team."`.
  - `writeReady`: selection nil → `.ready`, `raw == ""`.
  - `noModelFails`, `tooLongSelectionFailsBeforeTranscribing` (transcriber not called), `silenceIsNothingHeard`, `modelErrorFails`, `slowModelTimesOut` (timeout injectable for the test: `CommandPipeline.timeoutSeconds` used through an init parameter `timeout: Double = CommandPipeline.timeoutSeconds`), `preambleRemoved`.
  - `languageRuleApplies`: Claude focus (default rule vi) → transcriber options language `.vi`.
  - `CommandPaste`: `pastesWhenUnchanged`; `changedSelectionCopies` (start selected "a", now "b"); `otherElementCopies`; `terminalCopies`; `secureWins`; `unreadableSelectionTrustsElement` (both selectedText nil, sameElement → `.paste`).
  - FixLast: `selectBackAllowsNewlines` ("a\nb" → `.selectBack(characters: 3)`); `selectBackLimit` (2_001 → `.copyOnly`, 2_000 → select back); `selectBackTypingBlocks`.
  - History: `commandRoundTrips` (entry with `command` encodes key `command`; nil omits it).
- [ ] **Step 2: Run** `swift test --filter "CommandPipelineTests|FixLastTests|HistoryTests"`. Expected: compile failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(core): command pipeline, paste decision and history`.

### Task 4: Selection capture

**Files:**
- Create: `Sources/BugVoiceMac/SelectionCapture.swift`
- Modify: `Sources/BugVoiceMac/PasteboardInserter.swift` (add `public func selectBack(_ count: Int) async`: Shift+Left, key code 123 with `.maskShift`, marked, batches of 50 with 10 ms pauses)
- Test: `Tests/BugVoiceMacTests/SelectionCaptureTests.swift`

**Interfaces:**
- Produces:
  ```swift
  @MainActor public final class SelectionCapture {
      public init(pasteboard: NSPasteboard = .general, postCopy: @escaping @MainActor () -> Void = SelectionCapture.postCommandC)
      /// AX selection when non-empty; otherwise ⌘C fallback; nil when nothing is selected.
      public func capture(axSelection: String?) async -> String?
      public static func postCommandC()   // ⌘C via PasteboardInserter.makeKeyEvent (marked)
      public var timeout: Duration = .milliseconds(300)
  }
  ```
- Fallback: take a `PasteboardSnapshot`, remember `changeCount`, call `postCopy`, poll every 20 ms until `changeCount` changes or `timeout`; read `.string`; restore the snapshot (always, also on no change or empty string). An empty or whitespace-only string is nil.

- [ ] **Step 1: Write failing tests** with a uniquely named `NSPasteboard(name:)`:
  - `axSelectionWins`: `capture(axSelection: "abc")` → "abc", `postCopy` not called.
  - `fallbackReadsCopiedText`: pasteboard holds "old"; `postCopy` writes "picked" → returns "picked"; afterwards the pasteboard string is "old".
  - `fallbackRestoresClipboard`: same, with an image-free multi-type item ("old" string + custom type data) → both types restored.
  - `noChangeMeansNoSelection`: `postCopy` does nothing, timeout 50 ms → nil; pasteboard still "old".
  - `markedEvents`: `PasteboardInserter.makeKeyEvent(keyCode: 123, keyDown: true, flags: .maskShift)` carries the marker.
- [ ] **Step 2: Run** `swift test --filter BugVoiceMacTests`. Expected: compile failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(app): selection capture with clipboard restore`.

### Task 5: App — command controller, HUD, settings

**Files:**
- Create: `Sources/BugVoice/CommandController.swift`
- Modify: `Sources/BugVoice/AppModel.swift` (own `command: CommandController?` next to `dictation`; `makeCommandPipeline()` built like `makePipeline` with `plan(for: .dictation)`; start and `applySettings` it with dictation)
- Modify: `Sources/BugVoice/DictationController.swift`: make `hud`, `inserter`, `isBusy` and `recorder.isRunning` reachable as `var hud: HUDController` / `var inserter: PasteboardInserter` / `var isRecording: Bool` (internal, not private); `receive` ignores input while `model.command?.isActive == true`; `pasteRaw()` for a result with `command != nil` uses `decideSelectBack` → `inserter.selectBack(n)` then paste `uncleanedText` (HUD "Original restored"), `.copyOnly` → copy (HUD "Copied — press ⌘V" / "text changed since the paste"); `redoInOtherLanguage()` for a command → "Nothing to fix".
- Modify: `Sources/BugVoice/HUD/HUDState.swift`, `HUDView.swift`: `.commandListening(selectionCharacters: Int?, app: String?, startedAt: Date, language: String, languageChanged: Bool)` (pill: dot, `Command` tag, "142 characters" or "New text", app, language label); `.rewriting(model: String?, app: String?)` ("Rewriting (Qwen)", detail "\(app) · Esc to cancel").
- Modify: `Sources/BugVoice/UI/Settings/GeneralTab.swift` (Command key picker without the hotkey's own key; footnote from the spec), `ShortcutsSettingsView.swift` (fixed row "Command" / "Hold \(commandKey spoken name)", hidden when Off).

**Interfaces:**
- Consumes: Tasks 1–4; `HotkeyMonitor`, `HoldGestureDetector` (`handsFreeEnabled = false`), `LanguageKeyCycler`, `LanguageResolver`, `FocusInspector.read()/focusedElement()/isSameElement`, `ReplacementGuard` via `DictationController`.
- `CommandController`:
  - `var isActive: Bool` (recording or rewriting).
  - Own `HotkeyMonitor(key: effectiveCommandKey.hotkeyKey)`; not started when Off. Its `onKeyDown` with key code 53 while rewriting cancels the task (HUD hides, nothing pasted).
  - On `.startHold`: ignore when dictation is recording or busy. Read focus; secure → HUD `.message(title: "Secure field — command not run", detail: nil)`, no recording. Capture selection (`SelectionCapture.capture(axSelection: focus.selectedText)`); over 8,000 → HUD `CommandFailure.selectionTooLong`, no recording. Start the recorder (reuse `AudioRecorder` from a new instance), show `.commandListening`.
  - On `.stop`: stop, run `CommandPipeline`, show stages (`.transcribing` → existing transcribing pill, `.cleaning` → `.rewriting`).
  - On `.ready(result)`: re-read focus and element; `CommandPaste.decide`; `.paste` → `dictation.inserter.insert(finalText)`; outcome `.inserted` (or `.copiedNotConsumed` if not consumed); `.copy(reason)` → copy, outcome `.copiedNotConsumed`, HUD "Copied — press ⌘V" with the reason; `.secure` → copy, `HUDState.secureFieldCopied`. Done HUD: "Rewritten · ⌘Z to undo" (selection) or "Written", detail "\(words) words". Then `model.record(result)` (history and `lastResult`) but not `recordInsights`; record the insertion in the dictation `ReplacementGuard` so Original can select back.
  - Log one line per command with `Log.dictation`: `command outcome=… app=… chars=… words=… stt=…s model=…s`.
- `MenuLastDictation`: when `result.command != nil`, header "Last command · \(app) · \(time)", the instruction in quotes on its own line, buttons **Copy** and **Original** (Original calls `pasteRaw()`); no Retry / Raw / language button.

- [ ] **Step 1:** Implement the controller and wiring.
- [ ] **Step 2:** Implement HUD states, settings rows and the popover card.
- [ ] **Step 3: Run** `swift test` and `Scripts/build-app.sh`. Expected: pass, build succeeds.
- [ ] **Step 4: Smoke check** (only when the owner is away from the keyboard, see AGENTS rules on synthetic input): Settings › General shows Command key; the Shortcuts row shows "Hold Right ⌥".
- [ ] **Step 5: Commit** `feat(app): command mode`.

### Task 6: History tag

**Files:**
- Modify: `Sources/BugVoice/UI/DictationHistoryView.swift`

- [ ] **Step 1:** Rows whose entry has `command` show a **Command** tag after the app name and the instruction in quotes (secondary, italic) above the result (mockup screen 4). Search matches the instruction too.
- [ ] **Step 2: Run** `swift test` and `Scripts/build-app.sh`. Expected: pass.
- [ ] **Step 3: Commit** `feat(app): command tag in dictation history`.

### Task 7: Docs and device checks

**Files:**
- Create: `docs/progress/command-log.md`
- Modify: `AGENTS.md` (key documents: spec, mockup, plan, log), `docs/progress/HANDOFF.md`, `docs/ROADMAP.md`, `docs/propose-new-features.md` (mark 1 as built)

- [ ] **Step 1:** Log per task, test counts, deviations, then device checks (owner runs those that need speech):
  - C1 Rewrite in Notion: selection replaced, ⌘Z restores it.
  - C2 Vietnamese instruction "dịch sang tiếng Anh" on Vietnamese text: English result.
  - C3 Write new in Slack or TextEdit with nothing selected.
  - C4 Selection in Ghostty: result copied, HUD "terminals do not replace a selection".
  - C5 Change the selection during "Rewriting": copied, nothing replaced.
  - C6 Escape during "Rewriting": nothing pasted.
  - C7 Original (popover) and ⌃⌥R after a multi-line rewrite: original back.
  - C8 Clipboard unchanged after a ⌘C-fallback capture (copy something first, run a command in Ghostty, ⌘V pastes the earlier clipboard).
  - C9 Secure field: "Secure field — command not run".
  - C10 History shows the Command tag; Insights word count unchanged.
  - C11 Command key Off: Right Option does nothing; setting the hotkey to Right Option turns the command key off.
  - C12 Light and dark match the mockup.
- [ ] **Step 2: Run** `swift test`. Expected: pass.
- [ ] **Step 3: Commit** `docs: command mode log and handoff`.
