# Dictionary, Snippets and Style Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Settings → Vocabulary and Settings → Styles with a Dictionary page (words with heard-as corrections, and snippets) and a Style page (six app-chosen styles), and run every dictation through corrections → snippet placeholders → cleanup → fill.

**Architecture:** `VoiceCore` gains `DictionaryFile` (records + edit rules), `DictionaryStore` (actor owning `dictionary.json`, migration from `vocabulary.txt`), and `SnippetExpander` (trigger → `⟦S1⟧` placeholder → exact text). `Style` loses `chat` and gains `personal` and `work`, with legacy decoding. `DictationPipeline` protects snippets before the text model and fills them after. The app keeps a `DictionaryFile` in `AppModel`, rebuilds `Vocabulary` from it on every edit, and shows two new SwiftUI pages.

**Tech Stack:** Swift 6.4, tools 6.0, macOS 15, SwiftUI + AppKit, swift-testing. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-15-dictionary-style-design.md`. Mockup: `docs/design/proposal-dictionary-style.html`.

## Global Constraints

- Swift package, tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only.
- Exactly one external dependency: WhisperKit `exact: "1.1.1"`. Add nothing.
- TDD for everything in `VoiceCore`: failing test first, then code. `swift test` must pass before every commit (currently 278 VoiceCore + 60 BugVoiceMac tests, plus the ones you add).
- Build the app only with `Scripts/build-app.sh` (signs with `Bugler Local Dev`). Never change signing.
- Never send audio or text off this Mac unless the user configured a remote server. Snippet text never goes to the text model.
- UI copy: plain English, no hedging words, no emoji. Use the copy in the spec and this plan exactly.
- Commit after each task: `feat(core): …`, `feat(app): …`, `docs: …`, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Commit only the task's files, by path (`git commit -m … -- <paths>`); never `git add -A`.
- Search with `rg`, not grep/find.
- `dictionary.json` lives at `~/Library/Application Support/BugVoice/dictionary.json` (`AppPaths.dictionary`), `schemaVersion` 1.
- Placeholders are `⟦S1⟧`, `⟦S2⟧`, … (U+27E6, U+27E7). Prompt line, verbatim: `Tokens like ⟦S1⟧ are placeholders. Keep every one exactly once, unchanged, where it belongs.`
- Style display names: Personal messages, Work messages, Email, Document, Terminal, Other.

## Review Focus

1. **Bootstrap order.** `await loadDictionary()` must run before `startDictation()` in `AppModel.bootstrap()`; a dictation in the first second after launch must already use the Dictionary. Pinned by Task 7 Step 3 (code placement) and checked in review.
2. **Model mangles a placeholder.** The model drops, duplicates, rewrites (`[S1]`) or invents (`⟦S3⟧`) a placeholder: the cleaned text is discarded, `rawReason == .placeholderLost`, and the snippet is still filled exactly. Pinned by Task 5 `isIntact` tests and Task 6 pipeline tests.
3. **Old data with `chat`.** A `settings.json` with `"chat"` overrides, rules or cleanup flags, and `history.jsonl` lines with `"style":"chat"`, load without losing anything. Pinned by Task 1 `historyEntryWithChatStyleStillDecodes` and Task 2 legacy tests.
4. **Migration never loses `vocabulary.txt`.** `dictionary.json` is written before `vocabulary.txt` is renamed; an existing `dictionary.json` is never overwritten by migration; a damaged file is kept aside. Pinned by Task 4 store tests.
5. **Two quick edits both persist.** Adding two heard-as forms in quick succession keeps both: memory is updated before the save, and the store ignores a save older than the last one written. Pinned by Task 4 `olderRevisionIsIgnored` and Task 7's `editDictionary`.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/VoiceCore/Settings.swift` (modify) | `Style` cases, `title`, legacy `chat` decoding; `StyleSettings` legacy migration |
| `Sources/VoiceCore/StyleRouter.swift` (modify) | New built-in apps and website rules; `builtInApps(for:)`, `websites(for:)` |
| `Sources/VoiceCore/PromptBuilder.swift` (modify) | New default rules; placeholder line |
| `Sources/VoiceCore/Dictionary.swift` (create) | `DictionaryWord`, `Snippet`, `DictionaryFile`, `DictionaryError`, edit rules |
| `Sources/VoiceCore/DictionaryStore.swift` (create) | Actor owning `dictionary.json`: load, save, migrate |
| `Sources/VoiceCore/SnippetExpander.swift` (create) | `protect`, `ProtectedText.isIntact`, `ProtectedText.fill` |
| `Sources/VoiceCore/Vocabulary.swift` (modify) | `snippets`, `init(dictionary:)` |
| `Sources/VoiceCore/AppPaths.swift` (modify) | `dictionary` URL |
| `Sources/VoiceCore/OutputSanitizer.swift` (modify) | `RawReason.placeholderLost` |
| `Sources/VoiceCore/DictationPipeline.swift` (modify) | Pipeline order (spec §4) |
| `Sources/BugVoice/AppModel.swift` (modify) | Dictionary state, load/migrate, edits; `Page.dictionary`, `Page.style`; remove vocabulary text |
| `Sources/BugVoice/UI/MainWindow.swift` (modify) | Route the two pages |
| `Sources/BugVoice/UI/Components/FlowLayout.swift` (create) | Wrapping row layout for tags and chips |
| `Sources/BugVoice/UI/Dictionary/HeroCard.swift` (create) | Shared hero card with add field and illustration |
| `Sources/BugVoice/UI/Dictionary/DictionaryPage.swift` (create) | Page title + tabs |
| `Sources/BugVoice/UI/Dictionary/DictionaryWordsView.swift` (create) | Words hero, list, rows |
| `Sources/BugVoice/UI/Dictionary/SnippetsView.swift` (create) | Snippets hero, list, rows |
| `Sources/BugVoice/UI/Dictionary/SnippetEditorSheet.swift` (create) | Add/edit snippet sheet |
| `Sources/BugVoice/UI/Style/StylePage.swift` (create) | Style list + app entries |
| `Sources/BugVoice/UI/Style/StyleDetailView.swift` (create) | Apps, cleanup switch, tone, example |
| `Sources/BugVoice/UI/Style/StyleExamples.swift` (create) | Static example pairs |
| `Sources/BugVoice/UI/Settings/*` (modify/delete) | Remove Vocabulary and Styles tabs; Speech label |
| `Sources/BugVoice/UI/Insights/InsightsUsageView.swift` (modify) | Style titles, "Chat (old)" |
| `Sources/BugVoice/HUD/HUDState.swift`, `UI/DictationHistoryView.swift` (modify) | `placeholderLost`; style titles |
| `docs/testing/manual-checklist.md`, `docs/ROADMAP.md` (modify) | Checks 81–90; roadmap note |

---

### Task 1: Six styles

**Files:**
- Modify: `Sources/VoiceCore/Settings.swift:3-5`
- Modify: `Sources/VoiceCore/StyleRouter.swift`
- Modify: `Sources/VoiceCore/PromptBuilder.swift:12-24`
- Create: `Tests/VoiceCoreTests/StyleTests.swift`
- Modify: `Tests/VoiceCoreTests/StyleRouterTests.swift`, `Tests/VoiceCoreTests/PromptTests.swift:20-41`, `Tests/VoiceCoreTests/CancellationTests.swift:60`, `Tests/VoiceCoreTests/SettingsTests.swift:52-58`

**Interfaces:**
- Produces: `Style` cases `personal, work, email, document, terminal, other` (this order is `allCases`); `Style.title: String`; decoding `"chat"` yields `.personal`; `StyleRouter.builtInApps(for: Style) -> [String]` (sorted), `StyleRouter.websites(for: Style) -> [String]` (table order); `StyleRouter.defaultApps` keeps its name and type.

- [ ] **Step 1: Write the failing tests**

Create `Tests/VoiceCoreTests/StyleTests.swift`:

```swift
import Foundation
import Testing
@testable import VoiceCore

struct StyleTests {
    @Test func legacyChatDecodesAsPersonal() throws {
        let styles = try JSONDecoder().decode([Style].self, from: Data(#"["chat","work","terminal"]"#.utf8))
        #expect(styles == [.personal, .work, .terminal])
    }

    @Test func unknownStyleStillFailsToDecode() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Style.self, from: Data(#""poem""#.utf8))
        }
    }

    @Test func encodesRawValue() throws {
        let data = try JSONEncoder().encode([Style.personal, .work])
        #expect(String(decoding: data, as: UTF8.self) == #"["personal","work"]"#)
    }

    @Test func titlesInPageOrder() {
        #expect(Style.allCases.map(\.title) == [
            "Personal messages", "Work messages", "Email", "Document", "Terminal", "Other",
        ])
    }

    @Test func historyEntryWithChatStyleStillDecodes() throws {
        let entry = HistoryEntry(
            id: UUID(), startedAt: Date(timeIntervalSince1970: 0), appName: "Slack",
            bundleID: "com.tinyspeck.slackmacgap", style: .personal, language: "en",
            raw: "hi", cleaned: nil, text: "hi", outcome: "inserted", rawReason: nil,
            timings: StageTimings(recording: 1)
        )
        let json = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
            .replacingOccurrences(of: #""style":"personal""#, with: #""style":"chat""#)
        #expect(json.contains(#""style":"chat""#))
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: Data(json.utf8))
        #expect(decoded.style == .personal)
        #expect(decoded.text == "hi")
    }
}
```

Replace the body of `Tests/VoiceCoreTests/StyleRouterTests.swift` from the `@Test(arguments:` of `defaultApps` through the end of `browserURLDecidesStyle` with the version below, and keep any other tests in the file unchanged (change any remaining `.chat` in that file to `.work`):

```swift
    @Test(arguments: [
        ("com.apple.Terminal", Style.terminal),
        ("com.googlecode.iterm2", .terminal),
        ("dev.warp.Warp-Stable", .terminal),
        ("com.mitchellh.ghostty", .terminal),
        ("notion.id", .document),
        ("md.obsidian", .document),
        ("com.apple.MobileSMS", .personal),
        ("com.vng.zalo", .personal),
        ("net.whatsapp.WhatsApp", .personal),
        ("ru.keepcoder.Telegram", .personal),
        ("com.hnc.Discord", .personal),
        ("com.facebook.archon", .personal),
        ("com.tinyspeck.slackmacgap", .work),
        ("com.microsoft.teams2", .work),
        ("com.microsoft.teams", .work),
        ("com.electron.lark", .work),
        ("com.apple.mail", .email),
        ("com.example.unknown", .other),
    ])
    func defaultApps(bundleID: String, expected: Style) {
        #expect(router.style(for: FocusSnapshot(bundleID: bundleID)) == expected)
    }

    @Test func vsCodeTerminalPanelIsTerminalButEditorIsOther() {
        #expect(router.style(for: FocusSnapshot(bundleID: "com.microsoft.VSCode", isTerminalPanel: true)) == .terminal)
        #expect(router.style(for: FocusSnapshot(bundleID: "com.microsoft.VSCode")) == .other)
    }

    @Test(arguments: [
        ("https://docs.google.com/document/d/1", Style.document),
        ("https://mail.google.com/mail/u/0", .email),
        ("https://web.whatsapp.com/", .personal),
        ("https://www.messenger.com/t/1", .personal),
        ("https://discord.com/channels/1", .personal),
        ("https://web.telegram.org/a/", .personal),
        ("https://chat.zalo.me/", .personal),
        ("https://app.slack.com/client/T1", .work),
        ("https://teams.microsoft.com/v2/", .work),
        ("https://teams.live.com/v2/", .work),
        ("https://chat.google.com/room/1", .work),
        ("https://example.com/", .other),
    ])
    func browserURLDecidesStyle(url: String, expected: Style) {
        #expect(router.style(for: FocusSnapshot(bundleID: "com.google.Chrome", url: url)) == expected)
    }

    @Test func overrideStillWins() {
        let router = StyleRouter(overrides: ["ru.keepcoder.Telegram": .work])
        #expect(router.style(for: FocusSnapshot(bundleID: "ru.keepcoder.Telegram")) == .work)
    }

    @Test func builtInAppsAndWebsitesPerStyle() {
        #expect(StyleRouter.builtInApps(for: .work) == [
            "com.electron.lark", "com.microsoft.teams", "com.microsoft.teams2", "com.tinyspeck.slackmacgap",
        ])
        #expect(StyleRouter.builtInApps(for: .other).isEmpty)
        #expect(StyleRouter.websites(for: .personal) == [
            "web.whatsapp.com", "messenger.com", "discord.com", "web.telegram.org", "chat.zalo.me",
        ])
        #expect(StyleRouter.websites(for: .terminal).isEmpty)
    }
```

