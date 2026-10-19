# Shortcuts Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. If neither skill is installed, execute the plan directly, task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Six BugVoice actions in the Shortcuts app (three also as App Shortcuts in Spotlight and Siri), built into the app bundle by `Scripts/build-app.sh`.

**Architecture:** VoiceCore gets the pure parts, test-first: `ShortcutsActions` (parameter checks, folder and meeting lookup, action item lines, error copy) and a text-only `CommandPipeline.rewrite`. The app target gets one App Intent per action in `Sources/BugVoice/Intents/`, a bridge that waits for `AppModel` bootstrap, and an `AppShortcutsProvider`. The intents call the same `AppModel` / controller functions as the menu bar and MCP. `build-app.sh` runs `appintentsmetadataprocessor` and copies `Metadata.appintents` into the bundle.

**Tech Stack:** Swift 6 package, macOS 15, SwiftUI/AppKit, App Intents (system framework), Swift Testing. No new dependency.

**Spec:** `docs/superpowers/specs/2026-10-19-shortcuts-design.md` (mockup `docs/design/proposal-shortcuts.html`).

## Global Constraints

- `VoiceCore` imports Foundation only. TDD for VoiceCore. `swift test` passes before every commit.
- No new package dependency. `AppIntents` is imported only in `Sources/BugVoice/Intents/`.
- Every action runs with BugVoice in the menu bar: `openAppWhenRun = false` on every intent; no window opens.
- Local unless the owner configured a remote model or server; never paste anything (no action pastes).
- Rewrite: Dictation cleanup model through `AppModel.makeCommandPipeline()`, 30 s timeout (`CommandPipeline.timeoutSeconds`), at most 8,000 characters (`CommandPrompt.maxSelection`).
- Transcribe: through `UploadController`, same file types as Upload (`MCPTools.uploadExtensions`), waits at most 30 minutes.
- Action items limit: default 50, clamped to 1–200.
- Bootstrap wait: at most 10 s, then "BugVoice is still starting. Try again in a moment."
- No new setting. One footnote in Settings › Shortcuts.
- UI copy: plain English, no hedging, no emoji; strings exactly as in the spec table and mockup.
- Commit after each task; the pre-commit hook raises the build, never edit CFBundleVersion.

## Review Focus

1. Folder name typed with different case or without diacritics ("work", "ca nhan") finds "Work" / "Cá nhân"; a blank folder parameter means Unfiled, not an error (Task 1 tests `folderMatchesFolded`, `blankFolderIsUnfiled`).
2. Text exactly 8,000 characters is accepted, 8,001 is refused; whitespace-only text or instruction is refused before any model call (Task 1 test `rewriteLimits`).
3. The model wraps its answer in quotes or a "Here is the text:" line: the action returns the clean text, same as command mode (Task 2 test `rewriteSanitizes`).
4. Two meetings with the same title: Get open action items with that title returns items from both, newest first; an unknown title is an error, not an empty list (Task 1 tests `meetingTitleMatchesAll`, `unknownMeetingTitle`).
5. Transcribe with Wait off returns at once with the meeting title placeholder (file name); with Wait on, an upload that fails returns the upload's own error message, not the 30-minute message (Task 4, device check S5).

---

### Task 1: ShortcutsActions (VoiceCore)

**Files:**
- Create: `Sources/VoiceCore/ShortcutsActions.swift`
- Test: `Tests/VoiceCoreTests/ShortcutsActionsTests.swift`

