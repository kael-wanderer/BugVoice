# Project Words Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. If neither skill is installed, execute the plan directly, task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repo folders the owner adds give their file and code names to speech-to-text and cleanup in coding apps, so `AppModel` stops coming out as "app model".

**Architecture:** VoiceCore extracts and ranks code-shaped names from a file list (pure, test-first), stores projects in `projects.json`, and picks the active project from the focused window title. The dictation and command pipelines add the picked words to the Whisper prompt and to one extra cleanup-prompt line. The app lists files (`git ls-files` or a walk), scans in the background, and shows Dictionary › Projects.

**Tech Stack:** Swift 6 package, macOS 15, SwiftUI/AppKit, Swift Testing. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-19-project-words-design.md` (mockup `docs/design/proposal-project-words.html`).

## Global Constraints

- `VoiceCore` imports Foundation only. TDD for VoiceCore: failing test first. `swift test` passes before every commit.
- No new dependency. WhisperKit stays `exact: "1.1.1"`.
- Nothing leaves the Mac except through the cleanup model the owner configured.
- Never keep file contents; only identifiers and file names. Skip `.env*`, `*.pem`, `*.key`, `*credentials*`, `*secret*`.
- Limits: 20 projects; 5,000 files; files over 256 KB or with a NUL byte in the first 8 KB skipped; 1,000 words kept per project; 150 words per cleanup prompt; Whisper prompt stays 600 characters; scan stops after 30 s.
- Coding apps default; setting values Coding apps / All apps / Off.
- UI copy: plain English, no hedging, no emoji; strings from the mockup.
- Commit after each task; the pre-commit hook raises the build, never edit CFBundleVersion.

## Review Focus

1. A Dictionary word that is also a project word appears once, Dictionary first (Task 3 test `dictionaryWordsNotRepeated`).
2. A Facebook post in Chrome gets no project words with the default setting (Task 3 test `nonCodingAppGetsNothing`).
3. Hidden words stay hidden after a rescan (Task 2 test `rescanKeepsHidden`).
4. A secret-looking file is never read, even when Git tracks it (Task 1 test `secretFilesSkipped`).
5. A window title "BugVoice-old" must not match project "BugVoice" over a better match; whole-word, longest wins (Task 3 test `longestWholeWordWins`).

---

### Task 1: Word extractor

**Files:**
- Create: `Sources/VoiceCore/ProjectWords.swift`
- Test: `Tests/VoiceCoreTests/ProjectWordExtractorTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct ProjectWord: Codable, Equatable, Sendable { public var word: String; public var rank: Int }
  public struct ProjectSourceFile: Sendable { public var path: String; public var contents: String? } // path relative to the folder; contents nil = not read
  public enum ProjectWordExtractor {
      public static let maxWords = 1_000
      public static let sourceExtensions: Set<String>   // swift m h c cc cpp rs go py rb js jsx ts tsx java kt cs php scala sh sql
      public static func shouldRead(path: String) -> Bool        // source extension and not secret-looking
      public static func isSecretLooking(path: String) -> Bool
      public static func isCodeShaped(_ token: String) -> Bool
      public static func fileNameWords(path: String) -> [String]
      public static func identifiers(in contents: String) -> [String]          // code-shaped, deduped per file
      public static func declared(in contents: String) -> Set<String>          // names after a declaration keyword
      public static func extract(files: [ProjectSourceFile], hidden: Set<String>) -> [ProjectWord]
  }
  ```

- [ ] **Step 1: Write the failing tests**

  - `codeShaped`: true for `AppModel`, `replaceLast`, `max_tokens`, `API_KEY`, `uncleanedText`; false for `model`, `Model`, `API`, `test`, `deadbeef12`, `a1b2c3d4e5`, `x123456`.
  - `fileNames`: `"Sources/BugVoice/AppModel+Models.swift"` → `["AppModel", "Models"]`; `"Scripts/build-app.sh"` → `["build-app.sh"]`; `"README.md"` → `[]` (single plain word); `"docs/HANDOFF.md"` → `[]`.
  - `identifiersFromSwift`: contents `"final class DictationController {\n func replaceLast(_ x: Int) { let model = AppModel() } }"` gives a set equal to `["DictationController", "replaceLast", "AppModel"]`.
  - `declaredNames`: same contents → `["DictationController", "replaceLast"]`; Python `"def load_settings():\nclass HistoryLog:"` → `["load_settings", "HistoryLog"]`.
  - `secretFilesSkipped`: `shouldRead` false for `.env`, `config/.env.local`, `certs/server.pem`, `keys/id.key`, `aws_credentials.py`, `my_secret_store.ts`; true for `Sources/App.swift`; false for `notes.md`.
  - `rankCountsFilesAndBoostsDeclared`: three files: A declares `AppModel` and uses `HistoryEntry`; B uses `AppModel`; C is `HistoryEntry.swift` with empty contents. Result: `AppModel` rank 2 files + 5 (declared) = 7; `HistoryEntry` rank 2 files (A as identifier, C as file name) + 5 (file name) = 7; a file counts once per word even when the word appears many times; tie → alphabetical, order `[AppModel, HistoryEntry]`. Add a fourth file D using `HistoryEntry` three times and assert its rank becomes 8.
  - `tiesAlphabetical`, `hiddenDropped` (hidden `["AppModel"]` removes it), `capsAtMaxWords` (1,200 distinct words → 1,000).

- [ ] **Step 2: Run `swift test --filter ProjectWordExtractorTests`** — expect compile failure on missing types.

- [ ] **Step 3: Implement in `Sources/VoiceCore/ProjectWords.swift`.**
  Code-shaped rule: token matches `^[A-Za-z_][A-Za-z0-9_]{3,39}$`; split into parts on `_` and on lower→upper / upper→Upper-lower boundaries; code-shaped when there are 2+ non-empty parts **and** the token is not a hash/ID (all hex and 8+ characters, or more digits than letters). File-name words: stem without extension, split on `+`; each piece kept if code-shaped; a stem containing `-` or `.` keeps the full file name with extension (`build-app.sh`). Declaration keywords: `class struct enum protocol actor extension func def fn type interface trait function`. Rank = number of files containing the word (as identifier or file name), +5 once if declared anywhere or a file name.

- [ ] **Step 4: Run `swift test --filter ProjectWordExtractorTests`** — PASS; then full `swift test`.

- [ ] **Step 5: Commit** `feat(core): project word extractor`

### Task 2: Project store and setting

**Files:**
- Modify: `Sources/VoiceCore/ProjectWords.swift` (model), `Sources/VoiceCore/Settings.swift` (`SpeechSettings`), `Sources/VoiceCore/AppPaths.swift`, `Sources/VoiceCore/BackupPlan.swift:14-16`
- Create: `Sources/VoiceCore/ProjectStore.swift`
- Test: `Tests/VoiceCoreTests/ProjectStoreTests.swift`, `Tests/VoiceCoreTests/SettingsTests.swift`

**Interfaces:**
- Consumes: `ProjectWord`, `ProjectWordExtractor.maxWords`.
- Produces:
  ```swift
  public enum ProjectWordsScope: String, Codable, Sendable, CaseIterable { case codingApps, allApps, off }
  // SpeechSettings.projectWordsScope: ProjectWordsScope = .codingApps (tolerant decode)
  public struct Project: Codable, Equatable, Sendable, Identifiable {
      public var id: UUID; public var path: String; public var name: String; public var enabled: Bool
      public var hidden: [String]; public var scannedAt: Date?; public var fileCount: Int
      public var words: [ProjectWord]; public var missing: Bool   // missing not encoded
  }
  public struct ProjectFile: Codable, Equatable, Sendable {
      public static let supportedSchemaVersion = 1; public static let maxProjects = 20
      public var schemaVersion: Int; public var projects: [Project]
      public mutating func add(path: String) -> (id: UUID, added: Bool)   // same standardized path → existing id, added false; name = last path component; throws nothing; returns added false when 20 exist
      public mutating func remove(id: UUID)
      public mutating func rename(id: UUID, to name: String)       // trimmed; empty ignored
      public mutating func setEnabled(id: UUID, _ on: Bool)
      public mutating func hide(_ word: String, in id: UUID)       // adds to hidden, removes from words
      public mutating func show(_ word: String, in id: UUID)       // removes from hidden (comes back on next scan)
      public mutating func applyScan(id: UUID, words: [ProjectWord], fileCount: Int, at: Date)   // filters hidden
      public mutating func relocate(id: UUID, to path: String)
      public func needsDailyScan(_ project: Project, now: Date) -> Bool    // scannedAt nil or older than 24 h, and not missing
  }
  public actor ProjectStore { public init(url: URL); public func load() -> ProjectFile; public func save(_ file: ProjectFile) throws }
  // AppPaths.projects → root/projects.json; BackupPlan.rootFiles gains "projects.json"
  ```

- [ ] **Step 1: Write the failing tests**
  - `addDedupesPath` (`/a/BugVoice` and `/a/BugVoice/` → one project, second call `added == false`, name `"BugVoice"`), `addStopsAtTwenty`.
  - `rescanKeepsHidden`: hide `"TODO_ITEM"`, then `applyScan` with words containing it → not in `words`, still in `hidden`.
  - `showRemovesFromHidden`, `renameTrimsAndIgnoresEmpty`, `relocateClearsMissing`.
  - `needsDailyScan`: nil → true; 23 h → false; 25 h → true; missing → false.
  - `roundTripAndTolerantDecode`: encode/decode equal (except `missing`); JSON `{"projects":[{"path":"/x","name":"x"}]}` decodes with defaults (`enabled` true, `words` empty, new id).
  - `storeLoadsMissingAsEmpty`, `storeSurvivesCorruptFile` (garbage → empty file, no throw).
  - In `SettingsTests`: `projectWordsScopeDefaultsToCodingApps`, unknown value `"x"` decodes to `.codingApps`.
  - In the backup tests file that covers `rootFiles`: `projects.json` is included when present.

- [ ] **Step 2: Run** `swift test --filter 'ProjectStoreTests|SettingsTests|Backup'` — expect failures.
- [ ] **Step 3: Implement.** Store writes atomically like `DictionaryStore.write`; corrupt file is moved to `projects.corrupt-<unix>.json`.
- [ ] **Step 4: Run tests** — PASS; full `swift test`.
- [ ] **Step 5: Commit** `feat(core): project store and setting`

### Task 3: Matching and prompts

**Files:**
- Create: `Sources/VoiceCore/ProjectMatcher.swift`
- Modify: `Sources/VoiceCore/Focus.swift` (`windowTitle: String?`, init param default nil), `Sources/VoiceCore/Vocabulary.swift`, `Sources/VoiceCore/PromptBuilder.swift`, `Sources/VoiceCore/CommandPrompt.swift`, `Sources/VoiceCore/DictationPipeline.swift`, `Sources/VoiceCore/CommandPipeline.swift`
- Test: `Tests/VoiceCoreTests/ProjectMatcherTests.swift`, `Tests/VoiceCoreTests/PromptBuilderTests.swift`, `Tests/VoiceCoreTests/VocabularyTests.swift`, `Tests/VoiceCoreTests/DictationPipelineTests.swift`

**Interfaces:**
- Consumes: `Project`, `ProjectWordsScope`, `StyleRouter`.
- Produces:
  ```swift
  public enum CodingApps {
      public static let bundleIDs: Set<String>   // com.microsoft.VSCode, com.microsoft.VSCodeInsiders, com.todesktop.230313mzl4w4u92, com.apple.dt.Xcode, dev.zed.Zed, com.stablyai.orca
      public static func contains(focus: FocusSnapshot, style: Style) -> Bool   // style == .terminal or bundle ID in set
  }
  public struct ProjectMatch: Equatable, Sendable { public var projectName: String?; public var words: [String] }
  public enum ProjectMatcher {
      public static let promptLimit = 150
      public static func match(focus: FocusSnapshot, style: Style, projects: [Project], scope: ProjectWordsScope,
                               excluding dictionaryTerms: [String], limit: Int = promptLimit) -> ProjectMatch
  }
  // Vocabulary: public var projectWords: [String] = []; public func with(projectWords:) -> Vocabulary
  // PromptBuilder.projectWordsLine(_ words: [String]) -> String   (exact copy below)
  // DictationPipeline.init / CommandPipeline.init gain `projects: [Project] = []`; DictationResult gains `projectName: String?` (not written to history)
  ```
  Exact prompt line: `"Code names from the current project. When the speaker says one as plain words, write the name exactly (for example \"app model\" is AppModel): " + words.joined(separator: ", ")`

- [ ] **Step 1: Write the failing tests**
  - `nonCodingAppGetsNothing`: Chrome focus, style `.personal`, scope `.codingApps` → `ProjectMatch(projectName: nil, words: [])`; same with `.allApps` → words non-empty.
  - `offGetsNothing`; `disabledProjectsIgnored`; `missingProjectsStillUsed` (words kept from last scan).
  - `titleMatchesWholeWord`: title `"AppModel.swift — BugVoice"` → `"BugVoice"`; title `"BugVoiceExtras"` does not match `"BugVoice"`.
  - `pathMatches`: title `"~/Kael/19-AppBuild/BugVoice"` with project path `/Users/me/Kael/19-AppBuild/BugVoice` → match (compare after replacing the home prefix with `~`, and the full path too).
  - `longestWholeWordWins`: projects `"BugVoice"` and `"BugVoice-old"`, title `"BugVoice-old — main.swift"` → `"BugVoice-old"`.
  - `noMatchInterleaves`: A `[a1,a2,a3]`, B `[b1,b2]`, limit 4 → `[a1,b1,a2,b2]`, `projectName == nil`.
  - `dictionaryWordsNotRepeated`: dictionary terms `["AppModel"]` → `"AppModel"` absent (case-sensitive compare), limit still filled from the next words.
  - `limitApplied`: 400 words → 150.
  - `VocabularyTests.whisperPromptAddsProjectWordsAfterTerms`: terms `["Kael"]`, projectWords `["AppModel","HistoryEntry"]` → `"Kael, AppModel, HistoryEntry"`; with a 20-character budget → `"Kael, AppModel"`.
  - `PromptBuilderTests.projectWordsLine`: system prompt contains the exact line when `projectWords` is non-empty, and no "Code names" text when empty.
  - `CommandPromptTests.includesProjectWords` (same line in a command request).
  - `DictationPipelineTests.projectWordsReachPrompts`: fake transcriber captures `options.prompt` containing `"AppModel"`, fake cleanup captures the system prompt containing the line; focus bundle `com.mitchellh.ghostty`, `windowTitle` `"BugVoice"`; `result.projectName == "BugVoice"`.
- [ ] **Step 2: Run** the filtered tests — expect failures.
- [ ] **Step 3: Implement.** Pipelines compute the match at the top of `run` from `startFocus` and their `style`, then shadow `vocabulary` with `vocabulary.with(projectWords: match.words)`; everything downstream stays unchanged.
- [ ] **Step 4: Run tests** — PASS; full `swift test`.
- [ ] **Step 5: Commit** `feat(core): project matching and prompt words`

### Task 4: File listing and scanning

**Files:**
- Create: `Sources/BugVoiceMac/ProjectScanner.swift`
- Modify: `Sources/BugVoiceMac/FocusInspector.swift` (read `windowTitle` from the frontmost app's `kAXFocusedWindowAttribute` → `kAXTitleAttribute`, 0.25 s messaging timeout, also when the element is secure)
- Test: `Tests/BugVoiceMacTests/ProjectScannerTests.swift`

**Interfaces:**
- Consumes: `ProjectWordExtractor`, `ProjectSourceFile`, `ProjectWord`.
- Produces:
  ```swift
  public struct ProjectScanResult: Equatable, Sendable { public var words: [ProjectWord]; public var fileCount: Int; public var stoppedEarly: Bool }
  public enum ProjectScanError: Error, Equatable { case folderNotFound, noCodeFiles }
  public enum ProjectScanner {
      public static let maxFiles = 5_000; public static let maxFileBytes = 256 * 1024
      public static let skippedFolders: Set<String>   // node_modules .build build dist DerivedData Pods vendor target venv .venv
      public static func listFiles(in folder: URL) async -> [String]            // git ls-files, else walk; relative paths; capped
      public static func scan(folder: URL, hidden: Set<String>, timeLimit: Duration = .seconds(30)) async throws -> ProjectScanResult
  }
  ```
  `git` runs as `Process` with `/usr/bin/git`, arguments `["-C", path, "ls-files", "-z"]`, no shell, 5 s timeout; a non-zero exit or timeout falls back to the walk. Contents are read only when `shouldRead(path:)`; size and NUL checks before decoding as UTF-8 (invalid UTF-8 skipped).

- [ ] **Step 1: Write the failing tests** (temporary folders; no network)
  - `walkSkipsIgnoredFolders`: files in `node_modules/x.js`, `.build/y.swift`, `.hidden/z.swift`, `Sources/App.swift` → only `Sources/App.swift`.
  - `gitListRespectsIgnore`: `git init`, `.gitignore` containing `Generated/`, files `Generated/G.swift` and `Sources/AppModel.swift`, `git add -A` → list has `Sources/AppModel.swift`, not `Generated/G.swift`. Mark `.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git"))`.
  - `scanFindsWords`: `Sources/AppModel.swift` with `final class AppModel { func replaceLast() {} }` → words contain `AppModel`, `replaceLast`; `fileCount == 1`.
  - `largeAndBinaryFilesSkipped`: a 300 KB `.swift` file and one with a NUL byte → their identifiers absent.
  - `secretFileNeverRead`: `.env` containing `SECRET_TOKEN_VALUE=…` and `aws_credentials.py` containing `class LeakedCredential` → neither name in the words.
  - `missingFolderThrows` → `.folderNotFound`; `emptyFolderThrows` → `.noCodeFiles`.
  - `timeLimitStopsEarly`: `timeLimit: .zero` with files → `stoppedEarly == true`, no throw.