In `Tests/VoiceCoreTests/PromptTests.swift`, replace `customRulesReplaceBuiltIn` and `userTurnWrapsDictationAndAddsNoThinkForQwen` and add `newDefaultRules`:

```swift
    @Test func customRulesReplaceBuiltIn() {
        let p = PromptBuilder(customRules: ["work": "Only lowercase."]).systemPrompt(style: .work, vocabulary: Vocabulary(), focus: .unknown)
        #expect(p.contains("Only lowercase."))
        #expect(!p.contains(PromptBuilder.defaultRules(for: .work)))
    }

    @Test func newDefaultRules() {
        #expect(PromptBuilder.defaultRules(for: .personal).hasPrefix("Casual and warm."))
        #expect(PromptBuilder.defaultRules(for: .personal).contains("No greeting or sign-off unless spoken."))
        #expect(PromptBuilder.defaultRules(for: .work).hasPrefix("Clear and short."))
        #expect(PromptBuilder.defaultRules(for: .work).contains("when the speaker lists items, use bullets"))
        #expect(PromptBuilder.defaultRules(for: .other).hasPrefix("Light touch."))
    }

    @Test func userTurnWrapsDictationAndAddsNoThinkForQwen() {
        let r = PromptBuilder().request(raw: "hello", style: .personal, focus: .unknown, vocabulary: Vocabulary(), modelID: "qwen3.8-27b-mlx", disableThinking: true)
        #expect(r.user == "<dictation>\nhello\n</dictation>\n\n/no_think")
        let r2 = PromptBuilder().request(raw: "hello", style: .personal, focus: .unknown, vocabulary: Vocabulary(), modelID: "llama-3", disableThinking: true)
        #expect(r2.user == "<dictation>\nhello\n</dictation>")
        #expect(r.disableThinking)
        #expect(!r2.disableThinking)
    }
```

In `Tests/VoiceCoreTests/CancellationTests.swift:60` change `style: .chat` to `style: .personal`.

In `Tests/VoiceCoreTests/SettingsTests.swift`, `unknownStyleInAppOverridesDropsOnlyThatEntry` no longer compiles (`.chat` is gone). Leave the JSON as is and change the expectation to what the decoder does until Task 2 (`"chat"` is an unknown raw value, so it is dropped):

```swift
        #expect(overrides == ["com.a": .document])
```

Task 2 changes it to expect `"com.c": .personal`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'StyleTests|StyleRouterTests|PromptTests'`
Expected: build FAILS — `type 'Style' has no member 'personal'`.

- [ ] **Step 3: Implement**

In `Sources/VoiceCore/Settings.swift` replace the `Style` enum:

```swift
public enum Style: String, Codable, Sendable, CaseIterable {
    case personal, work, email, document, terminal, other

    /// Name shown on the Style page, the HUD and Insights.
    public var title: String {
        switch self {
        case .personal: "Personal messages"
        case .work: "Work messages"
        case .email: "Email"
        case .document: "Document"
        case .terminal: "Terminal"
        case .other: "Other"
        }
    }
}

extension Style {
    /// `chat` was split into `personal` and `work`. Anything stored with it
    /// (history lines, settings) loads as `personal`.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "chat" {
            self = .personal
        } else if let style = Style(rawValue: raw) {
            self = style
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown style \(raw)"))
        }
    }
}
```

In `Sources/VoiceCore/StyleRouter.swift` replace `defaultApps` and `urlRules`, and add the two lookups after `urlRules`:

```swift
    public static let defaultApps: [String: Style] = [
        "com.apple.Terminal": .terminal,
        "com.googlecode.iterm2": .terminal,
        "dev.warp.Warp-Stable": .terminal,
        "com.mitchellh.ghostty": .terminal,
        "notion.id": .document,
        "md.obsidian": .document,
        "com.apple.iWork.Pages": .document,
        "com.microsoft.Word": .document,
        "com.apple.TextEdit": .document,
        "com.apple.MobileSMS": .personal,
        "com.vng.zalo": .personal,
        "net.whatsapp.WhatsApp": .personal,
        "ru.keepcoder.Telegram": .personal,
        "com.hnc.Discord": .personal,
        "com.facebook.archon": .personal, // Messenger
        "com.tinyspeck.slackmacgap": .work,
        "com.microsoft.teams2": .work,
        "com.microsoft.teams": .work,
        "com.electron.lark": .work,
        "com.apple.mail": .email,
        "com.microsoft.Outlook": .email,
    ]
```

```swift
    static let urlRules: [(host: String, style: Style)] = [
        ("docs.google.com", .document),
        ("notion.so", .document),
        ("mail.google.com", .email),
        ("outlook.office.com", .email),
        ("web.whatsapp.com", .personal),
        ("messenger.com", .personal),
        ("discord.com", .personal),
        ("web.telegram.org", .personal),
        ("chat.zalo.me", .personal),
        ("app.slack.com", .work),
        ("teams.microsoft.com", .work),
        ("teams.live.com", .work),
        ("chat.google.com", .work),
    ]

    /// Bundle IDs routed to `style` with no override, sorted.
    public static func builtInApps(for style: Style) -> [String] {
        defaultApps.filter { $0.value == style }.map(\.key).sorted()
    }

    /// Website hosts routed to `style`, in rule order.
    public static func websites(for style: Style) -> [String] {
        urlRules.filter { $0.style == style }.map(\.host)
    }
```

In `Sources/VoiceCore/PromptBuilder.swift` replace the `case .chat, .other:` arm with:

```swift
        case .personal:
            "Casual and warm. Remove filler words, add light punctuation, keep slang and the speaker's wording. No greeting or sign-off unless spoken."
        case .work:
            "Clear and short. Remove filler words, apply self-corrections such as \"no, I mean\" or \"à không\" by keeping only the corrected version, keep technical terms. One short paragraph; when the speaker lists items, use bullets."
        case .other:
            "Light touch. Remove filler words, add punctuation, keep the casual tone and wording."
```

Then run `rg -n '\.chat\b' Sources Tests` and fix any remaining use (expected: none in `Sources`; app code uses `rawValue.capitalized`, which still compiles and is replaced in Task 8).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter 'StyleTests|StyleRouterTests|PromptTests|CancellationTests'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
swift test
git commit -m "feat(core): split chat into personal and work styles

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/VoiceCore/Settings.swift Sources/VoiceCore/StyleRouter.swift Sources/VoiceCore/PromptBuilder.swift Tests/VoiceCoreTests/StyleTests.swift Tests/VoiceCoreTests/StyleRouterTests.swift Tests/VoiceCoreTests/PromptTests.swift Tests/VoiceCoreTests/CancellationTests.swift Tests/VoiceCoreTests/SettingsTests.swift
```

---

### Task 2: Legacy `chat` in style settings

**Files:**
- Modify: `Sources/VoiceCore/Settings.swift` (`extension StyleSettings` decoder)
- Test: `Tests/VoiceCoreTests/SettingsTests.swift`

**Interfaces:**
- Consumes: `StyleRouter.defaultApps` (Task 1).
- Produces: `StyleSettings` decoding that maps `"chat"` overrides to the bundle's built-in `.work`/`.personal`, else `.personal`, and moves `"chat"` keys of `customRules`/`cleanupEnabled` to `personal` and `work`.

- [ ] **Step 1: Write the failing tests**

In `SettingsTests.unknownStyleInAppOverridesDropsOnlyThatEntry` set the expectation to `["com.a": .document, "com.c": .personal]`, and add:

```swift
    @Test func legacyChatOverrideFollowsBuiltInStyle() throws {
        let url = tempDir().appendingPathComponent("settings.json")
        let json = #"{"styles":{"appOverrides":{"com.tinyspeck.slackmacgap":"chat","com.vng.zalo":"chat","com.example.x":"chat","com.a":"document"}}}"#
        try Data(json.utf8).write(to: url)
        #expect(SettingsStore(url: url).load().styles.appOverrides == [
            "com.tinyspeck.slackmacgap": .work,
            "com.vng.zalo": .personal,
            "com.example.x": .personal,
            "com.a": .document,
        ])
    }

    @Test func legacyChatRulesAndCleanupCopyWithoutOverwriting() throws {
        let url = tempDir().appendingPathComponent("settings.json")
        let json = #"{"styles":{"customRules":{"chat":"Only lowercase.","work":"Mine."},"cleanupEnabled":{"chat":false,"terminal":false}}}"#
        try Data(json.utf8).write(to: url)
        let styles = SettingsStore(url: url).load().styles
        #expect(styles.customRules == ["personal": "Only lowercase.", "work": "Mine."])
        #expect(styles.cleanupEnabled == ["personal": false, "work": false, "terminal": false])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SettingsTests`
Expected: FAIL — the three tests above (`"chat"` is dropped or kept as a key).

- [ ] **Step 3: Implement**

Replace `extension StyleSettings { public init(from:) … }` in `Sources/VoiceCore/Settings.swift`:

```swift
extension StyleSettings {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cleanupEnabled = c.value(.cleanupEnabled, default: cleanupEnabled)
        // Decoded as strings so one unknown style drops only its own entry.
        let rawOverrides: [String: String] = c.value(.appOverrides, default: [:])
        appOverrides = rawOverrides.reduce(into: [:]) { result, entry in
            if entry.value == Self.legacyChat {
                result[entry.key] = StyleRouter.defaultApps[entry.key] == .work ? .work : .personal
            } else if let style = Style(rawValue: entry.value) {
                result[entry.key] = style
            }
        }
        customRules = c.value(.customRules, default: customRules)
        Self.splitLegacyChat(&cleanupEnabled)
        Self.splitLegacyChat(&customRules)
    }

    static let legacyChat = "chat"

    /// Moves a `chat` value to `personal` and `work`, keeping values already there.
    static func splitLegacyChat<Value>(_ values: inout [String: Value]) {
        guard let value = values.removeValue(forKey: legacyChat) else { return }
        for style in [Style.personal, .work] where values[style.rawValue] == nil {
            values[style.rawValue] = value
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SettingsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
swift test
git commit -m "feat(core): migrate chat style settings to personal and work

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/VoiceCore/Settings.swift Tests/VoiceCoreTests/SettingsTests.swift
```

---

### Task 3: Dictionary records and edit rules

**Files:**
- Create: `Sources/VoiceCore/Dictionary.swift`
- Modify: `Sources/VoiceCore/AppPaths.swift`
- Test: `Tests/VoiceCoreTests/DictionaryFileTests.swift`

**Interfaces:**
- Produces:
  - `public struct DictionaryWord: Codable, Equatable, Sendable, Identifiable { id: UUID; word: String; heardAs: [String]; init(id: UUID = UUID(), word: String, heardAs: [String] = []) }`
  - `public struct Snippet: Codable, Equatable, Sendable, Identifiable { id: UUID; trigger: String; text: String; init(id: UUID = UUID(), trigger: String, text: String) }`
  - `public enum DictionaryError: Error, Equatable, LocalizedError { case emptyTrigger, emptyText, duplicateTrigger }`
  - `public struct DictionaryFile: Codable, Equatable, Sendable` with `static let supportedSchemaVersion = 1`, `schemaVersion`, `words`, `snippets`, `init(words:snippets:)`, `init(migrating: Vocabulary)`, and mutating `addWords(_:) -> Int` (discardable), `addHeardAs(_:to:)`, `removeHeardAs(_:from:)`, `renameWord(_:to:) -> Bool` (discardable), `deleteWord(_:)`, `addSnippet(trigger:text:) throws -> Snippet` (discardable), `updateSnippet(_:trigger:text:) throws`, `deleteSnippet(_:)`.
  - `AppPaths.dictionary: URL`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/VoiceCoreTests/DictionaryFileTests.swift`:

```swift
import Foundation
import Testing
@testable import VoiceCore