**Interfaces:**
- Consumes: `MCPResolve.folder(_:in:)`, `AskText.fold(_:)`, `LibraryFolder`, `FolderID`, `MeetingManifest`, `ActionItemBoard`, `ActionItemFile`, `ActionItemRow`, `CommandFailure`, `CommandPrompt.maxSelection`, `SpeechLanguage`.
- Produces:
  - `public enum ShortcutsLanguage: String, CaseIterable, Sendable { case auto, english, vietnamese }` with `public var languages: [SpeechLanguage]?` (`auto` → `nil` meaning the Meetings setting, `english` → `[.en]`, `vietnamese` → `[.vi]`).
  - `public enum ShortcutsError: Error, Equatable, Sendable` with `public var message: String`.
  - `public enum ShortcutsActions` with the static members below.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func errorCopy() {
    #expect(ShortcutsError.meetingAlreadyRecording.message == "A meeting is already recording.")
    #expect(ShortcutsError.noMeetingRecording.message == "No meeting is recording.")
    #expect(ShortcutsError.transcriptTimeout.message == "Still transcribing after 30 minutes. The transcript will finish in BugVoice › Meetings.")
    #expect(ShortcutsError.noFolder("Wrok").message == "No folder named “Wrok”.")
    #expect(ShortcutsError.noMeeting("Standup").message == "No meeting named “Standup”.")
    #expect(ShortcutsError.textTooLong.message == "Text too long — 8,000 characters at most")
    #expect(ShortcutsError.emptyText.message == "No text to rewrite.")
    #expect(ShortcutsError.emptyInstruction.message == "No instruction given.")
    #expect(ShortcutsError.notReady.message == "BugVoice is still starting. Try again in a moment.")
    #expect(ShortcutsError.command(.noModel).message == "Command mode needs a text model — choose one in Settings › Models")
    #expect(ShortcutsError.command(.modelFailed).message == "Command failed — model unavailable")
    #expect(ShortcutsError.command(.outputTooLong).message == "The model's answer was too long")
    #expect(ShortcutsError.other("Could not read the file.").message == "Could not read the file.")
}
@Test func languageMapping() {
    #expect(ShortcutsLanguage.auto.languages == nil)
    #expect(ShortcutsLanguage.english.languages == [.en])
    #expect(ShortcutsLanguage.vietnamese.languages == [.vi])
}
@Test func folderMatchesFolded()   // folders "Work", "Cá nhân": "work" → Work's id, " ca nhan " → Cá nhân's id
@Test func blankFolderIsUnfiled()  // nil, "", "  " → .success(nil)
@Test func unknownFolder()         // "Wrok" → .failure(.noFolder("Wrok")); the name is trimmed in the message
@Test func rewriteLimits() {
    #expect(ShortcutsActions.checkRewrite(text: String(repeating: "a", count: 8_000), instruction: "shorter") == nil)
    #expect(ShortcutsActions.checkRewrite(text: String(repeating: "a", count: 8_001), instruction: "shorter") == .textTooLong)
    #expect(ShortcutsActions.checkRewrite(text: " \n", instruction: "shorter") == .emptyText)
    #expect(ShortcutsActions.checkRewrite(text: "hello", instruction: "  ") == .emptyInstruction)
}
@Test func limitBounds() {
    #expect(ShortcutsActions.clampLimit(nil) == 50)
    #expect(ShortcutsActions.clampLimit(0) == 1)
    #expect(ShortcutsActions.clampLimit(500) == 200)
    #expect(ShortcutsActions.clampLimit(20) == 20)
}
@Test func actionItemLine() {
    // item "Send the build to QA", owner "Kael", meeting "Weekly mobile sync"
    #expect(line == "Send the build to QA (Kael) — Weekly mobile sync")
    // no owner
    #expect(lineNoOwner == "Update the docs — Weekly mobile sync")
}
@Test func openItemsNewestFirstAndLimited()  // two meetings, older has 2 open, newer 1 open + 1 done; limit 2 → [newer open, older first]
@Test func meetingTitleMatchesAll()          // two meetings titled "Standup" and one "Retro"; meeting "standup" → items of both Standups only
@Test func unknownMeetingTitle()             // meeting "Nope" → .failure(.noMeeting("Nope"))
@Test func noOpenItemsIsEmptyList()          // all done → .success([])
```

- [ ] **Step 2: Run, expect failures**

Run: `swift test --filter ShortcutsActionsTests`
Expected: FAIL, `ShortcutsActions` not defined.

- [ ] **Step 3: Implement in `Sources/VoiceCore/ShortcutsActions.swift`**

```swift
public enum ShortcutsError: Error, Equatable, Sendable {
    case meetingAlreadyRecording, noMeetingRecording, transcriptTimeout, textTooLong,
         emptyText, emptyInstruction, notReady
    case noFolder(String), noMeeting(String), command(CommandFailure), other(String)
    public var message: String
}
public enum ShortcutsActions {
    public static let defaultLimit = 50
    public static let maxLimit = 200
    public static let transcriptWait: TimeInterval = 30 * 60
    public static let bootstrapWait: TimeInterval = 10
    public static func folder(_ name: String?, in folders: [LibraryFolder]) -> Result<FolderID?, ShortcutsError>
    public static func checkRewrite(text: String, instruction: String) -> ShortcutsError?
    public static func clampLimit(_ limit: Int?) -> Int
    public static func actionItemLine(_ row: ActionItemRow, meetingTitle: String) -> String
    public static func openActionItems(meetings: [MeetingManifest], done: ActionItemFile, meeting: String?,
                                       limit: Int?, now: Date) -> Result<[String], ShortcutsError>
}
```

`command(f).message` is `f.title` plus `" — " + detail` when `detail` is non-nil. `folder` reuses `MCPResolve.folder` and maps its failure to `.noFolder(trimmed)`. `openActionItems` filters meetings by `AskText.fold(title) == AskText.fold(meeting)` (trimmed; blank means all), builds `ActionItemBoard(status: .open, owner: .anyone, range: .all, query: "")`, flattens groups in board order, takes `clampLimit(limit)`.

- [ ] **Step 4: Run, expect pass**

Run: `swift test --filter ShortcutsActionsTests` then `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceCore/ShortcutsActions.swift Tests/VoiceCoreTests/ShortcutsActionsTests.swift
git commit -m "feat(core): shortcuts action checks and copy"
```

### Task 2: Text-only rewrite in CommandPipeline (VoiceCore)

**Files:**
- Modify: `Sources/VoiceCore/CommandPipeline.swift`
- Test: `Tests/VoiceCoreTests/CommandPipelineTests.swift` (reuse its fake transcriber and fake cleanup model)

**Interfaces:**
- Consumes: `ShortcutsActions.checkRewrite`, `ShortcutsError` (Task 1).
- Produces: `public func rewrite(text: String, instruction: String) async -> Result<String, ShortcutsError>` on `CommandPipeline`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func rewriteReturnsModelText()   // model returns "Short." → .success("Short."); request.user contains "<instruction>\nshorter\n</instruction>" and "<text>\nLong text here.\n</text>"
@Test func rewriteSanitizes()          // model returns "Here is the text:\n“Short.”" → .success("Short.")
@Test func rewriteNoModel()            // pipeline with model nil → .failure(.command(.noModel))
@Test func rewriteModelThrows()        // fake throws → .failure(.command(.modelFailed))
@Test func rewriteTimeout()            // fake sleeps 1 s, pipeline timeout 0.1 → .failure(.command(.modelFailed))
@Test func rewriteChecksFirst()        // text of 8,001 chars → .failure(.textTooLong) and the fake model was never called
@Test func rewriteOutputTooLong()      // output > 4×text + 2,000 chars → .failure(.command(.outputTooLong))
@Test func rewriteEmptyOutput()        // output "  " → .failure(.command(.emptyOutput))
```

