# Spanish Dictation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the owner tick Spanish as a dictation language so it appears in every dictation language picker, the language key, cleanup prompts, redo and Apple Shortcuts; notes follow because they dictate through the same pipeline.

**Architecture:** One new setting, `SpeechSettings.dictationLanguages`, drives every list. Pure logic (normalising, key cycle, redo order, prompt lines) lives in `VoiceCore` with Swift Testing tests; the app target only reads the setting and the new helpers.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Swift Testing, WhisperKit 1.1.1 (unchanged).

**Spec:** `docs/superpowers/specs/2026-10-23-spanish-dictation-design.md` (mockup `docs/design/proposal-spanish.html`).

## Global Constraints

- Swift tools 6.0, macOS 15 floor; `VoiceCore` imports Foundation only; no new dependencies.
- TDD in `VoiceCore`: failing test first. `swift test` passes before every commit.
- Default `dictationLanguages` is `[.en, .vi]`; with it every picker, the key cycle and redo behave exactly as today.
- Fixed language order everywhere: English, Vietnamese, Spanish. Short codes `Auto`, `EN`, `VI`, `ES`.
- UI copy: plain English, no hedging, no emoji. Build with `Scripts/build-app.sh`, run with `Scripts/run-dev-app.sh` (second display). No synthetic dictation or paste while the owner may be at the keyboard.
- Commit after each task: `feat(core): …`, `feat(app): …`, `docs: …`, ending with the Co-Authored-By line.

## Review Focus

1. Settings file from before this change (no `dictationLanguages` key, `language: "vi"`): loads with `[.en, .vi]` and keeps Vietnamese. Test in Task 1.
2. Settings file with `language: "es"` but no Spanish ticked (hand-edited or after unticking): switch falls back to Auto. Test in Task 1.
3. Spanish per-app rule while Spanish is unticked: rule survives decoding and still resolves to Spanish. Test in Task 1.
4. Redo when Whisper detected a language outside the set (`"pt"`, `nil`, upper-case `"EN"`): starts at English and cycles every ticked language. Test in Task 3.
5. Language key started from a per-app rule language that is unticked: cycle starts at Auto, never shows the unticked language. Test in Task 2.

---

### Task 1: Dictation languages setting

**Files:**
- Modify: `Sources/VoiceCore/Transcription.swift` (add `DictationLanguages`, `SpeechLanguage.shortCode`)
- Modify: `Sources/VoiceCore/Settings.swift:130-145` (property), `:355-382` (decoding)
- Test: `Tests/VoiceCoreTests/DictationLanguagesTests.swift` (new)

**Interfaces:**
- Produces:
  - `public enum DictationLanguages { static let choices: [SpeechLanguage] /* [.en,.vi,.es] */; static let defaults: [SpeechLanguage] /* [.en,.vi] */; static func normalized(_: [SpeechLanguage]) -> [SpeechLanguage] }` — drops `.auto` and repeats, returns them in `choices` order, empty → `defaults`.
  - `extension SpeechLanguage { public var shortCode: String }` — `"Auto"`, `"EN"`, `"VI"`, `"ES"`.
  - `SpeechSettings.dictationLanguages: [SpeechLanguage]` (default `DictationLanguages.defaults`; `didSet` normalises and sets `language = .auto` when `language` is no longer in it). `language` gets a `didSet` that turns an unticked non-Auto language into `.auto`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import VoiceCore