- [ ] **Step 2: Run** `swift test --filter ProjectScannerTests` — expect failures.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run tests** — PASS; full `swift test`.
- [ ] **Step 5: Commit** `feat(mac): project scanner and window title`

### Task 5: App wiring and Projects tab

**Files:**
- Create: `Sources/BugVoice/ProjectsController.swift`, `Sources/BugVoice/UI/Dictionary/ProjectsView.swift`
- Modify: `Sources/BugVoice/AppModel.swift` (load at bootstrap; pass `projects` to `makePipeline` and `makeCommandPipeline`; record last match), `Sources/BugVoice/UI/Dictionary/DictionaryPage.swift` (`DictionaryTab.projects`, pill "Projects"), `Sources/BugVoice/UI/Settings/SpeechTab.swift`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces (app-internal): `AppModel.projects: ProjectFile`, `AppModel.projectScanState: [UUID: ProjectScanStatus]` (`.scanning(files: Int)`, `.failed(String)`, `.stopped(files: Int)`), `AppModel.lastProjectMatch: (name: String, app: String, at: Date)?`; `ProjectsController` with `add(url:)`, `rescan(id:)`, `remove(id:)`, `rename(id:to:)`, `setEnabled(id:_:)`, `hide(_:in:)`, `show(_:in:)`, `relocate(id:to:)`, `addToDictionary(_:)`, `scanDueProjects()`.

