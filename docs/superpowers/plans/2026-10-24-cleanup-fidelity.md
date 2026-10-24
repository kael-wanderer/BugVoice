# Cleanup Fidelity Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After cleanup and before paste, detect lost or invented numbers, negations, paths and identifiers; paste raw (default), warn, or ignore, and let ⌃⌥R swap between versions.

**Architecture:** A pure `FidelityCheck` in `VoiceCore` compares `protected.text` with the sanitized cleaned output. `DictationPipeline` stores the issues on `DictationResult` and picks what pastes from a new `StyleSettings.fidelityAction`. HUD wording, the ⌃⌥R swap decision and Diagnostics live in `VoiceCore` so they are unit tested; the app target only wires them.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, Foundation only in `VoiceCore`.

**Spec:** `docs/superpowers/specs/2026-10-24-cleanup-fidelity-design.md` (mockup `docs/design/proposal-fidelity.html`)

## Global Constraints

- Swift package, tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only.
- No new dependency.
- TDD for everything in `VoiceCore`: failing test first. `swift test` passes before every commit.
- Commit after each task; messages `feat(core): …`, `feat(app): …`, `docs: …`.
- UI copy: plain English, no hedging words, no emoji.
- Diagnostics never carry dictated words: kinds only.
- Check time under 5 ms for a 200-word dictation.
- Command mode, Ask AI, meeting summaries and translations are never checked.
- Build the app with `Scripts/build-app.sh`; never run synthetic dictation while the owner is at the keyboard.

## Deviations from the spec (plan decisions)

- `FidelityCheck.issues(raw:cleaned:)` has no `language` parameter: number words and negations for English, Vietnamese and Spanish are always all active. Language detection is unreliable on mixed speech.
- No Global search entry: search targets only Settings sections (`SearchHit.Target.settings(section:)`), and the setting lives on the Style page.
- Identifier and path case: exact match, except a token whose first letter was capitalized at the start of a sentence in the cleaned text (`info.plist` → `Info.plist` after `. ` or at the start) counts as kept.

## Review Focus

1. Snippet placeholders `⟦S1⟧` contain digits; they must never count as numbers. (Task 1 test `placeholdersAreNotNumbers`.)
2. A secure-field result must not keep issue tokens in memory: `recallable` clears `fidelityIssues`. (Task 4 test `secureFieldDropsIssues`.)
3. An older `history.jsonl` line without `fidelityIssues` and an older `settings.json` without `fidelityAction` decode with defaults. (Task 4 tests `historyWithoutIssuesDecodes`, `unknownFidelityActionKeepsDefault`.)
4. Trailing punctuation and Markdown around tokens (`Info.plist.`, `**15**`, `` `AppModel` ``) must not cause a lost-detail flag. (Task 2 test `punctuationAroundTokens`.)
5. Very long dictations stay under the time budget. (Task 2 test `twoHundredWordsUnderFiveMilliseconds`.)

---

### Task 1: Number comparison

**Files:**
- Create: `Sources/VoiceCore/FidelityCheck.swift`, `Sources/VoiceCore/NumberWords.swift`
- Test: `Tests/VoiceCoreTests/FidelityCheckTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct FidelityIssue: Codable, Equatable, Sendable {
      public enum Kind: String, Codable, Sendable, CaseIterable { case number, negation, path, identifier }
      public enum Direction: String, Codable, Sendable { case lost, invented }
      public var kind: Kind
      public var direction: Direction
      public var token: String   // as written in raw (lost) or cleaned (invented)
  }
  public enum FidelityCheck {
      public static func issues(raw: String, cleaned: String) -> [FidelityIssue]
  }
  enum NumberWords {
      /// Values spoken as words in en/vi/es, compositional: "twenty five", "hai mươi lăm", "veinticinco" → 25.
      static func values(in text: String) -> Set<Decimal>
  }
  ```
  Issue order: kind in `Kind.allCases` order, then position in the text.