struct DictationLanguagesTests {
    @Test func normalizedKeepsFixedOrder() {
        #expect(DictationLanguages.normalized([.es, .auto, .en, .es]) == [.en, .es])
        #expect(DictationLanguages.normalized([]) == [.en, .vi])
    }
    @Test func shortCodes() {
        #expect(SpeechLanguage.allCases.map(\.shortCode) == ["Auto", "VI", "EN", "ES"])
    }
    @Test func defaultsAndUntickReset() {
        var s = SpeechSettings()
        #expect(s.dictationLanguages == [.en, .vi])
        s.dictationLanguages = [.en, .vi, .es]; s.language = .es
        s.dictationLanguages = [.en, .vi]
        #expect(s.language == .auto)
    }
    @Test func legacyFileKeepsLanguage() throws {
        let s = try JSONDecoder().decode(SpeechSettings.self, from: Data(#"{"language":"vi"}"#.utf8))
        #expect(s.dictationLanguages == [.en, .vi]); #expect(s.language == .vi)
    }
    @Test func spanishSwitchWithoutSpanishTickedFallsBack() throws {
        let s = try JSONDecoder().decode(SpeechSettings.self, from: Data(#"{"language":"es"}"#.utf8))
        #expect(s.language == .auto)
    }
    @Test func spanishRuleSurvivesWhenUnticked() throws {
        let json = #"{"appLanguages":[{"kind":"website","id":"web.whatsapp.com","language":"es"}]}"#
        let s = try JSONDecoder().decode(SpeechSettings.self, from: Data(json.utf8))
        #expect(s.appLanguages == [AppLanguageRule(kind: .website, id: "web.whatsapp.com", language: .es)])
    }
    @Test func roundTripsSpanish() throws {
        var s = SpeechSettings(); s.dictationLanguages = [.en, .vi, .es]; s.language = .es
        #expect(try JSONDecoder().decode(SpeechSettings.self, from: JSONEncoder().encode(s)) == s)
    }
}
```

- [ ] **Step 2: Run `swift test --filter DictationLanguagesTests`** — expected FAIL: `DictationLanguages` not found.

- [ ] **Step 3: Implement** the Interfaces above. Property observers do not run inside `init(from:)`, so decoding normalises `dictationLanguages` and resets an unticked `language` itself (as `MeetingSettings` does at `Settings.swift:121`). In decoding, read `dictationLanguages` before `language`; the app-rule filter accepts `.en`, `.vi`, `.es` (rejects `.auto`). Add `dictationLanguages` to `SpeechSettings.CodingKeys` if the type lists keys explicitly.

- [ ] **Step 4: Run `swift test`** — all pass (existing settings tests included).

- [ ] **Step 5: Commit** `feat(core): dictation languages setting with Spanish`

### Task 2: Language key cycle follows the ticked languages

**Files:**
- Modify: `Sources/VoiceCore/LanguageKeyCycler.swift`
- Test: `Tests/VoiceCoreTests/LanguageKeyCyclerTests.swift`

**Interfaces:**
- Consumes: `DictationLanguages.normalized`.
- Produces: `LanguageKeyCycler.init(start: SpeechLanguage, languages: [SpeechLanguage] = DictationLanguages.defaults)`; `tap()` goes Auto → each language in order → Auto. A start not in `languages` starts at `.auto`.

- [ ] **Step 1: Add failing tests** (keep the two existing ones unchanged — they prove the default cycle):

```swift
@Test func cyclesThroughSpanish() {
    var c = LanguageKeyCycler(start: .auto, languages: [.en, .vi, .es])
    c.tap(); #expect(c.current == .en)
    c.tap(); #expect(c.current == .vi)
    c.tap(); #expect(c.current == .es)
    c.tap(); #expect(c.current == .auto)
}
@Test func untickedStartBeginsAtAuto() {
    var c = LanguageKeyCycler(start: .es, languages: [.en, .vi])
    #expect(c.current == .auto)
    c.tap(); c.tap(); c.tap()
    #expect(c.current == .auto)
}
@Test func spanishOnlyCycle() {
    var c = LanguageKeyCycler(start: .es, languages: [.es])
    #expect(c.current == .es)
    c.tap(); #expect(c.current == .auto)
}
```

- [ ] **Step 2: Run `swift test --filter LanguageKeyCyclerTests`** — FAIL (no `languages:` label).
- [ ] **Step 3: Implement**; store the normalised list.
- [ ] **Step 4: Run `swift test`** — pass.
- [ ] **Step 5: Commit** `feat(core): language key cycles the dictation languages`

### Task 3: Redo order for three languages

**Files:**
- Modify: `Sources/VoiceCore/FixLast.swift` (replace `otherLanguage(of:)`)
- Test: `Tests/VoiceCoreTests/FixLastTests.swift` (replace `otherLanguage` test)

**Interfaces:**
- Produces:
  - `public struct RedoChain: Sendable, Equatable { public let original: String?; public private(set) var tried: [SpeechLanguage]; public init(original: String?); public mutating func next(languages: [SpeechLanguage]) -> SpeechLanguage; public func peek(languages: [SpeechLanguage]) -> SpeechLanguage }`
  - `FixLast.otherLanguage(of:)` is removed; callers use `RedoChain`.

`next` algorithm (spec "Redo in another language"):

```
order = DictationLanguages.normalized(languages)
o = original?.lowercased()
if let pick = order.first(where: { $0.rawValue != o && !tried.contains($0) }) { tried.append(pick); return pick }
tried = []
if let back = SpeechLanguage(rawValue: o ?? ""), back != .auto, order.contains(back) { return back }
tried = [order[0]]; return order[0]
```

`peek` runs `next` on a copy.

- [ ] **Step 1: Write failing tests**

```swift
private func chain(_ original: String?, _ languages: [SpeechLanguage], presses: Int) -> [SpeechLanguage] {
    var c = RedoChain(original: original)
    return (0..<presses).map { _ in c.next(languages: languages) }
}
@Test func twoLanguageSwapUnchanged() {
    #expect(chain("en", [.en, .vi], presses: 3) == [.vi, .en, .vi])
    #expect(chain("vi", [.en, .vi], presses: 2) == [.en, .vi])
}
@Test func threeLanguageOrder() {
    let all: [SpeechLanguage] = [.en, .vi, .es]
    #expect(chain("en", all, presses: 4) == [.vi, .es, .en, .vi])
    #expect(chain("vi", all, presses: 3) == [.en, .es, .vi])
    #expect(chain("es", all, presses: 3) == [.en, .vi, .es])
}
@Test func detectedOutsideTheSet() {
    let all: [SpeechLanguage] = [.en, .vi, .es]
    #expect(chain("pt", all, presses: 4) == [.en, .vi, .es, .en])
    #expect(chain(nil, [.en, .vi], presses: 3) == [.en, .vi, .en])
    #expect(chain("EN", [.en, .vi], presses: 1) == [.vi])
}
@Test func peekDoesNotAdvance() {
    let c = RedoChain(original: "en")
    #expect(c.peek(languages: [.en, .vi, .es]) == .vi)
    #expect(c.tried.isEmpty)
}
```

- [ ] **Step 2: Run `swift test --filter FixLastTests`** — FAIL.
- [ ] **Step 3: Implement** `RedoChain`; delete `otherLanguage(of:)` and its old test. `swift build` will show the two app call sites (`DictationController.redoInOtherLanguage`, `MenuSections`); leave them for Task 5 but keep the build green by switching them to `RedoChain(original: previous.language).next(languages: model.settings.speech.dictationLanguages)` / `.peek(...)` now (Task 5 adds the stored chain).
- [ ] **Step 4: Run `swift test`** — pass.
- [ ] **Step 5: Commit** `feat(core): redo order for three dictation languages`

### Task 4: Spanish prompt lines and Shortcuts language

**Files:**
- Modify: `Sources/VoiceCore/PromptBuilder.swift:13,49-51`, `Sources/VoiceCore/CommandPrompt.swift:15`, `Sources/VoiceCore/ShortcutsActions.swift:3-8`
- Test: `Tests/VoiceCoreTests/PromptTests.swift`, `Tests/VoiceCoreTests/CommandPromptTests.swift`, `Tests/VoiceCoreTests/ShortcutsActionsTests.swift`

**Interfaces:**
- Produces:
  - `PromptBuilder.spanishRule = "The speaker spoke Spanish. Remove Spanish filler words (eh, este, o sea, pues) and apply self-corrections such as \"no, perdón\" or \"quiero decir\" by keeping only the corrected version."`
  - `PromptBuilder.keepEnglishSpanishRule = "Keep English words the speaker used in English. Never translate them into Spanish."`
  - `systemPrompt` appends `spanishRule` for `.es`, and `keepEnglishSpanishRule` for `.es` when `keepEnglishWords`. `CommandPrompt.request` appends `keepEnglishSpanishRule` for `.es` when `keepEnglishWords`.
  - `ShortcutsLanguage.spanish` → `[.es]`.

- [ ] **Step 1: Write failing tests**

```swift
// PromptTests
@Test func spanishLines() {
    let p = PromptBuilder().systemPrompt(style: .work, vocabulary: Vocabulary(), focus: FocusSnapshot(), language: .es, keepEnglishWords: true)
    #expect(p.contains(PromptBuilder.spanishRule))
    #expect(p.contains(PromptBuilder.keepEnglishSpanishRule))
    #expect(!p.contains(PromptBuilder.keepEnglishRule))
}
@Test func noSpanishLinesForOtherLanguages() {
    for language in [SpeechLanguage.auto, .en, .vi] {
        let p = PromptBuilder().systemPrompt(style: .work, vocabulary: Vocabulary(), focus: FocusSnapshot(), language: language, keepEnglishWords: true)
        #expect(!p.contains(PromptBuilder.spanishRule))
    }
}
// CommandPromptTests: language .es, keepEnglishWords true → system contains keepEnglishSpanishRule; false → does not.
// ShortcutsActionsTests
@Test func spanishShortcutLanguage() { #expect(ShortcutsLanguage.spanish.languages == [.es]) }
```

Use the existing tests' constructors for `Vocabulary` and `FocusSnapshot` if they differ from the above.

- [ ] **Step 2: Run `swift test`** — the new tests FAIL.
- [ ] **Step 3: Implement** the Interfaces.
- [ ] **Step 4: Run `swift test`** — pass.
- [ ] **Step 5: Commit** `feat(core): Spanish cleanup prompt and Shortcuts language`

### Task 5: App wiring

**Files:**
- Modify: `Sources/BugVoice/UI/Settings/SpeechTab.swift:51-80` (checkbox row, Language picker, footnotes, keep-English label)
- Modify: `Sources/BugVoice/UI/Settings/AppLanguagesCard.swift:35-36,71-72` (pickers)
- Modify: `Sources/BugVoice/UI/Menu/MenuPopover.swift:233-235`, `MenuSubmenus.swift:95-97,110,136`, `MenuPanelController.swift:226`, `MenuSections.swift:160-162`
- Modify: `Sources/BugVoice/DictationController.swift:149,217-224,422-441`, `CommandController.swift:127,164-169`
- Modify: `Sources/BugVoice/AppModel+Models.swift:130-131` and the `AppModel` stored properties
- Modify: `Sources/BugVoice/Intents/TranscribeFileIntent.swift:6-12`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: `AppModel.redoChain: RedoChain?` — set to `nil` in `record(_:)`; `DictationController.redoInOtherLanguage` does `var chain = model.redoChain ?? RedoChain(original: previous.language); let language = chain.next(languages: model.settings.speech.dictationLanguages); model.redoChain = chain`. `MenuSections` labels the button with `(model.redoChain ?? RedoChain(original: result.language)).peek(languages: …).displayName`, and the tooltip stays "Redo in other language (⌃⌥L)".

- [ ] **Step 1: Settings › Speech.** Above the Language picker, a "Dictation languages" row with one `Toggle(.checkbox)` per `DictationLanguages.choices`, each disabled when it is the only ticked one (copy `MeetingsTab.isLastLanguage`). Footnote: "Languages you speak when you dictate. Each one appears in the language switch, the language key and the per-app list." The Language picker lists Auto then the ticked languages (`displayName`). Its footnote becomes "Auto uses the per-app list below, then detects the language. \(ticked names joined as "English, Vietnamese or Spanish") applies everywhere." The key footnote lists "Auto, " + ticked names. Keep-English toggle title: "Keep English words in Vietnamese and Spanish" when `.es` is ticked, else today's title.
- [ ] **Step 2: Per-app pickers** list the ticked languages plus the rule's own language when it is unticked; the website default (`websiteLanguage`) and new app rules keep today's defaults.
- [ ] **Step 3: Menu.** Popover switch: Auto + ticked languages with `shortCode` labels. `MenuSubmenuItems.languages` becomes a function of the model (Auto + ticked, `displayName`), update its three uses. Status item title: `language == .auto ? "" : language.shortCode`.
- [ ] **Step 4: HUD labels.** `DictationController.hudLanguage` and `CommandController.showListening` use `shortCode`. Both `LanguageKeyCycler(start:)` call sites pass `languages: model.settings.speech.dictationLanguages`.
- [ ] **Step 5: Redo.** Add `AppModel.redoChain`, reset it in `record(_:)`, use it in `redoInOtherLanguage` and `MenuSections` per Interfaces.
- [ ] **Step 6: Shortcuts.** `ShortcutsLanguageEntity` gains `case spanish` with display "Spanish".
- [ ] **Step 7: Verify.** `swift build` clean (no new warnings in touched files), `swift test` pass, `Scripts/build-app.sh`, `Scripts/run-dev-app.sh`; on the second display open Settings › Speech, screenshot the BugVoice window with Spanish unticked and ticked (ticking changes the owner's settings; untick again afterwards so their setup is unchanged), and open the popover from the second display's menu bar to see ES. No dictation.
- [ ] **Step 8: Commit** `feat(app): Spanish in dictation pickers, key, HUD, redo and Shortcuts`

### Task 6: Speech check and docs

**Files:**
- Create: `docs/progress/spanish-log.md`
- Modify: `CLAUDE.md` (AGENTS.md) key documents, `docs/progress/HANDOFF.md`

- [ ] **Step 1: Spanish transcription check.** `say -v Mónica -o <scratch>/es.aiff "Mañana enviamos el prototipo y revisamos la accesibilidad."`, convert to 16 kHz WAV with ffmpeg, run `swift run BugVoiceBench` on it with `--languages auto,es` (see `Sources/BugVoiceBench/main.swift` for the file argument). Expected: both runs return Spanish text close to the sentence; record the output in the log.
- [ ] **Step 2: Log.** `docs/progress/spanish-log.md`: what was built per task with commits, test count, the bench result, screenshots taken, and the spec's seven device checks as an unchecked list for the owner.
- [ ] **Step 3: Docs.** Add the spec, mockup, plan and log to the key documents list; add a HANDOFF entry.
- [ ] **Step 4: Commit** `docs: Spanish dictation log and handoff`