- [ ] **Step 2: Run, expect failures**

Run: `swift test --filter CommandPipelineTests`
Expected: FAIL, `rewrite(text:instruction:)` not found.

- [ ] **Step 3: Implement `rewrite(text:instruction:)`**

Order: `checkRewrite` first, then `model == nil` → `.command(.noModel)`. Build the request with `CommandPrompt.request(instruction:selection: text, style: .other, focus: FocusSnapshot(appName: "Shortcuts"), vocabulary: vocabulary.with(projectWords: []), language: settings.speech.language, keepEnglishWords: settings.speech.keepEnglishWords, modelID:disableThinking:)` from the model. Same `withTimeout(seconds: timeout)` call and same `CommandOutput.sanitize(_, selection: text)` mapping as `run`. No project words: there is no focused app to match.

- [ ] **Step 4: Run, expect pass**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceCore/CommandPipeline.swift Tests/VoiceCoreTests/CommandPipelineTests.swift
git commit -m "feat(core): text-only command rewrite"
```

### Task 3: App plumbing for the intents

**Files:**
- Create: `Sources/BugVoice/Intents/ShortcutsBridge.swift`
- Modify: `Sources/BugVoice/AppModel.swift` (end of `bootstrap()`), `Sources/BugVoice/UploadController.swift` (`Draft`, `submitForAgent`, `run(_:)`), `Sources/BugVoice/MeetingController.swift` only if needed to read the start failure (see Step 3)

**Interfaces:**
- Consumes: `ShortcutsError`, `ShortcutsActions.bootstrapWait` (Task 1).
- Produces:
  - `@MainActor enum ShortcutsBridge { static weak var model: AppModel?; static func ready() async throws -> AppModel }` — returns the model once `model`, `model.meetings` and `model.uploads` are non-nil; polls every 0.1 s up to `bootstrapWait`; throws `ShortcutsError.notReady`.
  - `extension ShortcutsError: CustomLocalizedStringResourceConvertible` (in this file, the app target) returning `message`, so Shortcuts shows the sentence.
  - `UploadController.submitForAgent(url:title:labels:client:languages:)` with new last parameter `languages: [SpeechLanguage]? = nil`.

- [ ] **Step 1: Bridge**

Write `ShortcutsBridge` as above. At the end of `AppModel.bootstrap()` set `ShortcutsBridge.model = self`.

- [ ] **Step 2: Upload language**

Add `var languages: [SpeechLanguage]?` to `UploadController.Draft`; `submitForAgent` stores it on the draft. In `run(_:)`, the scheduler gets `languages: inputs[job.id]?.languages ?? model.settings.meetings.languages` (read the draft before it is removed, if `run` removes it). Existing MCP calls keep passing nothing. Relaunch does not keep the choice (agent uploads restored after relaunch use the setting), which is acceptable.

- [ ] **Step 3: Build**

Run: `swift build` and `swift test`
Expected: both succeed; no behaviour change yet.

- [ ] **Step 4: Commit**

```bash
git add Sources/BugVoice/Intents/ShortcutsBridge.swift Sources/BugVoice/AppModel.swift Sources/BugVoice/UploadController.swift
git commit -m "feat(app): shortcuts bridge and upload language"
```

### Task 4: The six intents and App Shortcuts

**Files:**
- Create in `Sources/BugVoice/Intents/`: `StartMeetingIntent.swift`, `StopMeetingIntent.swift`, `TranscribeFileIntent.swift`, `RewriteTextIntent.swift`, `NewNoteIntent.swift`, `ActionItemsIntent.swift`, `BugVoiceShortcuts.swift`

**Interfaces:**
- Consumes: `ShortcutsBridge.ready()`, `ShortcutsActions.*`, `ShortcutsError`, `ShortcutsLanguage`, `CommandPipeline.rewrite`, `UploadController.submitForAgent(...languages:)`, `UploadController.jobStatus(id:)`, `MeetingController.start()` / `stop()` / `isRecording` / `title`, `NotesController.createForAgent(title:body:frontMatter:)`, `MeetingExport.transcriptText(_:)`, `model.meetingManifests`, `model.actionItemsDone`, `model.libraryFolders` (whatever `MCPService` uses for `folders`).
- Produces: nothing other tasks consume.

Each intent: `static let openAppWhenRun = false`, `@MainActor func perform() async throws`, first line `let model = try await ShortcutsBridge.ready()`, errors thrown as `ShortcutsError`. Titles and descriptions exactly as mockup screen 1. Parameter summaries left to the builder.

- [ ] **Step 1: StartMeetingIntent** — "Start meeting recording". Parameter `title: String?`. If `meetings.isRecording` throw `.meetingAlreadyRecording`. `await meetings.start()`; if still not recording throw `.other(meetings.statusMessage ?? "Could not start the meeting.")` (expose `statusMessage` read access if private). If a trimmed title is given, `await meetings.rename(title)`. Returns `ReturnsValue<String>` = `meetings.title`.

- [ ] **Step 2: StopMeetingIntent** — "Stop meeting recording". Not recording → `.noMeetingRecording`. Capture `meetings.title`, `await meetings.stop()`, return the title.

- [ ] **Step 3: TranscribeFileIntent** — "Transcribe audio file". Parameters: `file: IntentFile` (supported content types: audio and movie), `language: ShortcutsLanguageEntity` (an `AppEnum` wrapping `ShortcutsLanguage`, titles "Auto", "English", "Vietnamese", default Auto), `wait: Bool` (default true, title "Wait for transcript"). Copy the file into a new folder under `FileManager.default.temporaryDirectory` when `file.fileURL` is nil or not readable (Shortcuts may hand over data only), keeping the file name; check the extension against `MCPTools.uploadExtensions` (error `.other(MCPTools.unsupportedType(ext))`). Submit with `client: "Shortcuts"`, `labels: ItemLabels()`, `languages: language.languages`. Wait off: return the file name without extension. Wait on: poll `jobStatus(id:)` every second; `.ready` with `meetingID` → find the manifest in `model.meetingManifests` and return `MeetingExport.transcriptText(_:)`; `.failed` → `.other(job.errorMessage ?? UploadFailure.unreadable.localizedDescription)`; `.cancelled` → `.other("The transcription was cancelled.")`; after `transcriptWait` → `.transcriptTimeout`. Report progress with `progress.completedUnitCount` from `job.progress` when present. Task cancellation (the owner stops the shortcut) stops waiting but leaves the upload running.

- [ ] **Step 4: RewriteTextIntent** — "Rewrite text". Parameters `text: String` (multiline), `instruction: String`. `await model.makeCommandPipeline().rewrite(text:instruction:)`; success returns the text, failure throws.

- [ ] **Step 5: NewNoteIntent** — "New note". Parameters `text: String` (multiline), `title: String?`, `folder: String?` (title "Folder", plain name). Resolve folder with `ShortcutsActions.folder(_:in:)`, then the same call `MCPService.createNote` makes (`notesController.createForAgent` with `MCPService.labels`-equivalent front matter; move `labels(folderID:tags:)` to an internal place both can call if it is private). Blank title → "Untitled". Returns the note title.

- [ ] **Step 6: ActionItemsIntent** — "Get open action items". Parameters `meeting: String?` (title "Meeting"), `limit: Int` (default 50, title "Limit"). Returns `[String]` from `ShortcutsActions.openActionItems(meetings: model.meetingManifests, done: model.actionItemsDone, meeting:limit:now: Date())`.

- [ ] **Step 7: BugVoiceShortcuts** — `struct BugVoiceShortcuts: AppShortcutsProvider` with three `AppShortcut`s:
  - `StartMeetingIntent()`, phrases `"Start a meeting in \(.applicationName)"`, `"Start recording a meeting in \(.applicationName)"`, short title "Start meeting", symbol `record.circle`.
  - `StopMeetingIntent()`, phrase `"Stop the meeting in \(.applicationName)"`, short title "Stop meeting", symbol `stop.circle`.
  - `NewNoteIntent()`, phrase `"New \(.applicationName) note"`, short title "New note", symbol `note.text.badge.plus`.

- [ ] **Step 8: Build and test**

Run: `swift build` and `swift test`
Expected: both succeed.

- [ ] **Step 9: Commit**

```bash
git add Sources/BugVoice/Intents Sources/BugVoice/MCPService.swift Sources/BugVoice/MeetingController.swift
git commit -m "feat(app): shortcuts actions and app shortcuts"
```

### Task 5: Bundle metadata, Settings footnote, docs

**Files:**
- Modify: `Scripts/build-app.sh`, `Sources/BugVoice/UI/Settings/ShortcutsSettingsView.swift`, `AGENTS.md`, `docs/progress/HANDOFF.md`, `docs/propose-new-features.md`
- Create: `docs/progress/shortcuts-log.md`

- [ ] **Step 1: Metadata step in `build-app.sh`**, after the `cp "$BIN/$APP_NAME" ...` line and before signing:

```bash
XCODE_DEVELOPER="${BUGVOICE_XCODE_DEVELOPER:-/Applications/Xcode.app/Contents/Developer}"
if PROCESSOR="$(DEVELOPER_DIR="$XCODE_DEVELOPER" xcrun --find appintentsmetadataprocessor 2>/dev/null)"; then
    # inputs: module BugVoice, Sources/BugVoice/**/*.swift as the source list,
    # the *.swiftconstvalues under .build/out/Intermediates.noindex/BugVoice.build/<Configuration dir>/
    # (match the configuration case-insensitively), binary "$BIN/$APP_NAME",
    # toolchain "$XCODE_DEVELOPER/Toolchains/XcodeDefault.xctoolchain",
    # SDK from `DEVELOPER_DIR=... xcrun --sdk macosx --show-sdk-path`,
    # --xcode-version from `DEVELOPER_DIR=... xcodebuild -version` (build number line),
    # --platform-family macOS --deployment-target 15.0 --target-triple arm64-apple-macos15.0,
    # output into a temp dir, then cp -R its Metadata.appintents into "$CONTENTS/Resources/".
    :