- [ ] **Step 1: Write failing tests** in `FidelityCheckTests` (Swift Testing, `@testable import VoiceCore`):

```swift
@Test func spokenNumberBecomesDigit() { #expect(FidelityCheck.issues(raw: "the timeout is fifteen seconds", cleaned: "The timeout is 15 seconds.").isEmpty) }
@Test func vietnameseNumberWord() { #expect(FidelityCheck.issues(raw: "họp lúc ba giờ chiều", cleaned: "Họp lúc 3 giờ chiều.").isEmpty) }
@Test func spanishCompound() { #expect(FidelityCheck.issues(raw: "son veinticinco euros", cleaned: "Son 25 euros.").isEmpty) }
@Test func digitSpelledOut() { #expect(FidelityCheck.issues(raw: "wait 5 minutes", cleaned: "Wait five minutes.").isEmpty) }
@Test func changedNumber() {
    #expect(FidelityCheck.issues(raw: "set the limit to 5", cleaned: "Set the limit to 50.") ==
        [.init(kind: .number, direction: .lost, token: "5"), .init(kind: .number, direction: .invented, token: "50")])
}
@Test func inventedNumber() { #expect(FidelityCheck.issues(raw: "around 20 users", cleaned: "Around 20 users, about 30%.") == [.init(kind: .number, direction: .invented, token: "30%")]) }
@Test func separatorsTimesPercent() {
    #expect(FidelityCheck.issues(raw: "1500 rows at 3 pm, 15 percent", cleaned: "1,500 rows at 3:00 PM, 15%.").isEmpty)
    #expect(FidelityCheck.issues(raw: "3 30", cleaned: "3:30").isEmpty)
}
@Test func decimalFromParts() { #expect(FidelityCheck.issues(raw: "version one point five", cleaned: "Version 1.5").isEmpty) }
@Test func listMarkersIgnored() { #expect(FidelityCheck.issues(raw: "first fix login second update docs", cleaned: "1. Fix login\n2. Update docs").isEmpty) }
@Test func ordinals() { #expect(FidelityCheck.issues(raw: "the first item", cleaned: "The 1st item.").isEmpty) }
@Test func placeholdersAreNotNumbers() { #expect(FidelityCheck.issues(raw: "send ⟦S1⟧ now", cleaned: "Send ⟦S1⟧ now.").isEmpty) }
@Test func selfCorrectionDropsEarlierNumber() {
    #expect(FidelityCheck.issues(raw: "meet at three, no I mean four", cleaned: "Meet at 4.").isEmpty)
    #expect(FidelityCheck.issues(raw: "gọi lúc 2 giờ à không 3 giờ", cleaned: "Gọi lúc 3 giờ.").isEmpty)
}
```

- [ ] **Step 2: Run** `swift test --filter FidelityCheckTests` — expected: build failure, `FidelityCheck` not defined.

- [ ] **Step 3: Implement** `NumberWords.values(in:)` and the number part of `FidelityCheck.issues`.

Algorithm (the tests do not fully determine it):
- Remove placeholders (`⟦…⟧`) from both texts first. Strip line-start list markers `^\s*(\d+[.)]|[-*•])\s+` from cleaned.
- Each digit token yields a set of candidate values: `1,500` / `1.500` → {1500, 1.5}; `3:00` → {3}; `3:30` → {3, 30}; `15%` → {15}; `1st` → {1}; `1.5` → {1.5}.
- Value sets per side = digit candidates ∪ `NumberWords.values` (ordinals included: first, thứ nhất, primero).
- Lost: a raw digit token none of whose candidates is in the cleaned value set. Invented: a cleaned digit token none of whose candidates is in the raw value set, except a decimal `a.b` whose parts a and b are both raw values.
- Correction markers (`no, I mean`, `I mean`, `sorry`, `actually`, `à không`, `à nhầm`, `ý là`, `no, perdón`, `quiero decir`, case-insensitive, commas optional so "no I mean" matches): raw details before the last marker of a sentence never count as lost. Shared helper, reused by Task 2.