struct DictionaryFileTests {
    @Test func addWordsSplitsOnCommasTrimsAndPutsNewestFirst() {
        var f = DictionaryFile()
        f.addWords("Kael")
        let added = f.addWords(" OpenWhispr ,Supabase,, ")
        #expect(added == 2)
        #expect(f.words.map(\.word) == ["OpenWhispr", "Supabase", "Kael"])
    }

    @Test func addWordsSkipsCaseInsensitiveDuplicates() {
        var f = DictionaryFile()
        f.addWords("BugVoice")
        let added = f.addWords("bugvoice, BUGVOICE, WhisperKit, whisperkit")
        #expect(added == 1)
        #expect(f.words.map(\.word) == ["WhisperKit", "BugVoice"])
    }

    @Test func heardAsAddsTrimmedUniqueFormsAndDropsTheWordItself() {
        var f = DictionaryFile()
        f.addWords("OpenWhispr")
        let id = f.words[0].id
        f.addHeardAs("open whisper, Open Whisper, openwhispr, , open whispers ", to: id)
        #expect(f.words[0].heardAs == ["open whisper", "open whispers"])
    }

    @Test func removeHeardAsIsCaseInsensitive() {
        var f = DictionaryFile()
        f.addWords("OpenWhispr")
        let id = f.words[0].id
        f.addHeardAs("open whisper, open whispers", to: id)
        f.removeHeardAs("Open Whisper", from: id)
        #expect(f.words[0].heardAs == ["open whispers"])
    }

    @Test func renameKeepsIdDropsMatchingHeardAsAndRejectsEmptyOrDuplicate() {
        var f = DictionaryFile()
        f.addWords("Kael, Open Whisper")
        let id = f.words[1].id
        f.addHeardAs("openwhispr, open whisper app", to: id)
        #expect(f.renameWord(id, to: " OpenWhispr "))
        #expect(f.words[1].id == id)
        #expect(f.words[1].word == "OpenWhispr")
        #expect(f.words[1].heardAs == ["open whisper app"])
        #expect(!f.renameWord(id, to: "  "))
        #expect(!f.renameWord(id, to: "kael"))
        #expect(f.words[1].word == "OpenWhispr")
    }

    @Test func deleteWord() {
        var f = DictionaryFile()
        f.addWords("Kael, BugVoice")
        f.deleteWord(f.words[0].id)
        #expect(f.words.map(\.word) == ["BugVoice"])
    }

    @Test func addSnippetTrimsEndsKeepsInnerLineBreaksNewestFirst() throws {
        var f = DictionaryFile()
        try f.addSnippet(trigger: " sign off ", text: "\n Best,\nKael \n")
        try f.addSnippet(trigger: "my linkedin", text: "linkedin.com/in/kael")
        #expect(f.snippets.map(\.trigger) == ["my linkedin", "sign off"])
        #expect(f.snippets[1].text == "Best,\nKael")
    }

