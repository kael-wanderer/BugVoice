# Learn From Corrections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. If neither skill is installed, execute the plan directly, task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the owner fixes a misheard word right after a paste, BugVoice suggests adding it to the Dictionary.

**Architecture:** VoiceCore holds the pure parts, test-first: find the pasted region between two anchors, align pasted and edited words, filter misheard-word candidates, and keep suggestions in `suggestions.json`. The app watches the pasted field through Accessibility for up to 60 s after each ordinary paste, then feeds the last region it saw into VoiceCore. Suggestions show in Dictionary › Words, the popover and the sidebar.

**Tech Stack:** Swift 6 package, macOS 15, SwiftUI/AppKit, Accessibility, `NSSpellChecker`, Swift Testing. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-19-learn-from-corrections-design.md` (mockup `docs/design/proposal-corrections.html`).

## Global Constraints

- `VoiceCore` imports Foundation only. TDD for VoiceCore. `swift test` passes before every commit.
- No new dependency. Never read a secure field. Text stays on this Mac; only the changed words are stored.
- Watched: dictation outcome Inserted, not a command, not into Notes or meeting notes, style not Terminal, field not secure, setting on.
- Watch 60 s, poll every 1 s, AX timeout 0.25 s, one watch at a time; anchors 40 characters each side; value over 100,000 characters not watched.
- Candidate: 1–3 words each side, both non-empty; written side at most 40 characters; similarity at least 0.5 after folding case and diacritics, or equal when folded; at most 3 candidates per paste and at most 40% of pasted words changed.
- Limits: 50 pending (oldest dropped), 500 dismissed.
- UI copy: plain English, no hedging, no emoji; strings from the mockup and spec.
- Commit after each task; the pre-commit hook raises the build, never edit CFBundleVersion.

## Review Focus

1. The owner sends the message (field cleared) a second after fixing: the last read with the fix is used (Task 4 test `clearedFieldUsesLastSeenRegion`).
2. Text typed before or after the paste (new sentence at the end) is not mistaken for a fix (Task 1 test `textAddedAfterPasteIgnored`).
3. A word that is already in the Dictionary with that heard-as is not suggested again (Task 2 test `knownPairIgnored`).
4. A Vietnamese tone fix whose letters differ only by diacritics passes the similarity rule (Task 1 test `toneFixKept`).
5. The same pasted text appearing twice in the field: the region between the anchors is used, not the first occurrence (Task 1 test `regionUsesAnchorsNotText`).

---

### Task 1: Region, diff and filter

**Files:**
- Create: `Sources/VoiceCore/Corrections.swift`
- Test: `Tests/VoiceCoreTests/CorrectionsTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct CorrectionCandidate: Equatable, Sendable { public var heard: String; public var written: String }
  public enum CorrectionRegion {
      public static let anchorLength = 40
      public static let maxValueLength = 100_000
      /// before/after: the field text around the paste at paste time (only the last/first 40 characters are used).
      public static func find(value: String, before: String, after: String) -> String?
  }
  public enum CorrectionDiff {
      public static func words(_ text: String) -> [String]          // split on whitespace, punctuation trimmed from word edges, empty dropped
      public static func candidates(pasted: String, edited: String) -> [CorrectionCandidate]   // runs of 1–3 replaced words each side
  }
  public enum CorrectionFilter {
      public static let minSimilarity = 0.5
      public static let maxWrittenLength = 40
      public static let maxCandidates = 3
      public static let maxChangedFraction = 0.4
      public static func fold(_ text: String) -> String              // lowercased, diacritics removed, đ→d
      public static func similarity(_ a: String, _ b: String) -> Double   // 1 − Levenshtein(fold a, fold b) / max length
      public static func keep(_ candidates: [CorrectionCandidate], pasted: String) -> [CorrectionCandidate]
  }
  ```
  `find`: take `before.suffix(40)` and `after.prefix(40)`; empty anchor means start / end of value. Locate the **last** occurrence of the before anchor, then the **first** occurrence of the after anchor at or after it; the region is the text between, trimmed. Nil when an anchor is missing or `value.count > maxValueLength`.
  `candidates`: LCS over `words` (compare exactly); each maximal run where both sides changed becomes one candidate, joined by single spaces; runs with an empty side or more than 3 words on a side are skipped. Changed-word count for the 40% rule is the number of pasted words not in the LCS (expose as `CorrectionDiff.changedCount(pasted:edited:) -> Int`).
  `keep`: drop when `heard == written`, written over 40 characters, a pure case change of the first word of the paste, or `similarity < 0.5` unless `fold(heard) == fold(written)`; return `[]` when more than 3 candidates survive diffing or `changedCount / words(pasted).count > 0.4`.

- [ ] **Step 1: Write the failing tests**
  - `regionBetweenAnchors`: value `"Hi team. Thanks Kael, I'll review the build. Bye"`, before `"Hi team. "`, after `" Bye"` → `"Thanks Kael, I'll review the build."`.
  - `regionUsesAnchorsNotText`: value `"ok ok. A: ok ok. B"`, before `"A: "`, after `" B"` → `"ok ok."`.
  - `regionNilWhenAnchorGone` (value `""`), `emptyAnchorsMeanEnds` (before `""`, after `""` → whole trimmed value), `regionNilWhenTooLong` (100,001 characters).
  - `nameFix`: pasted `"Thanks Kale, I'll review the build after lunch."`, edited `"Thanks Kael, I'll review the build after lunch."` → candidates `[("Kale","Kael")]`, kept.
  - `toneFixKept`: `"đi ăn bun cha nhé"` → `"đi ăn bún chả nhé"` → kept `[("bun cha","bún chả")]`; `similarity("bun cha","bún chả") == 1`.
  - `rewordIgnored`: `"That looks good."` → `"That looks great."` → kept `[]` (similarity below 0.5).
  - `sentenceCaseIgnored`: `"the build is ready"` → `"The build is ready"` → `[]`.
  - `punctuationOnlyIgnored`: `"ok, ship it"` → `"ok — ship it"` → `[]` (no word changed after trimming).
  - `textAddedAfterPasteIgnored`: `"fix the bug"` → `"fix the bug in AppModel"` → `[]`.
  - `rewriteIgnored`: 10-word paste with 5 words replaced by look-alikes → `[]`.
  - `moreThanThreeIgnored`: 20-word paste with 4 separate one-word look-alike fixes → `[]`.
  - `fourWordRunSkipped`: a run of 4 replaced words → no candidate from it.
  - `foldHandlesD`: `fold("Đường") == "duong"`.
- [ ] **Step 2: Run** `swift test --filter CorrectionsTests` — compile failure on missing types.
- [ ] **Step 3: Implement** in `Sources/VoiceCore/Corrections.swift`. Fold with `folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)` plus `đ/Đ → d`; Levenshtein over `Character` arrays.
- [ ] **Step 4: Run tests** — PASS; full `swift test`.
- [ ] **Step 5: Commit** `feat(core): correction region, diff and filter`

### Task 2: Suggestions model and Dictionary accept

**Files:**
- Create: `Sources/VoiceCore/Suggestions.swift`
- Modify: `Sources/VoiceCore/Dictionary.swift` (accept), `Sources/VoiceCore/Settings.swift` (`SpeechSettings.learnFromCorrections = true`, tolerant decode), `Sources/VoiceCore/AppPaths.swift` (`suggestions` → `suggestions.json`), `Sources/VoiceCore/BackupPlan.swift` (`rootFiles` gains `"suggestions.json"`)
- Test: `Tests/VoiceCoreTests/SuggestionsTests.swift`, `Tests/VoiceCoreTests/SettingsTests.swift`, the backup test that covers `rootFiles`

**Interfaces:**
- Consumes: `CorrectionCandidate`.
- Produces:
  ```swift
  public struct Suggestion: Codable, Equatable, Sendable, Identifiable {
      public var id: UUID; public var written: String; public var heard: String; public var app: String?
      public var count: Int; public var lastSeen: Date; public var replace: Bool
  }
  public struct DismissedPair: Codable, Hashable, Sendable { public var written: String; public var heard: String }
  public struct SuggestionFile: Codable, Equatable, Sendable {
      public static let supportedSchemaVersion = 1; public static let maxPending = 50; public static let maxDismissed = 500
      public var schemaVersion: Int; public var pending: [Suggestion]; public var dismissed: [DismissedPair]
      /// `replace` starts false when `isRealWord(heard) && isRealWord(written)`, true otherwise.
      public mutating func record(_ candidate: CorrectionCandidate, app: String?, at: Date, dictionary: DictionaryFile,
                                  isRealWord: (String) -> Bool)
      public mutating func dismiss(id: UUID)
      public mutating func setReplace(id: UUID, _ on: Bool)
      public mutating func remove(id: UUID)
  }
  public actor SuggestionStore { public init(url: URL); public func load() -> SuggestionFile; public func save(_ file: SuggestionFile, revision: Int?) throws }
  extension DictionaryFile { public mutating func accept(_ suggestion: Suggestion) }   // add or find word (case-insensitive key), add heard-as when replace
  ```
  "Same pair" (count, dismissed, known heard-as) compares `written` exactly and `heard` case-insensitively: "Kael"/"kale" and "Kael"/"Kale" are one pair; "Kael" and "kael" are different words.

- [ ] **Step 1: Write the failing tests**
  - `recordAddsNewestFirst`, `recordCountsSamePair` (twice → one suggestion, `count == 2`, `lastSeen` updated, moved to front).
  - `dismissedNeverReturns`: dismiss then record the same pair → `pending` empty.
  - `knownPairIgnored`: dictionary has word "Kael" with heard-as "Kale" → record ignored; dictionary has "Kael" without heard-as → recorded.
  - `bothRealWordsStartWithoutReplace`: `isRealWord` true for "cell" and "sell" → `replace == false`; true for "Kale" only → `replace == true`.
  - `capsPendingAndDismissed`: 51 distinct records → 50, the oldest gone; 501 dismissals → 500.
  - `acceptAddsWordAndHeardAs`; `acceptWithoutReplaceAddsWordOnly`; `acceptExistingWordAddsHeardAs` (word "kael" exists → no duplicate, heard-as added to it).
  - `roundTripAndTolerantDecode` (`{"pending":[{"written":"Kael","heard":"Kale"}]}` decodes with count 1, replace true); `storeSurvivesCorruptFile`; `olderRevisionIsIgnored`.
  - Settings: `learnFromCorrectionsDefaultsOn`. Backup: `suggestions.json` included when present.
- [ ] **Step 2: Run** the filtered tests — failures.
- [ ] **Step 3: Implement.** The store follows `ProjectStore` (atomic write, `suggestions.corrupt-<unix>.json`, revision check).
- [ ] **Step 4: Run tests** — PASS; full `swift test`.
- [ ] **Step 5: Commit** `feat(core): dictionary suggestions`

### Task 3: Field reading and real-word check

**Files:**
- Modify: `Sources/BugVoiceMac/FocusInspector.swift`
- Create: `Sources/BugVoiceMac/RealWords.swift`
- Test: `Tests/BugVoiceMacTests/RealWordsTests.swift`

**Interfaces:**
- Produces:
  ```swift
  extension FocusInspector {
      /// kAXValueAttribute of `element` with a 0.25 s timeout; nil when unreadable, secure (SecureFocusPolicy) or over 100,000 characters.
      @MainActor public static func value(of element: AXUIElement) -> String?
  }
  public enum RealWords {
      /// True when NSSpellChecker finds no misspelling in `text` for "en" or for "vi" (only languages it has).
      @MainActor public static func isRealWord(_ text: String) -> Bool
  }
  ```
- [ ] **Step 1: Write the failing tests:** `RealWords.isRealWord("cell") == true`, `isRealWord("sell") == true`, `isRealWord("Kael") == false`, `isRealWord("Qzxv") == false`, `isRealWord("") == false`.
- [ ] **Step 2: Run** `swift test --filter RealWordsTests` — failure.
- [ ] **Step 3: Implement.** `NSSpellChecker.shared.checkSpelling(of:startingAt:language:wrap:inSpellDocumentWithTag:wordCount:)` per language in `availableLanguages` matching `en*` / `vi*`; real when any returns `NSNotFound` location.
- [ ] **Step 4: Run tests** — PASS; full `swift test`.
- [ ] **Step 5: Commit** `feat(mac): field value read and real-word check`

### Task 4: Watcher

**Files:**
- Create: `Sources/BugVoice/CorrectionWatcher.swift`
- Modify: `Sources/BugVoice/DictationController.swift` (start after an ordinary Inserted result; stop when a new recording begins), `Sources/BugVoice/AppModel.swift` (load suggestions at bootstrap; `suggestions: SuggestionFile`; `recordCorrections(_:app:)`, `acceptSuggestion(_:)`, `dismissSuggestion(_:)`, `setSuggestionReplace(_:_:)`, `acceptAllSuggestions()`)
- Test: `Tests/VoiceCoreTests/CorrectionsTests.swift` (the app has no test target, so the watch logic is the pure `CorrectionWatch` below)

**Interfaces:**
- Consumes: Tasks 1–3, `FocusInspector.focusedElement()`, `FocusInspector.isSameElement`.
- Produces (VoiceCore, test-first, in `Sources/VoiceCore/Corrections.swift`):
  ```swift
  public struct CorrectionWatch: Sendable {
      public init(pasted: String, before: String, after: String)
      /// Feed each poll. Returns false when the watch should end (anchors gone after a region was seen, or value nil).
      public mutating func observe(value: String?) -> Bool
      public var lastRegion: String? { get }
      public func result() -> [CorrectionCandidate]        // keep(candidates(pasted, lastRegion)) or []
  }
  ```
  App: `CorrectionWatcher.start(pasted:focus:app:)` captures `FocusInspector.focusedElement()` and anchors `focus.beforeText ?? ""`, `focus.afterText ?? ""`; a main-actor task polls every 1 s for 60 s; ends early when `observe` returns false, the focused element is no longer the same, or `stop()` is called; on end it calls `model.recordCorrections(watch.result(), app:)`. Starting a new watch ends the previous one first (its result is still recorded).

- [ ] **Step 1: Write the failing tests** (`CorrectionsTests`):
  - `watchUsesLatestRegion`: observe pasted value, then the fixed value → `result() == [("Kale","Kael")]`.
  - `clearedFieldUsesLastSeenRegion`: observe the fixed value, then `""` → `observe` returns false, `result()` still has the fix.
  - `unchangedGivesNothing`, `nilValueEnds`.
- [ ] **Step 2: Run** — failures. **Step 3: Implement** `CorrectionWatch` and the app watcher. Start conditions in `DictationController` after the pipeline result: `result.outcome == .inserted`, not into Notes or meeting notes, `result.style != .terminal`, `!focus.isSecure`, `model.settings.speech.learnFromCorrections`. `begin(handsFree:notesOnly:)` and command mode start call `stop()`.
- [ ] **Step 4:** `swift test`; `Scripts/build-app.sh`.
- [ ] **Step 5: Commit** `feat(app): watch pasted fields for corrections`

### Task 5: Suggestions UI and setting

**Files:**
- Create: `Sources/BugVoice/UI/Dictionary/SuggestionsCard.swift`
- Modify: `Sources/BugVoice/UI/Dictionary/DictionaryWordsView.swift` (card above the list), `Sources/BugVoice/UI/Menu/MenuPopover.swift` / `MenuSections.swift` (line under Last dictation), the sidebar Dictionary item (badge), `Sources/BugVoice/UI/Settings/SpeechTab.swift`

- [ ] **Step 1: Card** per mockup screen 2, hidden when empty: title "Suggestions", subtitle "Words you fixed after a paste.", **Add all**; rows newest first: written word, "heard as “Kale” · Slack · 2 times" ("1 time" singular), "Last seen 10:42", switch "Replace every time", **Add**, **Dismiss**; when both sides are real words (`RealWords.isRealWord`) the second line reads "“cell” and “sell” are both real words — added as a spelling hint only" while the switch is off; when both sides fold equal it reads "Vietnamese tone fix".
- [ ] **Step 2: Popover** line "2 Dictionary suggestions" with count badge, opening Dictionary › Words; hidden at 0. **Sidebar** Dictionary badge with the count, hidden at 0.
- [ ] **Step 3: Settings › Speech** switch "Learn from corrections" with the spec footnote verbatim; off stops the current watch and keeps suggestions.
- [ ] **Step 4:** `swift test`, `Scripts/build-app.sh`; read-only smoke: Settings › Speech row and an empty Dictionary › Words render.
- [ ] **Step 5: Commit** `feat(app): dictionary suggestions UI`

### Task 6: Docs and device checks

**Files:**
- Create: `docs/progress/corrections-log.md`
- Modify: `AGENTS.md` (plan and log lines), `docs/progress/HANDOFF.md`, `docs/propose-new-features.md` (item 2 status)

- [ ] **Step 1:** Log: commits, test counts per target, deviations, then device checks with Result / Evidence:
  - K1 Slack: dictate a name, fix it, send within 5 s → suggestion "heard as …" with the app.
  - K2 Notion: Vietnamese tone fix → "Vietnamese tone fix" row.
  - K3 Reword "good" to "great" → no suggestion.
  - K4 Fix the same word twice in two dictations → one row, "2 times".
  - K5 Add with Replace every time → next dictation spells it right; Dictionary shows the heard-as.
  - K6 Both real words ("cell" fixed to "sell") start with the switch off; Add adds the word only.
  - K7 Dismiss → the same fix later is not suggested.
  - K8 Ghostty and a password field → nothing watched (no suggestion).
  - K9 Setting off → no new suggestions; popover and sidebar counts update.
  - K10 Backup and restore keep suggestions and dismissed pairs.
- [ ] **Step 2:** `swift test`; commit `docs: corrections log and handoff`.