- [ ] **Step 4: Run** `swift test --filter FidelityCheckTests` — expected: all pass.

- [ ] **Step 5: Commit** `feat(core): fidelity check for numbers`

---

### Task 2: Negations, paths, identifiers and the corpus

**Files:**
- Modify: `Sources/VoiceCore/FidelityCheck.swift`
- Test: `Tests/VoiceCoreTests/FidelityCheckTests.swift`, new `Tests/VoiceCoreTests/FidelityCorpusTests.swift`

**Interfaces:**
- Consumes: Task 1 types and correction-marker helper.
- Produces: no new public API.

- [ ] **Step 1: Write failing tests**

```swift
@Test func droppedNot() { #expect(FidelityCheck.issues(raw: "we should not ship Friday", cleaned: "We should ship Friday.") == [.init(kind: .negation, direction: .lost, token: "not")]) }
@Test func contractionExpanded() { #expect(FidelityCheck.issues(raw: "don't merge it", cleaned: "Do not merge it.").isEmpty) }
@Test func vietnameseNegation() { #expect(FidelityCheck.issues(raw: "đừng xoá file này", cleaned: "Xoá file này.") == [.init(kind: .negation, direction: .lost, token: "đừng")]) }
@Test func markerNegationNotCounted() { #expect(FidelityCheck.issues(raw: "send it today no I mean tomorrow", cleaned: "Send it tomorrow.").isEmpty) }
@Test func addedNegationIgnored() { #expect(FidelityCheck.issues(raw: "that works", cleaned: "That does not work.").isEmpty) }
@Test func pathChanged() { #expect(FidelityCheck.issues(raw: "edit Sources/VoiceCore/History.swift", cleaned: "Edit Sources/History.swift.") == [.init(kind: .path, direction: .lost, token: "Sources/VoiceCore/History.swift")]) }
@Test func identifiersLost() {
    #expect(FidelityCheck.issues(raw: "rename user_profile to UserProfile", cleaned: "Rename user profile to user profile.").map(\.token) == ["user_profile", "UserProfile"])
}
@Test func projectWordJoinAllowed() { #expect(FidelityCheck.issues(raw: "check the app model class", cleaned: "Check the AppModel class.").isEmpty) }
@Test func flagsKept() { #expect(FidelityCheck.issues(raw: "run swift test --filter Foo", cleaned: "Run swift test --filter Foo").isEmpty) }
@Test func punctuationAroundTokens() { #expect(FidelityCheck.issues(raw: "open Info.plist and AppModel at 15", cleaned: "Open `Info.plist` and **AppModel** at **15**.").isEmpty) }
@Test func sentenceStartCapital() { #expect(FidelityCheck.issues(raw: "info.plist needs a bump", cleaned: "Info.plist needs a bump.").isEmpty) }
@Test func abbreviationsAreNotPaths() { #expect(FidelityCheck.issues(raw: "e.g. at 3 a.m.", cleaned: "For example, at 3 AM.").isEmpty) }
@Test func twoHundredWordsUnderFiveMilliseconds() {
    let raw = Array(repeating: "please do not change Sources/App.swift or AppModel before 15 users", count: 20).joined(separator: " ")
    let start = ContinuousClock.now
    _ = FidelityCheck.issues(raw: raw, cleaned: raw)
    #expect(ContinuousClock.now - start < .milliseconds(5))
}
```

Token rules from the spec's table: negation word lists (English: not, no, never, n't suffix, cannot, none, nothing, nobody, neither, nor, without; Vietnamese: không, chưa, chẳng, đừng, chả; Spanish: no, nunca, nada, nadie, ni, sin, tampoco), lost when cleaned count < raw count after removing marker negations. Path: contains `/` or `\` between word characters, starts with `~/` or `./`, or `name.ext` with name ≥ 2 characters and ext 1–5 letters (not `e.g`, `a.m`). Identifier: inner capital, `_`, `--word`, `-x` with a letter, or backticked. Trailing `.,;:!?)` and surrounding `` ` `` `*` are stripped before comparing.