else
    echo "Skipping Shortcuts metadata: Xcode not found"
fi
```

The exact processor flags are in the spec's spike note (`--output --toolchain-dir --module-name --sdk-root --xcode-version --platform-family --deployment-target --target-triple --source-file-list --swift-const-vals-list --binary-file`). A processor failure fails the build (`set -e`); zero `.swiftconstvalues` files found is an error with a clear message, not a silent skip.

- [ ] **Step 2: Verify the bundle**

Run: `Scripts/build-app.sh && ls build/BugVoice.app/Contents/Resources/Metadata.appintents && codesign --verify --strict build/BugVoice.app`
Expected: `extract.actionsdata` listed, verify passes. Then `plutil -p` or `strings` on `extract.actionsdata` shows all six intent type names and the four phrases.

Run: `BUGVOICE_XCODE_DEVELOPER=/nonexistent Scripts/build-app.sh`
Expected: "Skipping Shortcuts metadata: Xcode not found", app builds and signs.

- [ ] **Step 3: Settings footnote** — under the Dictation card in `ShortcutsSettingsView`, footnote style as other Settings footnotes: "BugVoice actions are also in the Shortcuts app: start and stop meetings, transcribe files, rewrite text, new notes and open action items."

- [ ] **Step 4: Docs** — `docs/progress/shortcuts-log.md` with what was built and device checks:
  - S1 After `Scripts/build-app.sh` and `Scripts/run-dev-app.sh`, the Shortcuts app lists the six BugVoice actions with the mockup's descriptions (relaunch BugVoice once if not).
  - S2 Spotlight "start a meeting" shows the BugVoice App Shortcut; running it starts recording with BugVoice in the menu bar only.
  - S3 Stop meeting recording returns the title; running it again errors "No meeting is recording."
  - S4 Start meeting recording with a title while one is recording errors "A meeting is already recording."
  - S5 Transcribe a short voice memo (Language Auto, Wait on) returns the transcript; the meeting appears in Meetings; Wait off returns at once.
  - S6 Rewrite text "make it shorter" returns rewritten text; with no Dictation model it errors with the Settings › Models sentence.
  - S7 New note with Folder "Wrok" errors "No folder named “Wrok”."; with a real folder the note is in that folder.
  - S8 Get open action items returns lines "item (owner) — meeting", newest meeting first.
  - S9 Quit BugVoice, run a BugVoice shortcut: BugVoice launches and the action runs (or the still-starting error after 10 s).
  - S10 Settings › Shortcuts shows the footnote.
  Add an AGENTS.md line for the log, a HANDOFF.md entry, mark item 6 in `docs/propose-new-features.md` as built.

- [ ] **Step 5: Commit**

```bash
git add Scripts/build-app.sh Sources/BugVoice/UI/Settings/ShortcutsSettingsView.swift AGENTS.md docs
git commit -m "feat(app): shortcuts metadata in the bundle, settings footnote, docs"
```