    @Test func duplicateTriggerIsRejected() throws {
        var f = DictionaryFile()
        try f.addSnippet(trigger: "my linkedin", text: "a")
        #expect(throws: DictionaryError.duplicateTrigger) {
            try f.addSnippet(trigger: "My LinkedIn", text: "b")
        }
        #expect(f.snippets.count == 1)
        #expect(DictionaryError.duplicateTrigger.localizedDescription == "A snippet with this trigger already exists.")
    }

    @Test func emptyTriggerOrTextIsRejected() {
        var f = DictionaryFile()
        #expect(throws: DictionaryError.emptyTrigger) { try f.addSnippet(trigger: " ", text: "a") }
        #expect(throws: DictionaryError.emptyText) { try f.addSnippet(trigger: "a", text: " \n ") }
        #expect(f.snippets.isEmpty)
    }

    @Test func updateSnippetChecksOtherTriggersOnly() throws {
        var f = DictionaryFile()
        let a = try f.addSnippet(trigger: "cal link", text: "cal.com/kael")
        try f.addSnippet(trigger: "my linkedin", text: "linkedin.com/in/kael")
        try f.updateSnippet(a.id, trigger: "Cal Link", text: "cal.com/kael/30")
        #expect(f.snippets[1].trigger == "Cal Link")
        #expect(f.snippets[1].text == "cal.com/kael/30")
        #expect(throws: DictionaryError.duplicateTrigger) {
            try f.updateSnippet(a.id, trigger: "my linkedin", text: "x")
        }
    }

    @Test func deleteSnippet() throws {
        var f = DictionaryFile()
        let a = try f.addSnippet(trigger: "cal link", text: "cal.com/kael")
        f.deleteSnippet(a.id)
        #expect(f.snippets.isEmpty)
    }

    @Test func decodingSkipsBadEntriesAndFillsDefaults() throws {
        let json = #"""
        {"words":[{"word":"Kael"},{"heardAs":["x"]},{"id":"6F1C2E4A-0000-0000-0000-000000000001","word":"BugVoice","heardAs":["bug voice"]}],
         "snippets":[{"trigger":"cal","text":"cal.com/kael"},{"trigger":"x"}]}
        """#
        let f = try JSONDecoder().decode(DictionaryFile.self, from: Data(json.utf8))
        #expect(f.schemaVersion == 1)
        #expect(f.words.map(\.word) == ["Kael", "BugVoice"])
        #expect(f.words[1].heardAs == ["bug voice"])
        #expect(f.words[0].heardAs.isEmpty)
        #expect(f.snippets.map(\.trigger) == ["cal"])
    }

    @Test func migratingVocabularyKeepsLaterLinesNewest() {
        let v = Vocabulary.parse("BugVoice\nWhisperKit\nbugvoice\nmy linkedin => linkedin.com/in/kael\nsign off => Best,\\nKael\nempty =>\n")
        let f = DictionaryFile(migrating: v)
        #expect(f.words.map(\.word) == ["WhisperKit", "BugVoice"])
        #expect(f.snippets.map(\.trigger) == ["sign off", "my linkedin"])
        #expect(f.snippets[0].text == "Best,\nKael")
    }
}
```

Note: `Vocabulary.parse` dedupes terms case-sensitively, so `bugvoice` reaches `DictionaryFile(migrating:)`, which drops it case-insensitively.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DictionaryFileTests`
Expected: build FAILS — `cannot find 'DictionaryFile' in scope`.

- [ ] **Step 3: Implement**

Create `Sources/VoiceCore/Dictionary.swift`:

```swift
import Foundation

/// A word BugVoice must spell right, and the forms speech recognition
/// mishears it as. Heard-as forms are replaced by the word.
public struct DictionaryWord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var word: String
    public var heardAs: [String]

    public init(id: UUID = UUID(), word: String, heardAs: [String] = []) {
        self.id = id
        self.word = word
        self.heardAs = heardAs
    }
}

/// A spoken trigger replaced by saved text, exactly.
public struct Snippet: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var trigger: String
    public var text: String

    public init(id: UUID = UUID(), trigger: String, text: String) {
        self.id = id
        self.trigger = trigger
        self.text = text
    }
}

public enum DictionaryError: Error, Equatable, LocalizedError {
    case emptyTrigger, emptyText, duplicateTrigger

    public var errorDescription: String? {
        switch self {
        case .emptyTrigger: "Enter a trigger phrase."
        case .emptyText: "Enter the text to insert."
        case .duplicateTrigger: "A snippet with this trigger already exists."
        }
    }
}

/// Contents of `dictionary.json`. Both lists are newest first.
public struct DictionaryFile: Codable, Equatable, Sendable {
    public static let supportedSchemaVersion = 1

    public var schemaVersion = DictionaryFile.supportedSchemaVersion
    public var words: [DictionaryWord] = []
    public var snippets: [Snippet] = []

    public init(words: [DictionaryWord] = [], snippets: [Snippet] = []) {
        self.words = words
        self.snippets = snippets
    }

    /// From `vocabulary.txt`: terms become words, `spoken => written` lines
    /// become snippets. Later lines count as newer.
    public init(migrating vocabulary: Vocabulary) {
        self.init()
        for term in vocabulary.terms { insertWord(term) }
        for replacement in vocabulary.replacements {
            _ = try? addSnippet(trigger: replacement.spoken, text: replacement.written)
        }
    }
}

// Tolerant decoding: one unreadable entry drops only itself.
extension DictionaryWord {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        word = try c.decode(String.self, forKey: .word)
        heardAs = c.value(.heardAs, default: [])
    }
}

extension Snippet {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        trigger = try c.decode(String.self, forKey: .trigger)
        text = try c.decode(String.self, forKey: .text)
    }
}

extension DictionaryFile {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.value(.schemaVersion, default: schemaVersion)
        words = c.value(.words, default: [LossyElement<DictionaryWord>]()).compactMap(\.value)
        snippets = c.value(.snippets, default: [LossyElement<Snippet>]()).compactMap(\.value)
    }
}

/// One array element, or nil when it cannot be decoded.
struct LossyElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: Edits

extension DictionaryFile {
    /// Comparison key: NFC, case-insensitive.
    static func key(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parts(_ text: String) -> [String] {
        text.split(separator: ",").map { trimmed(String($0)) }.filter { !$0.isEmpty }
    }

    /// Adds each comma-separated word not already present, at the top in the
    /// order typed. Returns how many were added.
    @discardableResult
    public mutating func addWords(_ text: String) -> Int {
        var seen = Set(words.map { Self.key($0.word) })
        let added = Self.parts(text)
            .filter { seen.insert(Self.key($0)).inserted }
            .map { DictionaryWord(word: $0) }
        words.insert(contentsOf: added, at: 0)
        return added.count
    }

    /// One word, no comma splitting. Used by migration.
    mutating func insertWord(_ text: String) {
        let word = Self.trimmed(text)
        guard !word.isEmpty, !words.contains(where: { Self.key($0.word) == Self.key(word) }) else { return }
        words.insert(DictionaryWord(word: word), at: 0)
    }

    /// Adds each comma-separated form that is new and not the word itself.
    public mutating func addHeardAs(_ text: String, to id: DictionaryWord.ID) {
        guard let i = words.firstIndex(where: { $0.id == id }) else { return }
        var seen = Set(words[i].heardAs.map(Self.key))
        seen.insert(Self.key(words[i].word))
        for form in Self.parts(text) where seen.insert(Self.key(form)).inserted {
            words[i].heardAs.append(form)
        }
    }

    public mutating func removeHeardAs(_ form: String, from id: DictionaryWord.ID) {
        guard let i = words.firstIndex(where: { $0.id == id }) else { return }
        words[i].heardAs.removeAll { Self.key($0) == Self.key(form) }
    }

    /// False, and nothing changes, when the new name is empty or another
    /// word already has it.
    @discardableResult
    public mutating func renameWord(_ id: DictionaryWord.ID, to text: String) -> Bool {
        let word = Self.trimmed(text)
        guard !word.isEmpty,
              let i = words.firstIndex(where: { $0.id == id }),
              !words.contains(where: { $0.id != id && Self.key($0.word) == Self.key(word) })
        else { return false }
        words[i].word = word
        words[i].heardAs.removeAll { Self.key($0) == Self.key(word) }
        return true
    }

    public mutating func deleteWord(_ id: DictionaryWord.ID) {
        words.removeAll { $0.id == id }
    }

    @discardableResult
    public mutating func addSnippet(trigger: String, text: String) throws -> Snippet {
        let (trigger, text) = try validated(trigger: trigger, text: text, excluding: nil)
        let snippet = Snippet(trigger: trigger, text: text)
        snippets.insert(snippet, at: 0)
        return snippet
    }

    public mutating func updateSnippet(_ id: Snippet.ID, trigger: String, text: String) throws {
        guard let i = snippets.firstIndex(where: { $0.id == id }) else { return }
        let (trigger, text) = try validated(trigger: trigger, text: text, excluding: id)
        snippets[i].trigger = trigger
        snippets[i].text = text
    }

    public mutating func deleteSnippet(_ id: Snippet.ID) {
        snippets.removeAll { $0.id == id }
    }

    private func validated(trigger: String, text: String, excluding id: Snippet.ID?) throws -> (String, String) {
        let trigger = Self.trimmed(trigger)
        let text = Self.trimmed(text)
        guard !trigger.isEmpty else { throw DictionaryError.emptyTrigger }
        guard !text.isEmpty else { throw DictionaryError.emptyText }
        guard !snippets.contains(where: { $0.id != id && Self.key($0.trigger) == Self.key(trigger) }) else {
            throw DictionaryError.duplicateTrigger
        }
        return (trigger, text)
    }
}
```

If `LossyElement` collides with an existing name (`rg -n "LossyElement" Sources`), rename it.

In `Sources/VoiceCore/AppPaths.swift` replace the `vocabulary` line with:

```swift
    /// Dictionary words and snippets.
    public var dictionary: URL { root.appendingPathComponent("dictionary.json") }
    /// The old word list. Read once to migrate into `dictionary.json`.
    public var vocabulary: URL { root.appendingPathComponent("vocabulary.txt") }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DictionaryFileTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
swift test
git commit -m "feat(core): add Dictionary words and snippets with edit rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/VoiceCore/Dictionary.swift Sources/VoiceCore/AppPaths.swift Tests/VoiceCoreTests/DictionaryFileTests.swift
```

---

### Task 4: Dictionary store and migration

**Files:**
- Create: `Sources/VoiceCore/DictionaryStore.swift`
- Test: `Tests/VoiceCoreTests/DictionaryStoreTests.swift`

**Interfaces:**
- Consumes: `DictionaryFile`, `DictionaryFile(migrating:)`, `Vocabulary.parse` (Task 3).
- Produces:
  - `public enum DictionaryLoadIssue: Equatable, Sendable { case none, resetFromCorrupt, newerVersion }`
  - `public enum DictionaryStoreError: Error, Equatable { case newerVersion }`
  - `public actor DictionaryStore { init(url: URL); func load(now: Date = Date()) -> (DictionaryFile, DictionaryLoadIssue) (discardable); func save(_ file: DictionaryFile, revision: Int? = nil) throws; func migrateIfNeeded(vocabularyURL: URL, now: Date = Date()) throws -> Bool (discardable) }`

- [ ] **Step 1: Write the failing tests**

Create `Tests/VoiceCoreTests/DictionaryStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import VoiceCore

struct DictionaryStoreTests {
    func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bv-dict-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func sample() -> DictionaryFile {
        var f = DictionaryFile()
        f.addWords("Kael")
        _ = try? f.addSnippet(trigger: "sign off", text: "Best,\nKael")
        return f
    }

    @Test func missingFileLoadsEmpty() async {
        let (file, issue) = await DictionaryStore(url: tempDir().appendingPathComponent("dictionary.json")).load()
        #expect(file == DictionaryFile())
        #expect(issue == .none)
    }

    @Test func saveRoundTrips() async throws {
        let url = tempDir().appendingPathComponent("dictionary.json")
        let saved = sample()
        try await DictionaryStore(url: url).save(saved)
        let (file, issue) = await DictionaryStore(url: url).load()
        #expect(file == saved)
        #expect(file.snippets.first?.text == "Best,\nKael")
        #expect(issue == .none)
    }

    @Test func damagedFileIsRenamedAndStartsEmpty() async throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("dictionary.json")
        try Data("{nope".utf8).write(to: url)
        let (file, issue) = await DictionaryStore(url: url).load(now: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(file == DictionaryFile())
        #expect(issue == .resetFromCorrupt)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names == ["dictionary.corrupt-1700000000.json"])
    }

    @Test func newerSchemaIsReadOnly() async throws {
        let url = tempDir().appendingPathComponent("dictionary.json")
        let original = Data(#"{"schemaVersion":2,"words":[{"word":"Kael"}]}"#.utf8)
        try original.write(to: url)
        let store = DictionaryStore(url: url)
        let (_, issue) = await store.load()
        #expect(issue == .newerVersion)
        await #expect(throws: DictionaryStoreError.newerVersion) { try await store.save(sample()) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func olderRevisionIsIgnored() async throws {
        let url = tempDir().appendingPathComponent("dictionary.json")
        let store = DictionaryStore(url: url)
        var newer = DictionaryFile()
        newer.addWords("Kael, BugVoice")
        var older = DictionaryFile()
        older.addWords("Kael")
        try await store.save(newer, revision: 2)
        try await store.save(older, revision: 1)
        let (file, _) = await DictionaryStore(url: url).load()
        #expect(file.words.map(\.word) == ["Kael", "BugVoice"])
    }

    @Test func migratesVocabularyTxtAndRenamesIt() async throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("dictionary.json")
        let vocab = dir.appendingPathComponent("vocabulary.txt")
        try "# terms\nBugVoice\nWhisperKit\n\nmy linkedin => linkedin.com/in/kael\nsign off => Best,\\nKael\n"
            .write(to: vocab, atomically: true, encoding: .utf8)
        let store = DictionaryStore(url: url)
        #expect(try await store.migrateIfNeeded(vocabularyURL: vocab))
        let (file, issue) = await store.load()
        #expect(issue == .none)
        #expect(file.words.map(\.word) == ["WhisperKit", "BugVoice"])
        #expect(file.snippets.map(\.trigger) == ["sign off", "my linkedin"])
        #expect(file.snippets[0].text == "Best,\nKael")
        #expect(!FileManager.default.fileExists(atPath: vocab.path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("vocabulary.migrated.txt").path))
    }

    @Test func existingMigratedFileGetsATimestampedName() async throws {
        let dir = tempDir()
        let vocab = dir.appendingPathComponent("vocabulary.txt")
        try "Kael\n".write(to: vocab, atomically: true, encoding: .utf8)
        try "old\n".write(to: dir.appendingPathComponent("vocabulary.migrated.txt"), atomically: true, encoding: .utf8)
        let store = DictionaryStore(url: dir.appendingPathComponent("dictionary.json"))
        #expect(try await store.migrateIfNeeded(vocabularyURL: vocab, now: Date(timeIntervalSince1970: 1_700_000_000)))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("vocabulary.migrated-1700000000.txt").path))
        #expect(try String(contentsOf: dir.appendingPathComponent("vocabulary.migrated.txt"), encoding: .utf8) == "old\n")
    }

    @Test func noMigrationWhenDictionaryExists() async throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("dictionary.json")
        let vocab = dir.appendingPathComponent("vocabulary.txt")
        try await DictionaryStore(url: url).save(sample())
        try "BugVoice\n".write(to: vocab, atomically: true, encoding: .utf8)
        let store = DictionaryStore(url: url)
        let migrated = try await store.migrateIfNeeded(vocabularyURL: vocab)
        #expect(!migrated)
        #expect(FileManager.default.fileExists(atPath: vocab.path))
        #expect(await store.load().0.words.map(\.word) == ["Kael"])
    }

    @Test func noVocabularyMeansNoFile() async throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("dictionary.json")
        let migrated = try await DictionaryStore(url: url).migrateIfNeeded(vocabularyURL: dir.appendingPathComponent("vocabulary.txt"))
        #expect(!migrated)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DictionaryStoreTests`
Expected: build FAILS — `cannot find 'DictionaryStore' in scope`.

- [ ] **Step 3: Implement**

Create `Sources/VoiceCore/DictionaryStore.swift`:

```swift
import Foundation

public enum DictionaryLoadIssue: Equatable, Sendable {
    case none
    /// The file could not be read; it was renamed aside and the Dictionary
    /// starts empty.
    case resetFromCorrupt
    /// Written by a newer BugVoice; shown, never written.
    case newerVersion
}

public enum DictionaryStoreError: Error, Equatable {
    case newerVersion
}

/// Owns `dictionary.json`. Every write replaces the file atomically.
public actor DictionaryStore {
    public let url: URL
    private var loaded = false
    private var readOnly = false
    private var lastRevision = Int.min

    public init(url: URL) {
        self.url = url
    }

    @discardableResult
    public func load(now: Date = Date()) -> (DictionaryFile, DictionaryLoadIssue) {
        loaded = true
        readOnly = false
        guard FileManager.default.fileExists(atPath: url.path) else { return (DictionaryFile(), .none) }
        struct Header: Decodable { var schemaVersion: Int? }
        if let data = try? Data(contentsOf: url) {
            if let version = (try? JSONDecoder().decode(Header.self, from: data))?.schemaVersion,
               version > DictionaryFile.supportedSchemaVersion {
                readOnly = true
                return (DictionaryFile(), .newerVersion)
            }
            if let decoded = try? JSONDecoder().decode(DictionaryFile.self, from: data) {
                return (decoded, .none)
            }
        }
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("dictionary.corrupt-\(Int(now.timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: backup)
        return (DictionaryFile(), .resetFromCorrupt)
    }

    /// `revision` orders saves from quick successive edits: a save older than
    /// the last one written is skipped. Nil always writes.
    public func save(_ file: DictionaryFile, revision: Int? = nil) throws {
        if !loaded { load() }
        if readOnly { throw DictionaryStoreError.newerVersion }
        if let revision {
            guard revision > lastRevision else { return }
            lastRevision = revision
        }
        try write(file)
    }

    /// When `dictionary.json` does not exist and `vocabulary.txt` does: writes
    /// the Dictionary from it, then renames it to `vocabulary.migrated.txt`.
    /// Returns true when it migrated.
    @discardableResult
    public func migrateIfNeeded(vocabularyURL: URL, now: Date = Date()) throws -> Bool {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path), fm.fileExists(atPath: vocabularyURL.path) else { return false }
        let text = try String(contentsOf: vocabularyURL, encoding: .utf8)
        try write(DictionaryFile(migrating: Vocabulary.parse(text)))
        let dir = vocabularyURL.deletingLastPathComponent()
        var target = dir.appendingPathComponent("vocabulary.migrated.txt")
        if fm.fileExists(atPath: target.path) {
            target = dir.appendingPathComponent("vocabulary.migrated-\(Int(now.timeIntervalSince1970)).txt")
        }
        try fm.moveItem(at: vocabularyURL, to: target)
        return true
    }

    private func write(_ file: DictionaryFile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DictionaryStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
swift test
git commit -m "feat(core): store the Dictionary and migrate vocabulary.txt

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/VoiceCore/DictionaryStore.swift Tests/VoiceCoreTests/DictionaryStoreTests.swift
```

---

### Task 5: Vocabulary from the Dictionary, and snippet placeholders

**Files:**
- Modify: `Sources/VoiceCore/Vocabulary.swift`
- Create: `Sources/VoiceCore/SnippetExpander.swift`
- Test: `Tests/VoiceCoreTests/VocabularyTests.swift`, create `Tests/VoiceCoreTests/SnippetExpanderTests.swift`

**Interfaces:**
- Consumes: `DictionaryFile`, `Snippet` (Task 3).
- Produces:
  - `Vocabulary.snippets: [Snippet]`; `Vocabulary.init(terms:replacements:snippets:)` (all defaulted); `Vocabulary.init(dictionary: DictionaryFile)` — `terms` oldest first (so `whisperPrompt()` lists newest first), `replacements` = every heard-as → its word.
  - `public struct ProtectedText: Equatable, Sendable { text: String; fills: [String: String]; init(text:fills:); func isIntact(_ cleaned: String) -> Bool; func fill(_ text: String) -> String }`
  - `public enum SnippetExpander { static func protect(_ text: String, snippets: [Snippet]) -> ProtectedText; static func placeholders(in text: String) -> [String] }`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/VoiceCoreTests/VocabularyTests.swift` (inside the struct):

```swift
    @Test func builtFromDictionary() throws {
        var f = DictionaryFile()
        f.addWords("Kael")
        f.addWords("OpenWhispr")
        f.addHeardAs("open whisper", to: f.words[0].id)
        try f.addSnippet(trigger: "my linkedin", text: "linkedin.com/in/kael")
        let v = Vocabulary(dictionary: f)
        #expect(v.terms == ["Kael", "OpenWhispr"])
        #expect(v.whisperPrompt() == "OpenWhispr, Kael")
        #expect(v.applyReplacements(to: "open whisper rocks") == "OpenWhispr rocks")
        #expect(v.snippets == f.snippets)
    }
```

Create `Tests/VoiceCoreTests/SnippetExpanderTests.swift`:

```swift
import Foundation
import Testing
@testable import VoiceCore

struct SnippetExpanderTests {
    let linkedin = Snippet(trigger: "my linkedin", text: "linkedin.com/in/kael")
    let signOff = Snippet(trigger: "sign off", text: "Best,\nKael")

    @Test func singleTrigger() {
        let p = SnippetExpander.protect("here is my linkedin thanks", snippets: [linkedin])
        #expect(p.text == "here is ⟦S1⟧ thanks")
        #expect(p.fills == ["⟦S1⟧": "linkedin.com/in/kael"])
    }

    @Test func multipleTriggersNumberedInOrderOfAppearance() {
        let p = SnippetExpander.protect("sign off then my linkedin", snippets: [linkedin, signOff])
        #expect(p.text == "⟦S1⟧ then ⟦S2⟧")
        #expect(p.fills == ["⟦S1⟧": "Best,\nKael", "⟦S2⟧": "linkedin.com/in/kael"])
    }

    @Test func sameTriggerTwiceGetsTwoPlaceholders() {
        let p = SnippetExpander.protect("my linkedin and my linkedin", snippets: [linkedin])
        #expect(p.text == "⟦S1⟧ and ⟦S2⟧")
    }

    @Test func caseInsensitive() {
        #expect(SnippetExpander.protect("My LinkedIn", snippets: [linkedin]).text == "⟦S1⟧")
    }

    @Test func vietnameseTriggerMatchesInEitherNormalForm() {
        let s = Snippet(trigger: "chữ ký", text: "Kael")
        let decomposed = "gửi chữ ký".decomposedStringWithCanonicalMapping
        #expect(SnippetExpander.protect(decomposed, snippets: [s]).text == "gửi ⟦S1⟧".precomposedStringWithCanonicalMapping)
    }

    @Test(arguments: ["sign-off", "sign  off", "Sign - off"])
    func spacesOrHyphensBetweenWords(spoken: String) {
        #expect(SnippetExpander.protect("ok \(spoken) now", snippets: [signOff]).text == "ok ⟦S1⟧ now")
    }

    @Test func punctuationAfterTriggerStays() {
        #expect(SnippetExpander.protect("my linkedin.", snippets: [linkedin]).text == "⟦S1⟧.")
    }

    @Test func longestTriggerFirst() {
        let short = Snippet(trigger: "sign", text: "X")
        let p = SnippetExpander.protect("sign off now", snippets: [short, signOff])
        #expect(p.text == "⟦S1⟧ now")
        #expect(p.fills["⟦S1⟧"] == "Best,\nKael")
    }

    @Test(arguments: ["mylinkedin", "my linkedins", "cosign off"])
    func noMatchInsideLongerWords(text: String) {
        let p = SnippetExpander.protect(text, snippets: [linkedin, signOff])
        #expect(p.fills.isEmpty)
        #expect(p.text == text)
    }

    @Test func noSnippetsLeavesTextUnchanged() {
        let p = SnippetExpander.protect("hello", snippets: [])
        #expect(p == ProtectedText(text: "hello", fills: [:]))
    }

    @Test func isIntactNeedsEachPlaceholderExactlyOnceAndNoOthers() {
        let p = SnippetExpander.protect("a my linkedin b sign off", snippets: [linkedin, signOff])
        #expect(p.isIntact("A ⟦S1⟧ b ⟦S2⟧."))
        #expect(p.isIntact("⟦S2⟧ first, then ⟦S1⟧"))
        #expect(!p.isIntact("A b ⟦S2⟧."))
        #expect(!p.isIntact("⟦S1⟧ ⟦S1⟧ ⟦S2⟧"))
        #expect(!p.isIntact("[S1] ⟦S2⟧"))
        #expect(!p.isIntact("⟦S1⟧ ⟦S2⟧ ⟦S3⟧"))
        #expect(ProtectedText(text: "hi", fills: [:]).isIntact("Hi."))
    }

    @Test func fillRestoresMultiLineTextExactlyInOnePass() {
        let p = ProtectedText(text: "", fills: ["⟦S1⟧": "a ⟦S2⟧", "⟦S2⟧": "Best,\nKael"])
        #expect(p.fill("Thanks. ⟦S2⟧") == "Thanks. Best,\nKael")
        #expect(p.fill("⟦S1⟧ ⟦S2⟧") == "a ⟦S2⟧ Best,\nKael")
    }

    @Test func placeholdersInText() {
        #expect(SnippetExpander.placeholders(in: "x ⟦S1⟧ y ⟦S12⟧") == ["⟦S1⟧", "⟦S12⟧"])
        #expect(SnippetExpander.placeholders(in: "nothing").isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'SnippetExpanderTests|VocabularyTests'`
Expected: build FAILS — `cannot find 'SnippetExpander' in scope`.

- [ ] **Step 3: Implement**

In `Sources/VoiceCore/Vocabulary.swift`: change the doc comment to `/// Words, heard-as replacements and snippets used by a dictation. Built from the Dictionary; \`parse\` reads the old \`vocabulary.txt\` format (bench tool, migration).`, and replace the stored properties and `init` with:

```swift
    public var terms: [String]
    public var replacements: [Replacement]
    public var snippets: [Snippet]

    public init(terms: [String] = [], replacements: [Replacement] = [], snippets: [Snippet] = []) {
        self.terms = terms
        self.replacements = replacements
        self.snippets = snippets
    }

    /// Terms oldest first (the Dictionary lists newest first), so
    /// `whisperPrompt` keeps the newest words when it runs out of room.
    public init(dictionary: DictionaryFile) {
        self.init(
            terms: dictionary.words.reversed().map(\.word),
            replacements: dictionary.words.flatMap { word in
                word.heardAs.map { Replacement(spoken: $0, written: word.word) }
            },
            snippets: dictionary.snippets
        )
    }
```

Create `Sources/VoiceCore/SnippetExpander.swift`:

```swift
import Foundation

/// Text whose snippet triggers were replaced by placeholders `⟦S1⟧`, `⟦S2⟧`…
public struct ProtectedText: Equatable, Sendable {
    public var text: String
    /// Placeholder → snippet text.
    public var fills: [String: String]

    public init(text: String, fills: [String: String]) {
        self.text = text
        self.fills = fills
    }

    /// True when `cleaned` holds every placeholder exactly once and no other.
    public func isIntact(_ cleaned: String) -> Bool {
        SnippetExpander.placeholders(in: cleaned).sorted() == fills.keys.sorted()
    }

    /// Each placeholder → its snippet text, in one pass: snippet text is
    /// never scanned again.
    public func fill(_ text: String) -> String {
        guard !fills.isEmpty else { return text }
        var output = ""
        var cursor = text.startIndex
        for match in text.matches(of: /⟦S\d+⟧/) {
            output += text[cursor..<match.range.lowerBound]
            let token = String(text[match.range])
            output += fills[token] ?? token
            cursor = match.range.upperBound
        }
        output += text[cursor...]
        return output
    }
}

public enum SnippetExpander {
    /// Whole words, case-insensitive, NFC on both sides; spaces or hyphens
    /// between trigger words match any run of either. Longest trigger first;
    /// replaced text is not scanned again.
    public static func protect(_ text: String, snippets: [Snippet]) -> ProtectedText {
        let rules = snippets
            .filter { !$0.trigger.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.trigger.count > $1.trigger.count }
        guard !rules.isEmpty else { return ProtectedText(text: text, fills: [:]) }
        let text = text.precomposedStringWithCanonicalMapping
        let alternation = rules.map { "(" + pattern(for: $0.trigger) + ")" }.joined(separator: "|")
        let pattern = "(?<![\\p{L}\\p{N}])(?:" + alternation + ")(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return ProtectedText(text: text, fills: [:])
        }
        let source = text as NSString
        var output = ""
        var cursor = 0
        var fills: [String: String] = [:]
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            guard let rule = rules.indices.first(where: { match.range(at: $0 + 1).location != NSNotFound }) else {
                output += source.substring(with: match.range)
                cursor = match.range.location + match.range.length
                continue
            }
            let token = "⟦S\(fills.count + 1)⟧"
            fills[token] = rules[rule].text
            output += token
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)
        return ProtectedText(text: output, fills: fills)
    }

    /// Every `⟦S<n>⟧` in `text`, in order.
    public static func placeholders(in text: String) -> [String] {
        text.matches(of: /⟦S\d+⟧/).map { String(text[$0.range]) }
    }

    static func pattern(for trigger: String) -> String {
        trigger.precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: "[\\s\\-]+")
    }
}
```

Note: `"Sign - off"` matches because `[\s\-]+` covers the run ` - `.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter 'SnippetExpanderTests|VocabularyTests'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
swift test
git commit -m "feat(core): build vocabulary from the Dictionary and protect snippets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/VoiceCore/Vocabulary.swift Sources/VoiceCore/SnippetExpander.swift Tests/VoiceCoreTests/VocabularyTests.swift Tests/VoiceCoreTests/SnippetExpanderTests.swift
```

---

### Task 6: Pipeline order and placeholder prompt

**Files:**
- Modify: `Sources/VoiceCore/PromptBuilder.swift`, `Sources/VoiceCore/OutputSanitizer.swift:3-5`, `Sources/VoiceCore/DictationPipeline.swift` (the `// Clean` block through `text = vocabulary.applyReplacements(to: text)`)
- Modify (compile): `Sources/BugVoice/HUD/HUDState.swift:42`, `Sources/BugVoice/UI/DictationHistoryView.swift:58`
- Test: `Tests/VoiceCoreTests/PromptTests.swift`, `Tests/VoiceCoreTests/DictationPipelineTests.swift`

**Interfaces:**
- Consumes: `Vocabulary.snippets`, `SnippetExpander`, `ProtectedText` (Task 5).
- Produces: `RawReason.placeholderLost`; `PromptBuilder.systemPrompt(style:vocabulary:focus:hasPlaceholders: Bool = false)`; `PromptBuilder.placeholderRule` (static string); pipeline order of spec §4.

- [ ] **Step 1: Write the failing tests**

Append to `PromptTests`:

```swift
    @Test func placeholderLineOnlyWhenRequestHasPlaceholder() {
        let with = PromptBuilder().request(raw: "here is ⟦S1⟧", style: .work, focus: .unknown, vocabulary: Vocabulary(), modelID: "m", disableThinking: false)
        #expect(with.system.contains("Tokens like ⟦S1⟧ are placeholders. Keep every one exactly once, unchanged, where it belongs."))
        let without = PromptBuilder().request(raw: "here is it", style: .work, focus: .unknown, vocabulary: Vocabulary(), modelID: "m", disableThinking: false)
        #expect(!without.system.contains("placeholders"))
    }
```

Append to `DictationPipelineTests` (inside the struct):

```swift
    static let dictionaryVocab = Vocabulary(
        terms: ["OpenWhispr"],
        replacements: [.init(spoken: "open whisper", written: "OpenWhispr")],
        snippets: [Snippet(trigger: "my linkedin", text: "linkedin.com/in/kael")]
    )

    @Test func heardAsIsFixedBeforeCleanupAndRawStaysOriginal() async {
        let model = RecordingModel()
        let r = await pipeline(transcriber: FakeTranscriber(text: "open whisper is great"), model: model, vocabulary: Self.dictionaryVocab)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(await model.requests.first?.user.contains("OpenWhispr is great") == true)
        #expect(r.raw == "open whisper is great")
        #expect(r.finalText == "OpenWhispr is great")
    }

    @Test func snippetSurvivesCleanupAndNeverReachesModel() async {
        let model = RecordingModel(output: "Here is ⟦S1⟧.")
        let r = await pipeline(transcriber: FakeTranscriber(text: "here is my linkedin"), model: model, vocabulary: Self.dictionaryVocab)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        let request = await model.requests.first
        #expect(request?.user.contains("⟦S1⟧") == true)
        #expect(request?.user.contains("linkedin.com") == false)
        #expect(request?.system.contains("linkedin.com") == false)
        #expect(request?.system.contains("Tokens like ⟦S1⟧ are placeholders") == true)
        #expect(r.rawReason == nil)
        #expect(r.cleaned == "Here is linkedin.com/in/kael.")
        #expect(r.finalText == "Here is linkedin.com/in/kael.")
        #expect(r.raw == "here is my linkedin")
    }

    @Test(arguments: ["Here is my profile.", "Here is ⟦S1⟧ ⟦S1⟧.", "Here is [S1].", "Here is ⟦S1⟧ and ⟦S2⟧."])
    func mangledPlaceholderDiscardsCleanedText(output: String) async {
        let insertion = RecordingInsertion()
        let r = await pipeline(transcriber: FakeTranscriber(text: "here is my linkedin"), model: FakeModel(output: output), insertion: insertion, vocabulary: Self.dictionaryVocab)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .inserted)
        #expect(r.rawReason == .placeholderLost)
        #expect(r.cleaned == nil)
        #expect(r.finalText == "here is linkedin.com/in/kael")
        #expect(await insertion.inserted == ["here is linkedin.com/in/kael"])
    }

    @Test func cleanupOffStillFillsSnippet() async {
        var s = AppSettings()
        s.cleanupEnabled = false
        let r = await pipeline(transcriber: FakeTranscriber(text: "here is my linkedin"), settings: s, vocabulary: Self.dictionaryVocab)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.rawReason == .cleanupOff)
        #expect(r.finalText == "here is linkedin.com/in/kael")
    }

    @Test func terminalFillsSnippetWithoutModelCall() async {
        let model = RecordingModel()
        let r = await pipeline(transcriber: FakeTranscriber(text: "open my linkedin"), model: model, focusAtInsert: terminalFocus, vocabulary: Self.dictionaryVocab)
            .run(clip: speechClip, startFocus: terminalFocus, startedAt: Date(), onStage: { _ in })
        #expect(await model.requests.isEmpty)
        #expect(r.finalText == "open linkedin.com/in/kael")
    }

    @Test func secureFieldCopiesFilledTextOnly() async {
        let insertion = RecordingInsertion()
        let r = await pipeline(transcriber: FakeTranscriber(text: "here is my linkedin"), model: nil, insertion: insertion,
                               focusAtInsert: FocusSnapshot(bundleID: "com.apple.Safari", isSecure: true), vocabulary: Self.dictionaryVocab)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .copiedSecureField)
        #expect(r.historyEntry == nil)
        #expect(await insertion.inserted.isEmpty)
        #expect(await insertion.copied == ["here is linkedin.com/in/kael"])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'PromptTests|DictationPipelineTests'`
Expected: build FAILS — `type 'RawReason' has no member 'placeholderLost'`.

- [ ] **Step 3: Implement**

`Sources/VoiceCore/OutputSanitizer.swift`:

```swift
public enum RawReason: String, Codable, Sendable {
    case cleanupOff, modelError, modelTimeout, emptyOutput, tooLong
    /// The model lost, repeated or changed a snippet placeholder.
    case placeholderLost
}
```

`Sources/VoiceCore/PromptBuilder.swift`: add after `sharedRules`:

```swift
    static let placeholderRule = "Tokens like ⟦S1⟧ are placeholders. Keep every one exactly once, unchanged, where it belongs."
```

Change `systemPrompt` to take the flag and add the line after the `Style:` part:

```swift
    public func systemPrompt(style: Style, vocabulary: Vocabulary, focus: FocusSnapshot, hasPlaceholders: Bool = false) -> String {
        var parts = [Self.sharedRules]
        let rules = customRules[style.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultRules(for: style)
        parts.append("Style: \(rules)")
        if hasPlaceholders {
            parts.append(Self.placeholderRule)
        }
        // … the rest unchanged (terms, before, after)
```

and in `request(...)` pass it:

```swift
            system: systemPrompt(
                style: style, vocabulary: vocabulary, focus: focus,
                hasPlaceholders: !SnippetExpander.placeholders(in: raw).isEmpty
            ),
```

`Sources/VoiceCore/DictationPipeline.swift`: replace from `// Clean` through `text = vocabulary.applyReplacements(to: text)` with:

```swift
        // Dictionary: heard-as forms become their words, then each snippet
        // trigger becomes a placeholder, so the text model never sees or
        // rewords the saved text.
        let protected = SnippetExpander.protect(vocabulary.applyReplacements(to: raw), snippets: vocabulary.snippets)
        var text = protected.text
        var cleanedAccepted = false

        // Clean
        if let model = textModel, settings.cleanupEnabled, settings.styles.isCleanupEnabled(for: style) {
            onStage(.cleaning(model: settings.textModel.model))
            mark = Date()
            var built = PromptBuilder(customRules: settings.styles.customRules).request(
                raw: protected.text, style: style, focus: startFocus, vocabulary: vocabulary,
                modelID: settings.textModel.model, disableThinking: settings.textModel.disableThinking
            )
            built.maxTokens = min(1024, 2 * protected.text.count + 50)
            let request = built
            do {
                let output = try await withTimeout(seconds: settings.textModel.timeoutSeconds) {
                    try await model.clean(request)
                }
                switch OutputSanitizer.sanitize(output, raw: protected.text) {
                case .accepted(let cleaned) where protected.isIntact(cleaned):
                    text = cleaned
                    cleanedAccepted = true
                case .accepted:
                    result.rawReason = .placeholderLost
                case .rejected(let reason):
                    result.rawReason = reason
                }
            } catch is TimeoutError {
                result.rawReason = .modelTimeout
            } catch {
                result.rawReason = .modelError
                result.errorMessage = String(describing: error)
            }
            result.timings.clean = Date().timeIntervalSince(mark)
        } else {
            result.rawReason = .cleanupOff
        }

        // Corrections again (the model may re-split a word), then the saved
        // snippet text, exactly.
        text = protected.fill(vocabulary.applyReplacements(to: text))
        if cleanedAccepted { result.cleaned = text }
```

The terminal trailing-period step and everything after stay as they are.

`Sources/BugVoice/HUD/HUDState.swift:42`: `case .emptyOutput, .tooLong, .placeholderLost:`.

`Sources/BugVoice/UI/DictationHistoryView.swift:58`:

```swift
                    if let reason = e.rawReason, [.modelError, .modelTimeout, .placeholderLost].contains(reason) {
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS (all suites, including the existing `replacementsApplyAfterCleanup` and `maxTokensScalesWithRawLength`). Then `swift build` to confirm the app target compiles.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(core): protect snippets through cleanup and fill them after

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/VoiceCore/PromptBuilder.swift Sources/VoiceCore/OutputSanitizer.swift Sources/VoiceCore/DictationPipeline.swift Sources/BugVoice/HUD/HUDState.swift Sources/BugVoice/UI/DictationHistoryView.swift Tests/VoiceCoreTests/PromptTests.swift Tests/VoiceCoreTests/DictationPipelineTests.swift
```

---

### Task 7: Dictionary in the app, and the Dictionary page

App code; no unit-test target. Verify with `swift build`, `swift test`, `Scripts/build-app.sh`, and by looking at the page.

**Files:**
- Modify: `Sources/BugVoice/AppModel.swift` (Page enum; properties at 62–63; bootstrap 132–143; `// MARK: Vocabulary` at ~520)
- Modify: `Sources/BugVoice/UI/MainWindow.swift`
- Modify: `Sources/BugVoice/UI/Settings/SettingsView.swift`; delete `Sources/BugVoice/UI/Settings/VocabularyTab.swift`
- Create: `Sources/BugVoice/UI/Components/FlowLayout.swift`, `Sources/BugVoice/UI/Dictionary/HeroCard.swift`, `DictionaryPage.swift`, `DictionaryWordsView.swift`, `SnippetsView.swift`, `SnippetEditorSheet.swift`

**Interfaces:**
- Consumes: `DictionaryStore`, `DictionaryFile` edits, `Vocabulary(dictionary:)`, `AppPaths.dictionary`.
- Produces: `AppModel.dictionary: DictionaryFile`, `AppModel.dictionaryReadOnly: Bool`, `AppModel.loadDictionary() async`, `AppModel.editDictionary(_ change: (inout DictionaryFile) throws -> Void) async rethrows`; `Page.dictionary`; `FlowLayout(spacing:)`; `View.insightsCard()` (existing, reused).

- [ ] **Step 1: AppModel state and loading**

In `Page`: add `dictionary` after `insights` (`case dictation, insights, dictionary, meetings, notes, settings`), title `"Dictionary"`, symbol `"character.book.closed"`. Update the doc comment to `/// Main-window pages, in sidebar order.`

Replace `var vocabularyText = ""` / `var vocabulary = Vocabulary()` with:

```swift
    /// Dictionary words and snippets, newest first.
    var dictionary = DictionaryFile()
    /// True when `dictionary.json` was written by a newer BugVoice: shown, never written.
    var dictionaryReadOnly = false
    /// Built from `dictionary`; what the next dictation uses.
    var vocabulary = Vocabulary()
```

Add next to `insightsStore`:

```swift
    @ObservationIgnored let dictionaryStore = DictionaryStore(url: AppPaths.standard().dictionary)
    @ObservationIgnored private var dictionaryRevision = 0
```

Update the `saveError` doc comment: `(settings, Dictionary, history, …)`.

- [ ] **Step 2: Load, migrate and edit**

Replace the whole `// MARK: Vocabulary` section (`saveVocabulary`) with:

```swift
    // MARK: Dictionary

    /// Moves `vocabulary.txt` into the Dictionary once, then loads it.
    /// Must finish before dictation starts.
    func loadDictionary() async {
        do {
            try await dictionaryStore.migrateIfNeeded(vocabularyURL: paths.vocabulary)
        } catch {
            saveError = "Could not move vocabulary.txt into the Dictionary: \(error.localizedDescription)"
        }
        let (file, issue) = await dictionaryStore.load()
        dictionary = file
        vocabulary = Vocabulary(dictionary: file)
        switch issue {
        case .none: break
        case .resetFromCorrupt:
            saveError = "Dictionary file was damaged and has been reset. The old file is kept next to it."
        case .newerVersion:
            dictionaryReadOnly = true
        }
    }

    /// Applies `change` in memory first, so a second quick edit builds on
    /// this one, then saves. Throws only what `change` throws; a failed save
    /// goes to `saveError`.
    func editDictionary(_ change: (inout DictionaryFile) throws -> Void) async rethrows {
        guard !dictionaryReadOnly else { return }
        var next = dictionary
        try change(&next)
        guard next != dictionary else { return }
        dictionary = next
        vocabulary = Vocabulary(dictionary: next)
        dictionaryRevision += 1
        do {
            try await dictionaryStore.save(next, revision: dictionaryRevision)
        } catch {
            saveError = "Could not save the Dictionary: \(error.localizedDescription)"
        }
    }
```

- [ ] **Step 3: Bootstrap order**

In `bootstrap()`, delete the `vocabulary.txt` creation block and the two lines that read and parse it, and put `await loadDictionary()` directly before `await loadInsights()`:

```swift
        isLoadingSettings = false

        await loadDictionary()
        await loadInsights()
        startDictation()
```

Then run `rg -n "vocabularyText|saveVocabulary|paths\.vocabulary" Sources/BugVoice` — the only hit must be inside `loadDictionary()`.

- [ ] **Step 4: Remove the Vocabulary settings tab**

```bash
git rm Sources/BugVoice/UI/Settings/VocabularyTab.swift
```

Delete the `VocabularyTab(...)` line from `SettingsView`.

- [ ] **Step 5: FlowLayout**

Create `Sources/BugVoice/UI/Components/FlowLayout.swift`:

```swift
import SwiftUI

/// Lays children left to right and wraps to a new row when one does not fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            width = max(width, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
```

- [ ] **Step 6: HeroCard**

Create `Sources/BugVoice/UI/Dictionary/HeroCard.swift`:

```swift
import AppKit
import SwiftUI

/// Title, text, an add field and a decorative illustration. The
/// illustration hides when the card is narrower than 700 pt (a window
/// narrower than about 900 pt).
struct HeroCard<Illustration: View>: View {
    let title: String
    let text: String
    let placeholder: String
    var hint: String?
    var isDisabled = false
    let onAdd: (String) -> Void
    @ViewBuilder var illustration: Illustration

    @State private var input = ""
    @State private var cardWidth: CGFloat = 0

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.weight(.semibold))
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField(placeholder, text: $input)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmed.isEmpty || isDisabled)
                }
                .disabled(isDisabled)
                if let hint {
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            if cardWidth >= 700 {
                Spacer(minLength: 0)
                illustration.frame(width: 260, height: 150)
            }
        }
        .insightsCard()
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { cardWidth = $0 }
    }

    private var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func add() {
        guard !trimmed.isEmpty, !isDisabled else { return }
        onAdd(trimmed)
        input = ""
    }
}

/// Dashed rings behind a stack of chips with an icon badge, as in the mockup.
struct HeroIllustration<Chips: View>: View {
    let symbol: String
    @ViewBuilder var chips: Chips

    var body: some View {
        ZStack {
            ForEach([150.0, 110.0], id: \.self) { size in
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: size, height: size)
            }
            VStack(alignment: .leading, spacing: 8) { chips }
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                .offset(x: 105, y: -55)
        }
    }
}

/// One rounded chip on a hero illustration.
struct HeroChip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) { content }
            .font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}
```

- [ ] **Step 7: DictionaryPage**

Create `Sources/BugVoice/UI/Dictionary/DictionaryPage.swift`:

```swift
import SwiftUI
import VoiceCore

enum DictionaryTab: Hashable { case words, snippets }

struct DictionaryPage: View {
    @Bindable var model: AppModel
    @State private var tab: DictionaryTab = .words

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Dictionary").font(.title2.weight(.semibold))
                PillTabs(
                    items: [
                        .init(value: DictionaryTab.words, title: "Dictionary"),
                        .init(value: DictionaryTab.snippets, title: "Snippets"),
                    ],
                    selection: $tab
                )
                if model.dictionaryReadOnly {
                    Text("Dictionary was saved by a newer BugVoice.").foregroundStyle(.secondary)
                }
                switch tab {
                case .words: DictionaryWordsView(model: model)
                case .snippets: SnippetsView(model: model)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [ ] **Step 8: Words tab**

Create `Sources/BugVoice/UI/Dictionary/DictionaryWordsView.swift`:

```swift
import SwiftUI
import VoiceCore

struct DictionaryWordsView: View {
    @Bindable var model: AppModel
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(
                title: "Add words to your dictionary",
                text: "Names, tools and acronyms BugVoice should always get right. Add what it mishears them as, and those are fixed too.",
                placeholder: "Add words separated by commas — OpenWhispr, Supabase, Kael",
                hint: "Words also guide speech recognition and the text model.",
                isDisabled: model.dictionaryReadOnly,
                onAdd: { text in Task { await model.editDictionary { _ = $0.addWords(text) } } }
            ) {
                HeroIllustration(symbol: "character.book.closed") {
                    HeroChip { Text("open whisper").strikethrough().foregroundStyle(.secondary); Text("OpenWhispr").bold() }
                    HeroChip { Text("bug voice").strikethrough().foregroundStyle(.secondary); Text("BugVoice").bold() }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(model.dictionary.words.count == 1 ? "1 word" : "\(model.dictionary.words.count) words")
                        .font(.headline)
                    Spacer()
                    TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 220)
                }
                .padding(.bottom, 8)
                if model.dictionary.words.isEmpty {
                    Text("No words yet.").foregroundStyle(.secondary).padding(.vertical, 8)
                } else if filtered.isEmpty {
                    Text("No words match.").foregroundStyle(.secondary).padding(.vertical, 8)
                }
                ForEach(filtered) { word in
                    Divider()
                    WordRow(model: model, word: word).padding(.vertical, 8)
                }
            }
            .insightsCard()
        }
    }

    private var filtered: [DictionaryWord] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.dictionary.words }
        return model.dictionary.words.filter { word in
            word.word.localizedCaseInsensitiveContains(query)
                || word.heardAs.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}

private struct WordRow: View {
    let model: AppModel
    let word: DictionaryWord
    @State private var newName: String?
    @State private var newHeardAs: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if newName != nil {
                TextField("Word", text: Binding(get: { newName ?? "" }, set: { newName = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit(rename)
                    .onExitCommand { newName = nil }
            } else {
                Text(word.word).bold().frame(minWidth: 140, alignment: .leading)
            }
            FlowLayout(spacing: 6) {
                if !word.heardAs.isEmpty {
                    Text("Heard as").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(word.heardAs, id: \.self) { form in
                    HStack(spacing: 4) {
                        Text(form)
                        Button { edit { $0.removeHeardAs(form, from: word.id) } } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                        .disabled(model.dictionaryReadOnly)
                    }
                    .font(.callout)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                if newHeardAs != nil {
                    TextField("open whisper, open whispers", text: Binding(get: { newHeardAs ?? "" }, set: { newHeardAs = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onSubmit(addHeardAs)
                        .onExitCommand { newHeardAs = nil }
                } else {
                    Button("+ heard as") { newHeardAs = "" }
                        .buttonStyle(.borderless)
                        .disabled(model.dictionaryReadOnly)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button("Edit") { newName = word.word }
                Button("Delete") { edit { $0.deleteWord(word.id) } }
            }
            .buttonStyle(.borderless)
            .disabled(model.dictionaryReadOnly)
        }
    }

    private func edit(_ change: @escaping @MainActor (inout DictionaryFile) -> Void) {
        Task { await model.editDictionary { change(&$0) } }
    }

    private func rename() {
        guard let name = newName else { return }
        edit { _ = $0.renameWord(word.id, to: name) }
        newName = nil
    }

    private func addHeardAs() {
        guard let text = newHeardAs else { return }
        edit { $0.addHeardAs(text, to: word.id) }
        newHeardAs = nil
    }
}
```

If the compiler rejects `@escaping @MainActor` closures passed into `editDictionary`, drop `@MainActor`; `WordRow` is a `View` and already main-actor isolated.

- [ ] **Step 9: Snippets tab and sheet**

Create `Sources/BugVoice/UI/Dictionary/SnippetEditorSheet.swift`:

```swift
import SwiftUI
import VoiceCore

/// What the sheet edits: a new snippet (id nil) or an existing one.
struct SnippetDraft: Identifiable {
    let id = UUID()
    var snippetID: Snippet.ID?
    var trigger: String
    var text: String
}

struct SnippetEditorSheet: View {
    let model: AppModel
    let draft: SnippetDraft
    @State private var trigger: String
    @State private var text: String
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, draft: SnippetDraft) {
        self.model = model
        self.draft = draft
        _trigger = State(initialValue: draft.trigger)
        _text = State(initialValue: draft.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.snippetID == nil ? "New snippet" : "Edit snippet").font(.headline)
            TextField("Trigger", text: $trigger).textFieldStyle(.roundedBorder)
            Text("Text").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBlank(text) || isBlank(trigger))
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let snippetID = draft.snippetID
        let trigger = trigger
        let text = text
        Task {
            do {
                try await model.editDictionary { file in
                    if let snippetID {
                        try file.updateSnippet(snippetID, trigger: trigger, text: text)
                    } else {
                        try file.addSnippet(trigger: trigger, text: text)
                    }
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
```

Create `Sources/BugVoice/UI/Dictionary/SnippetsView.swift`:

```swift
import SwiftUI
import VoiceCore

struct SnippetsView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var draft: SnippetDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(
                title: "Stuff you shouldn't have to say twice",
                text: "Say a trigger phrase and BugVoice puts in what you saved: links, intros, sign-offs, prompts. The saved text is pasted exactly, never reworded.",
                placeholder: "Add a trigger phrase — \"my linkedin\", \"cal link\"",
                isDisabled: model.dictionaryReadOnly,
                onAdd: { trigger in draft = SnippetDraft(snippetID: nil, trigger: trigger, text: "") }
            ) {
                HeroIllustration(symbol: "text.badge.plus") {
                    HeroChip { Text("\"Sign off\"").bold(); Text("↳ Best, Kael · kael@example.com").foregroundStyle(.secondary) }
                    HeroChip { Text("\"My LinkedIn\"").bold(); Text("↳ linkedin.com/in/kael").foregroundStyle(.secondary) }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(model.dictionary.snippets.count == 1 ? "1 snippet" : "\(model.dictionary.snippets.count) snippets")
                        .font(.headline)
                    Spacer()
                    TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 220)
                }
                .padding(.bottom, 8)
                if model.dictionary.snippets.isEmpty {
                    Text("No snippets yet.").foregroundStyle(.secondary).padding(.vertical, 8)
                } else if filtered.isEmpty {
                    Text("No snippets match.").foregroundStyle(.secondary).padding(.vertical, 8)
                }
                ForEach(filtered) { snippet in
                    Divider()
                    row(snippet).padding(.vertical, 8)
                }
            }
            .insightsCard()
        }
        .sheet(item: $draft) { SnippetEditorSheet(model: model, draft: $0) }
    }

    private func row(_ snippet: Snippet) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("“\(snippet.trigger)”").bold().frame(minWidth: 140, alignment: .leading)
            Text("↳ " + snippet.text.replacingOccurrences(of: "\n", with: " ⏎ "))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button("Edit") { draft = SnippetDraft(snippetID: snippet.id, trigger: snippet.trigger, text: snippet.text) }
                Button("Delete") { Task { await model.editDictionary { $0.deleteSnippet(snippet.id) } } }
            }
            .buttonStyle(.borderless)
            .disabled(model.dictionaryReadOnly)
        }
    }

    private var filtered: [Snippet] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.dictionary.snippets }
        return model.dictionary.snippets.filter {
            $0.trigger.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query)
        }
    }
}
```

- [ ] **Step 10: Route the page**

In `MainWindow`'s `switch model.page` add `case .dictionary: DictionaryPage(model: model)` after `.insights`.

- [ ] **Step 11: Build and look**

Run: `swift build && swift test && Scripts/build-app.sh`
Expected: all pass; app builds and signs.

Open `build/BugVoice.app`, go to Dictionary:
- Add "OpenWhispr, Supabase": both rows at the top in that order; count reads "2 words" (plus existing).
- "+ heard as" → "open whisper" → tag appears; × removes it.
- Edit renames inline; Delete removes the row.
- Snippets: type `my linkedin`, Add → sheet with trigger filled; Save is disabled until text is entered; save; adding the same trigger again shows "A snippet with this trigger already exists." in the sheet.
- Narrow the window: the illustration hides; widen: it returns.
- `~/Library/Application Support/BugVoice/dictionary.json` holds the entries; `vocabulary.txt` is now `vocabulary.migrated.txt` if it existed.
- Settings has no Vocabulary tab.

If you cannot see the screen, say so in your report.

- [ ] **Step 12: Commit**

```bash
git commit -m "feat(app): add the Dictionary page with words and snippets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/BugVoice/AppModel.swift Sources/BugVoice/UI/MainWindow.swift Sources/BugVoice/UI/Settings/SettingsView.swift Sources/BugVoice/UI/Settings/VocabularyTab.swift Sources/BugVoice/UI/Components/FlowLayout.swift Sources/BugVoice/UI/Dictionary
```

---

### Task 8: Style page, and style names everywhere

**Files:**
- Modify: `Sources/BugVoice/AppModel.swift` (Page enum), `Sources/BugVoice/UI/MainWindow.swift`
- Create: `Sources/BugVoice/UI/Style/StylePage.swift`, `StyleDetailView.swift`, `StyleExamples.swift`
- Modify: `Sources/BugVoice/UI/Settings/SettingsView.swift`, `SpeechTab.swift:46`; delete `StylesTab.swift`
- Modify: `Sources/BugVoice/UI/Insights/InsightsUsageView.swift:38`, `Sources/BugVoice/HUD/HUDState.swift:34,47`

**Interfaces:**
- Consumes: `Style.title`, `StyleRouter.defaultApps`, `builtInApps(for:)`, `websites(for:)`, `PromptBuilder.defaultRules(for:)`, `FlowLayout`, `insightsCard()`.
- Produces: `Page.style`.

- [ ] **Step 1: Page and settings**

In `Page`: add `style` after `dictionary` (`case dictation, insights, dictionary, style, meetings, notes, settings`), title `"Style"`, symbol `"paintbrush.pointed"`. In `MainWindow` add `case .style: StylePage(model: model)`.

```bash
git rm Sources/BugVoice/UI/Settings/StylesTab.swift
```

Delete the `StylesTab(...)` line from `SettingsView`. In `SpeechTab.swift` change `Toggle("Use vocabulary as hints", …)` to `Toggle("Use Dictionary words as hints", …)`.

- [ ] **Step 2: Style names in HUD and Insights**

`HUDState.swift`: `style: Style.document.rawValue.capitalized` → `style: Style.document.title`; `style: r.style.rawValue.capitalized` → `style: r.style.title`.

`InsightsUsageView.swift` By style rows:

```swift
                              rows: summary.styles.map {
                                  BreakdownRow(name: Style(rawValue: $0.name)?.title ?? "Chat (old)", words: $0.words, share: $0.share)
                              }) {
```

- [ ] **Step 3: Examples**

Create `Sources/BugVoice/UI/Style/StyleExamples.swift`:

```swift
import VoiceCore

/// Static "You say" / "BugVoice writes" pairs from the mockup.
enum StyleExamples {
    static func example(for style: Style) -> (said: String, written: String) {
        switch style {
        case .personal:
            ("um hey are you free tonight like around 7 for dinner", "Hey, are you free tonight around 7 for dinner?")
        case .work:
            ("so the deploy is friday no I mean thursday and uh can you check the API", "The deploy is Thursday. Can you check the API?")
        case .email:
            ("hi anna thanks for the update um I'll review it tomorrow best kael", "Hi Anna,\n\nThanks for the update. I'll review it tomorrow.\n\nBest,\nKael")
        case .document:
            ("first install the app second grant the mic third hold right option", "1. Install the app.\n2. Grant the microphone.\n3. Hold Right Option.")
        case .terminal:
            ("um git status", "git status")
        case .other:
            ("so I think we should uh ship it", "I think we should ship it.")
        }
    }
}
```

- [ ] **Step 4: Style page**

Create `Sources/BugVoice/UI/Style/StylePage.swift`:

```swift
import AppKit
import SwiftUI
import VoiceCore

/// An app or website shown under a style.
struct StyleAppEntry: Identifiable, Hashable {
    var id: String
    var name: String
    /// Nil for a website; websites follow their built-in rule and cannot move.
    var bundleID: String?
    /// True when the user moved this app here.
    var isOverride: Bool
}

@MainActor
enum StyleApps {
    static func entries(for style: Style, overrides: [String: Style]) -> [StyleAppEntry] {
        let builtIn = StyleRouter.builtInApps(for: style)
            .filter { overrides[$0] == nil || overrides[$0] == style }
            .map { StyleAppEntry(id: $0, name: appName($0), bundleID: $0, isOverride: false) }
        let moved = overrides
            .filter { $0.value == style && StyleRouter.defaultApps[$0.key] != style }
            .keys
            .map { StyleAppEntry(id: $0, name: appName($0), bundleID: $0, isOverride: true) }
        let apps = (builtIn + moved).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let sites = StyleRouter.websites(for: style).map { StyleAppEntry(id: $0, name: $0, bundleID: nil, isOverride: false) }
        return apps + sites
    }

    static func summary(for style: Style, overrides: [String: Style]) -> String {
        if style == .other { return "Every app not listed" }
        let names = entries(for: style, overrides: overrides).filter { $0.bundleID != nil }.prefix(4).map(\.name)
        return names.isEmpty ? "No apps" : names.joined(separator: ", ")
    }

    /// The installed app's name, or the bundle ID when it is not installed.
    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

struct StylePage: View {
    @Bindable var model: AppModel
    @State private var selected: Style = .personal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style").font(.title2.weight(.semibold))
            Text("Each app is matched to a style when you start dictating. The style sets how the text model cleans your words.")
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 4) {
                    ForEach(Style.allCases, id: \.self) { style in
                        Button { selected = style } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.title).fontWeight(.semibold)
                                Text(StyleApps.summary(for: style, overrides: model.settings.styles.appOverrides))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(selected == style ? Color.primary.opacity(0.08) : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 230)
                ScrollView {
                    StyleDetailView(model: model, style: selected)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

- [ ] **Step 5: Style detail**

Create `Sources/BugVoice/UI/Style/StyleDetailView.swift`:

```swift
import AppKit
import SwiftUI
import VoiceCore

struct StyleDetailView: View {
    @Bindable var model: AppModel
    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(style.title).font(.title3.weight(.semibold))

            section("Apps and websites") {
                if style == .other {
                    Text("Every app without a style uses Other.").foregroundStyle(.secondary)
                }
                let entries = StyleApps.entries(for: style, overrides: model.settings.styles.appOverrides)
                if !entries.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(entries) { chip($0) }
                    }
                }
                if style == .terminal {
                    Text("Also the terminal panel in VS Code and Cursor.").font(.caption).foregroundStyle(.secondary)
                }
                if style != .other {
                    Button { addApp() } label: { Label("Add app", systemImage: "plus") }
                }
            }

            Toggle("Clean up with the text model", isOn: Binding(
                get: { model.settings.styles.isCleanupEnabled(for: style) },
                set: { model.settings.styles.cleanupEnabled[style.rawValue] = $0 }
            ))

            section("Tone") {
                TextEditor(text: Binding(
                    get: { model.settings.styles.customRules[style.rawValue] ?? PromptBuilder.defaultRules(for: style) },
                    set: { model.settings.styles.customRules[style.rawValue] = $0 == PromptBuilder.defaultRules(for: style) ? nil : $0 }
                ))
                .font(.callout)
                .frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                Button("Reset to default") { model.settings.styles.customRules[style.rawValue] = nil }
                    .disabled(model.settings.styles.customRules[style.rawValue] == nil)
            }

            section("Example") {
                let example = StyleExamples.example(for: style)
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("You say").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(example.said).foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("BugVoice writes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(example.written)
                    }
                }
            }
        }
        .insightsCard()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    @ViewBuilder
    private func chip(_ entry: StyleAppEntry) -> some View {
        if let bundleID = entry.bundleID {
            Menu {
                Menu("Move to…") {
                    ForEach(Style.allCases.filter { $0 != style }, id: \.self) { target in
                        Button(target.title) { move(bundleID, to: target) }
                    }
                }
                if entry.isOverride {
                    Button("Reset") { model.settings.styles.appOverrides[bundleID] = nil }
                }
            } label: {
                Text(entry.name)
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .fixedSize()
        } else {
            Text(entry.name)
                .font(.callout)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
    }

    /// An override equal to the built-in style is removed rather than stored.
    private func move(_ bundleID: String, to target: Style) {
        model.settings.styles.appOverrides[bundleID] = StyleRouter.defaultApps[bundleID] == target ? nil : target
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        move(id, to: style)
    }
}
```

- [ ] **Step 6: Leftovers**

Run: `rg -n 'rawValue\.capitalized|StylesTab|VocabularyTab|vocabulary as hints' Sources`
Expected: no hits.

- [ ] **Step 7: Build and look**

Run: `swift build && swift test && Scripts/build-app.sh`
Expected: all pass.

Open the app, go to Style:
- Sidebar order: Dictation, Insights, Dictionary, Style, Meetings, Notes, Settings.
- Work lists Slack (and Teams if installed) plus `app.slack.com`, `teams.microsoft.com`, `teams.live.com`, `chat.google.com`; Personal lists Messages, Zalo, Telegram…
- Telegram → Move to… → Work Messages: it moves to Work with a Reset item; Reset returns it to Personal.
- Edit the Work tone, then Reset to default restores it.
- Other shows "Every app without a style uses Other." and no Add app button.
- Insights By style shows "Personal messages", "Work messages"…; an old `chat` key shows "Chat (old)".
- Settings has no Styles tab; Speech reads "Use Dictionary words as hints".

- [ ] **Step 8: Commit**

```bash
git commit -m "feat(app): add the Style page and use style names everywhere

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- Sources/BugVoice/AppModel.swift Sources/BugVoice/UI/MainWindow.swift Sources/BugVoice/UI/Style Sources/BugVoice/UI/Settings/SettingsView.swift Sources/BugVoice/UI/Settings/SpeechTab.swift Sources/BugVoice/UI/Settings/StylesTab.swift Sources/BugVoice/UI/Insights/InsightsUsageView.swift Sources/BugVoice/HUD/HUDState.swift
```

---

### Task 9: Checklist and roadmap

**Files:**
- Modify: `docs/testing/manual-checklist.md`, `docs/ROADMAP.md:34-35`

- [ ] **Step 1: Append checks 81–90**

Append to `docs/testing/manual-checklist.md`:

```markdown


## Dictionary and Style

Run these after building with `Scripts/build-app.sh`. Keep the Result column
blank until the maintainer runs each check.

| # | Where | Do | Expect | Result |
|---|---|---|---|---|
| 81 | Dictionary page | Add "OpenWhispr, Supabase" in one go | Both rows appear at the top, newest first | |
| 82 | Heard as | Add heard-as "open whisper" to OpenWhispr; dictate "open whisper is great" in TextEdit | "OpenWhispr is great" | |
| 83 | Snippet in Slack | Add snippet "my linkedin" → URL; dictate "here is my linkedin" in Slack | Cleaned Work sentence with the exact URL | |
| 84 | Multi-line snippet | Add "sign off" with two lines; dictate it in Mail | Line breaks kept | |
| 85 | Model off | Quit LM Studio; dictate "here is my linkedin" | Snippet still expanded | |
| 86 | Style page | Open Style; dictate in Slack and in Zalo | Slack under Work, Zalo under Personal; each dictation shows that tone | |
| 87 | Move app | Move Telegram to Work; dictate in Telegram; then Reset | Work tone; after Reset it is under Personal again | |
| 88 | Tone | Edit the Work tone, then Reset to default | Default text restored | |
| 89 | Migration | Quit; put a term and a `=>` line in `vocabulary.txt`; delete `dictionary.json`; launch | Word and snippet appear; file renamed `vocabulary.migrated.txt` | |
| 90 | Settings | Open Settings | No Vocabulary or Styles tab; Speech reads "Use Dictionary words as hints" | |
| 91 | Bundle IDs | For WhatsApp, Messenger, Teams, Lark, run `osascript -e 'id of app "Name"'` | IDs match `StyleRouter.defaultApps`; fix any that differ | |
```

- [ ] **Step 2: Roadmap note**

In `docs/ROADMAP.md` replace the bullet

```markdown
- Item 2 extends `vocabulary.txt` (WhisperKit spelling hints) rather than
  replacing it.
```

with

```markdown
- Item 2 replaced `vocabulary.txt` with `dictionary.json` (words, heard-as
  forms, snippets); an existing `vocabulary.txt` is migrated once and renamed
  `vocabulary.migrated.txt`.
```

- [ ] **Step 3: Commit**

```bash
git commit -m "docs: add Dictionary and Style checks 81-91

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- docs/testing/manual-checklist.md docs/ROADMAP.md
```

---

## Self-review notes

- Spec §3.1 rules → Task 3; damaged/newer → Task 4; §3.2 migration → Tasks 3–4; §3.3 styles and legacy → Tasks 1–2, Insights label → Task 8; §3.4 routing → Task 1; §4 pipeline → Tasks 5–6; §5 pages → Tasks 7–8; §5.3 settings → Tasks 7–8; §7 checklist → Task 9 (adds 91 for the bundle-ID check the spec asks for in §3.4).
- Website chips on the Style page have no Move to… menu: overrides are keyed by bundle ID, so a website follows its built-in rule. Spec §5.2 "Each chip has Move to…" applies to app chips.
- Hero illustration threshold is measured on the card (700 pt), which is about a 900 pt window.