- [ ] **Step 2: Write `FidelityCorpusTests`**: one parameterized `@Test(arguments:)` over at least 60 `(raw, cleaned, flags: Bool)` cases, English, Vietnamese, Spanish and mixed, half passing (filler removal, self-corrections, spoken numbers, list formatting, project-word joins, Spanish "eh, este, pues" removed) and half flagging (each kind, lost and invented). Include the twelve rows of the mockup's table verbatim.

- [ ] **Step 3: Run** `swift test --filter Fidelity` — expected: new tests fail.

- [ ] **Step 4: Implement** the three kinds in `FidelityCheck.issues`.

- [ ] **Step 5: Run** `swift test --filter Fidelity` — expected: all pass.

- [ ] **Step 6: Commit** `feat(core): fidelity check for negations, paths and identifiers`

---

### Task 3: Wording for the pill and the history tooltip

**Files:**
- Modify: `Sources/VoiceCore/FidelityCheck.swift`
- Test: `Tests/VoiceCoreTests/FidelityCheckTests.swift`

**Interfaces:**
- Produces:
  ```swift
  extension FidelityCheck {
      /// "5 → 50" (one lost and one invented number paired), "added 30", "dropped “not”", "lost `Sources/App.swift`".
      public static func describe(_ issues: [FidelityIssue]) -> [String]
      /// pastedRaw true: "Raw — cleanup …"; false: "Check — cleanup …".
      public static func hudTitle(_ issues: [FidelityIssue], pastedRaw: Bool) -> String
      public static func hudDetail(pastedRaw: Bool, pasteRawLetter: String) -> String
  }
  ```

- [ ] **Step 1: Write failing tests**

```swift
@Test func describePairsNumbers() {
    let issues: [FidelityIssue] = [.init(kind: .number, direction: .lost, token: "5"), .init(kind: .number, direction: .invented, token: "50")]
    #expect(FidelityCheck.describe(issues) == ["5 → 50"])
    #expect(FidelityCheck.hudTitle(issues, pastedRaw: true) == "Raw — cleanup changed a number")
}
@Test func hudTitles() {
    #expect(FidelityCheck.hudTitle([.init(kind: .negation, direction: .lost, token: "not")], pastedRaw: true) == "Raw — cleanup dropped “not”")
    #expect(FidelityCheck.hudTitle([.init(kind: .path, direction: .lost, token: "a/b")], pastedRaw: true) == "Raw — cleanup changed a path")
    #expect(FidelityCheck.hudTitle([.init(kind: .identifier, direction: .lost, token: "AppModel")], pastedRaw: false) == "Check — cleanup changed a name")
    #expect(FidelityCheck.hudTitle([.init(kind: .negation, direction: .lost, token: "not"), .init(kind: .path, direction: .lost, token: "a/b")], pastedRaw: true) == "Raw — cleanup changed 2 details")
    #expect(FidelityCheck.describe([.init(kind: .number, direction: .invented, token: "30%")]) == ["added 30%"])
    #expect(FidelityCheck.describe([.init(kind: .path, direction: .lost, token: "a/b")]) == ["lost `a/b`"])
}
@Test func hudDetails() {
    #expect(FidelityCheck.hudDetail(pastedRaw: true, pasteRawLetter: "R") == "⌃⌥R pastes the cleaned text")
    #expect(FidelityCheck.hudDetail(pastedRaw: false, pasteRawLetter: "X") == "⌃⌥X pastes raw")
}
```

"2 details" counts `describe` lines, so a paired number is one detail.

- [ ] **Step 2: Run** `swift test --filter FidelityCheckTests` — expected: fail, functions missing.
- [ ] **Step 3: Implement** the three functions.
- [ ] **Step 4: Run** `swift test --filter FidelityCheckTests` — expected: pass.
- [ ] **Step 5: Commit** `feat(core): fidelity check wording`

---

### Task 4: Setting, result fields and pipeline