- [ ] **Step 1: Controller.** Scans run in a detached `.utility` task, one at a time; results applied and saved on the main actor. At bootstrap: load, mark `missing` for folders that do not exist, then `scanDueProjects()`. `add(url:)` selects the existing card when the path is already there and scans new ones at once. `addToDictionary` uses the existing `editDictionary` word insert.
- [ ] **Step 2: Wire pipelines.** `makePipeline` and `makeCommandPipeline` pass `projects.projects`; after each dictation or command with `projectName != nil`, set `lastProjectMatch`.
- [ ] **Step 3: Projects tab** per mockup screen 1–2: cards (editable name, path, "412 words · 386 files · scanned 2 h ago", switch, Rescan, Remove), word chips with rank, × hides, click adds to Dictionary, "Show all 412", Hidden row with ↺, scanning bar "Scanning… 1,240 files", errors "Folder not found — words kept from the last scan" with **Locate…**, "No code files found", "Stopped after 30 s — 3,100 files read", footer "Last match: BugVoice in Ghostty, 2 min ago", empty state copy, **Add folder…** via `NSOpenPanel` (directories only). At 20 projects the button is disabled with help "20 projects at most".
- [ ] **Step 4: Settings › Speech:** segmented "Use project words in" Coding apps / All apps / Off with footnote "Coding apps: Terminal-style apps, VS Code, Cursor, Xcode, Zed and Orca. Manage folders in Dictionary › Projects."
- [ ] **Step 5:** `swift test`, `Scripts/build-app.sh`; read-only smoke: Dictionary › Projects empty state and Settings › Speech row render (no folder added to the owner's library unless restored afterwards).
- [ ] **Step 6: Commit** `feat(app): project words`

### Task 6: Docs and device checks

**Files:**
- Create: `docs/progress/project-words-log.md`
- Modify: `AGENTS.md` (Key documents: plan and log lines), `docs/progress/HANDOFF.md`, `docs/propose-new-features.md` (item 7 status)

- [ ] **Step 1:** Log: commits, test counts per target, deviations, then device checks P1–P8 with Result / Evidence columns:
  - P1 Add BugVoice folder: card shows words incl. `AppModel`, `DictationController`; scan under 2 s.
  - P2 In Ghostty at the BugVoice folder, say "open app model plus models and check replace last": text has `AppModel+Models` and `replaceLast`; footer shows "Last match: BugVoice in Ghostty".
  - P3 Same sentence in Notes or a Facebook post with Coding apps: no code names.
  - P4 Hide a word, Rescan: still hidden; ↺ brings it back after the next scan.
  - P5 Rename for an Orca worktree name; dictating in Orca matches it.
  - P6 Move the folder: "Folder not found"; Locate… fixes it.
  - P7 Command mode in VS Code uses the words.
  - P8 Backup then restore keeps the project list and hidden words.
- [ ] **Step 2:** `swift test`; commit `docs: project words log and handoff`.