**Files:**
- Modify: `Sources/VoiceCore/Settings.swift:198-211,414-430` (`StyleSettings` + decoder), `Sources/VoiceCore/OutputSanitizer.swift:3-5`, `Sources/VoiceCore/DictationPipeline.swift` (result fields, `recallable`, `historyEntry`, clean step), `Sources/VoiceCore/History.swift:20-62`, `Sources/VoiceCore/Diagnostics.swift:20-30`
- Test: `Tests/VoiceCoreTests/DictationPipelineTests.swift`, `HistoryTests.swift`, `DiagnosticsTests.swift`, the settings tests file that covers `StyleSettings` (find with `rg -l "cleanupEnabled" Tests/VoiceCoreTests`)

**Interfaces:**
- Consumes: `FidelityCheck.issues(raw:cleaned:)`, `FidelityIssue`.
- Produces:
  ```swift
  public enum FidelityAction: String, Codable, Sendable, CaseIterable { case raw, warn, off }   // Settings.swift
  StyleSettings.fidelityAction: FidelityAction = .raw          // key "fidelityAction"
  RawReason.detailChanged
  DictationResult.fidelityIssues: [FidelityIssue] = []
  DictationResult.fidelityAction: FidelityAction = .raw        // copy of the setting at run time
  DictationResult.isFidelityFallback: Bool                     // rawReason == .detailChanged && cleaned != nil
  HistoryEntry.fidelityIssues: [FidelityIssue]?                // CodingKey "fidelityIssues"; init param default nil
  ```

- [ ] **Step 1: Write failing tests**

```swift
// DictationPipelineTests
@Test func fallbackPastesRawAndKeepsCleaned() async {
    let insertion = RecordingInsertion()
    let r = await pipeline(transcriber: FakeTranscriber(text: "we should not ship Friday"), model: FakeModel(output: "We should ship Friday."), insertion: insertion)
        .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
    #expect(r.rawReason == .detailChanged)
    #expect(r.finalText == "we should not ship Friday")
    #expect(r.cleaned == "We should ship Friday.")
    #expect(r.fidelityIssues.map(\.kind) == [.negation])
    #expect(r.isFidelityFallback)
}
@Test func warnPastesCleaned() async {
    var settings = AppSettings(); settings.styles.fidelityAction = .warn
    let r = await pipeline(transcriber: FakeTranscriber(text: "we should not ship Friday"), model: FakeModel(output: "We should ship Friday."), settings: settings)
        .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
    #expect(r.rawReason == nil && r.finalText == "We should ship Friday." && r.fidelityIssues.count == 1 && r.fidelityAction == .warn)
}
@Test func offStillRecords() async { /* fidelityAction = .off: rawReason nil, cleaned pasted, fidelityIssues.count == 1 */ }
@Test func cleanPassHasNoIssues() async { /* default FakeTranscriber/FakeModel: fidelityIssues empty, rawReason nil */ }
@Test func secureFieldDropsIssues() { /* DictationResult with outcome .copiedSecureField and one issue: recallable.fidelityIssues.isEmpty */ }
// HistoryTests
@Test func historyKeepsIssues() { /* round-trip encode/decode keeps fidelityIssues */ }
@Test func historyWithoutIssuesDecodes() { /* an existing JSONL line without the key decodes, fidelityIssues == nil */ }
// Settings
@Test func unknownFidelityActionKeepsDefault() { /* {"fidelityAction":"maybe"} decodes to .raw; missing key → .raw */ }
// DiagnosticsTests
@Test func summaryNamesFidelityKinds() { /* result with negation + path issues: summary contains "raw=detailChanged" and "fidelity=negation,path", and not the token text */ }
```

Write the bodies of the commented tests in the same style as the first two.

- [ ] **Step 2: Run** `swift test --filter "DictationPipelineTests|HistoryTests|DiagnosticsTests|Settings"` — expected: build failure on missing members.

- [ ] **Step 3: Implement.**
  - Pipeline, in `case .accepted(let cleaned) where protected.isIntact(cleaned)`: `let issues = FidelityCheck.issues(raw: protected.text, cleaned: cleaned)`; set `result.fidelityIssues`, `result.fidelityAction = settings.styles.fidelityAction`. If issues are non-empty and the action is `.raw`: `rawReason = .detailChanged`, do not set `cleanedAccepted`, but after the fill step set `result.cleaned = protected.fill(vocabulary.applyReplacements(to: cleaned))`. Otherwise accept as today.
  - `recallable` also clears `fidelityIssues`. `historyEntry` passes `fidelityIssues.isEmpty ? nil : fidelityIssues`.
  - `Diagnostics.dictationSummary`: append `fidelity=<kinds>` (distinct, `Kind.allCases` order) when issues exist.

- [ ] **Step 4: Run** `swift test` — expected: all pass.
- [ ] **Step 5: Commit** `feat(core): run fidelity check before paste`

---

### Task 5: ⌃⌥R swap, pill and popover label

**Files:**
- Modify: `Sources/VoiceCore/FixLast.swift` (add plan function, `FixKind.cleaned`), `Sources/BugVoice/DictationController.swift:389-415` (`pasteRaw`), `Sources/BugVoice/HUD/HUDState.swift:19-55` and its two callers (`DictationController.swift:351,477`), `Sources/BugVoice/UI/Menu/MenuSections.swift:159-161`
- Test: `Tests/VoiceCoreTests/FixLastTests.swift`

**Interfaces:**
- Consumes: `isFidelityFallback`, `fidelityIssues`, `fidelityAction`, `FidelityCheck.hudTitle/hudDetail`.
- Produces:
  ```swift
  public enum FixKind: String, Codable, Sendable { case raw, otherLanguage, cleaned }
  public enum PasteRawPlan: Equatable, Sendable {
      case alreadyRaw
      case replace(DictationResult, kind: FixKind, title: String)
  }
  extension FixLast { public static func pasteRawPlan(_ previous: DictationResult) -> PasteRawPlan }
  static func HUDState.from(_ r: DictationResult, pasteRawLetter: String) -> HUDState?
  ```

- [ ] **Step 1: Write failing tests** in `FixLastTests`:

```swift
@Test func fallbackSwapsToCleaned() {
    // previous: finalText == uncleanedText == "we should not ship Friday", cleaned "We should ship Friday.", rawReason .detailChanged, one negation issue, style .work
    // expect .replace(r, kind: .cleaned, title: "Replaced with cleaned text") with r.finalText == "We should ship Friday.", r.rawReason == nil, r.cleaned unchanged
}
@Test func swappedBackKeepsCleaned() {
    // previous: the replacement from above (cleaned pasted, issues present)
    // expect .replace(r, kind: .raw, title: "Replaced with raw text") with r.finalText == uncleanedText, r.rawReason == .detailChanged, r.cleaned != nil
}
@Test func ordinaryPasteRawUnchanged() {
    // no issues, cleaned pasted: .replace with finalText == uncleanedText, cleaned == nil, rawReason == nil
}
@Test func alreadyRawWithoutCleaned() { /* finalText == uncleanedText, cleaned nil: .alreadyRaw */ }
@Test func terminalTrimOnSwap() { /* style .terminal, cleaned "git status." → swapped finalText "git status" (DictationPipeline.trimmed) */ }
```

- [ ] **Step 2: Run** `swift test --filter FixLastTests` — expected: fail.
- [ ] **Step 3: Implement** `pasteRawPlan`; then in `DictationController.pasteRaw` replace the inline "Already raw" / replacement logic with a `switch` on it (keep the existing guards, `showNothingToFix`, the "Already raw" message and `cleanup is off for …` detail, and `replacementDecision()`), passing `kind` and `title` to `performDirectReplacement`.
- [ ] **Step 4:** `HUDState.from(_:pasteRawLetter:)`: `.inserted` with `rawReason == .detailChanged` → `.warning(title: FidelityCheck.hudTitle(issues, pastedRaw: true), detail: FidelityCheck.hudDetail(pastedRaw: true, …))`; `.inserted` with issues, `fidelityAction == .warn`, `rawReason == nil` → same with `pastedRaw: false`. Callers pass `model.settings.shortcuts.letter(for: .pasteRaw)`.
- [ ] **Step 5:** `MenuSections`: the `.rawLast` button shows "Cleaned" with help "Paste cleaned (⌃⌥<letter>)" when `result.isFidelityFallback`; otherwise unchanged.
- [ ] **Step 6: Run** `swift test` and `swift build` — expected: pass, build complete.
- [ ] **Step 7: Commit** `feat(app): paste raw swaps to cleaned after a fidelity fallback`

---

### Task 6: History tag and Style page setting

**Files:**
- Modify: `Sources/BugVoice/UI/DictationHistoryView.swift:77-105`, `Sources/BugVoice/UI/Style/StylePage.swift:39-48`

**Interfaces:**
- Consumes: `HistoryEntry.fidelityIssues`, `FidelityCheck.describe`, `StyleSettings.fidelityAction`.

- [ ] **Step 1:** History row: when `fidelityIssues` is non-empty, a caption tag in `.bvWarning` reading "raw · detail" if `rawReason == .detailChanged`, else "check"; `.help` lists `FidelityCheck.describe` lines under "Cleanup changed". Drop `.detailChanged` from the plain "raw" tag condition so the row shows one tag.
- [ ] **Step 2:** Swap button (`arrow.left.arrow.right`) before Paste again, only when `fidelityIssues` is non-empty: pastes `e.cleaned` when the fallback pasted raw, else `e.raw`, via `model.dictation?.pasteAgain(_:)`. Help: "Paste the cleaned version" / "Paste the raw version".
- [ ] **Step 3:** Style page: above the pills, a card with `Picker("When cleanup changes a number, path, name or “not”", selection: $model.settings.styles.fidelityAction)` (options "Paste raw text", "Paste cleaned text and warn", "Off") and the footnote "BugVoice compares the cleaned text with what you said. Command mode and Ask AI are not checked."
- [ ] **Step 4:** `swift build`, `Scripts/build-app.sh`; open with `Scripts/run-dev-app.sh` only when the owner agrees (it restarts the installed copy). Screenshot the Style page and History; compare with mockup sections 3 and 4.
- [ ] **Step 5: Commit** `feat(app): fidelity tag in history and setting on the Style page`

---

### Task 7: History replay and docs

**Files:**
- Modify: `Sources/BugVoiceBench/main.swift` (new mode at the top)
- Create: `docs/progress/fidelity-log.md`
- Modify: `AGENTS.md` (Key documents: plan and log), `docs/progress/HANDOFF.md`

- [ ] **Step 1:** `bugvoice-bench --fidelity-history <path>`: reads `history.jsonl` with `HistoryLog`, runs `FidelityCheck.issues(raw: entry.raw, cleaned: cleaned)` on each entry with `cleaned`, prints to stdout the entry count, flagged count and percent, counts per kind, and each flagged pair (terminal only), then exits before the clip logic. Update the usage comment.
- [ ] **Step 2:** Run it on `~/Library/Application Support/BugVoice/history.jsonl` (confirm path via `AppPaths`). Review each flagged pair by hand.
- [ ] **Step 3:** If more than 2% are false alarms, tune the allowed differences in `FidelityCheck` (adding a corpus case for each fix, TDD) and rerun; if it cannot get under 2%, change the default `fidelityAction` to `.warn` and note it.
- [ ] **Step 4:** Write `docs/progress/fidelity-log.md`: tasks done with commits, replay result (counts and true/false alarm per kind, no dictated text), timing, and device checks F1–F8 copied from the spec as unchecked boxes.
- [ ] **Step 5:** Add plan and log to `AGENTS.md` Key documents; add a short status line to `HANDOFF.md`.
- [ ] **Step 6: Commit** `docs: fidelity check log and history replay`
