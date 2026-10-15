# Folders and Tags Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One level of folders plus tags, shared by Notes, Meetings and Upload, with AI tag suggestions after a meeting summary.

**Architecture:** Pure folder/tag logic, `library.json` storage, note front matter, manifest fields, filtering and suggestion parsing live in `VoiceCore` (TDD). `NotesController` and `MeetingSession` gain label writes. `AppModel` owns the library and routes label writes like rename. Shared SwiftUI views in `Sources/BugVoice/UI/Library/` are used by the Meetings, Notes and Upload pages.

**Tech Stack:** Swift 6.4 (tools 6.0), SwiftUI/AppKit, Swift Testing (`import Testing`), macOS 15 floor.

**Spec:** `docs/superpowers/specs/2026-10-15-folders-tags-design.md`. Mockup: `docs/design/proposal-folders.html`. Read both before starting.

## Global Constraints

- Swift package, tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only.
- Exactly one external dependency: WhisperKit pinned `exact: "1.1.1"`. Add none.
- TDD for everything in `VoiceCore`: failing test first, then code. `swift test` must pass before every commit.
- Build the app only with `Scripts/build-app.sh` (signs with `Bugler Local Dev`). Never ad hoc signing.
- UI copy: plain English, no hedging words, no emoji. Use the exact strings in this plan.
- Never send text off this Mac except to the Meetings provider the user configured (tag suggestions use it exactly like the summary).
- Folders are labels: never move, rename or delete a note or meeting file because of a folder change.
- Commit after each task, by path (`git add <paths>`), message style `feat(core): …`, `feat(app): …`, `docs: …`, ending with the trailer `Co-Authored-By: Codex <noreply@openai.com>`.
- Leave the untracked `.vscode/` alone. Search with `rg`.
- Run tests with `swift test` (whole suite) or `swift test --filter <SuiteName>`.

## Review Focus

1. A note that already has front matter written by another app (`aliases:`, `created:`) — BugVoice keeps those lines, in order, after adding its own keys. Pinned in Task 3.
2. Changing a note's folder or tags while its body has unsaved typing — both the typing and the labels reach disk. Pinned in Task 4.
3. Filing or tagging a meeting while it is still recording — the labels survive Stop and the final transcription save. Pinned in Task 5.
4. The folder used as a page filter or as the Upload default is deleted — the filter falls back to All and the Upload default to Unfiled. Pinned in Task 6 (`FolderFilter.resolved`) and Task 2 (`delete` clears `lastUploadFolderID`).
5. The model answers a tag suggestion with prose, a `<think>` block, numbering or invented tags — only allowed tags not already on the meeting survive, at most 3. Pinned in Task 7.

---

## File Structure

| File | Responsibility |
|---|---|
| Create `Sources/VoiceCore/LibraryLabels.swift` | `FolderID`, `TagName`, `ItemLabels` |
| Create `Sources/VoiceCore/Library.swift` | `LibraryFolder`, `LibraryFile`, `LibraryFolderError`, `LibraryFolders`, `LibraryLoadResult`, `LibraryStore` |
| Modify `Sources/VoiceCore/NotesDocument.swift` | `NoteFrontMatter`, front matter parse/serialize |
| Modify `Sources/VoiceCore/Notes.swift` | `NoteDocument.frontMatter`, `NotesListItem.tags` |
| Modify `Sources/VoiceCore/NotesListProjection.swift` | search matches tags |
| Modify `Sources/BugVoiceMac/NotesStore.swift` | write/read front matter on create/save/rename |
| Modify `Sources/BugVoiceMac/NotesController.swift` | `create(title:frontMatter:)`, `setLabels` |
| Modify `Sources/VoiceCore/Meeting.swift` | manifest `folderID`, `tags`, `suggestedTags`; search matches tags |
| Modify `Sources/VoiceCore/MeetingSession.swift` | `start(labels:)`, `setLabels` |
| Create `Sources/VoiceCore/LibraryProjection.swift` | `FolderFilter`, `LibraryLabeled`, `FolderCounts`, `TagCount`, `LibraryProjection` |
| Create `Sources/VoiceCore/TagSuggestion.swift` | prompt + parser |
| Modify `Sources/VoiceCore/AppPaths.swift`, `Sources/VoiceCore/Settings.swift` | `library` path, `LibrarySettings` |
| Modify `Sources/BugVoice/AppModel.swift` | library state, folder ops, label routing, suggestions |
| Modify `Sources/BugVoice/MeetingController.swift`, `Sources/BugVoice/UploadController.swift` | label routing into live sessions; upload draft labels |
| Create `Sources/BugVoice/UI/Library/FolderControls.swift` | `FolderFilterMenu`, `TagFilterBar`, `FolderPicker`, `NewFolderSheet` |
| Create `Sources/BugVoice/UI/Library/TagField.swift` | tag chips + autocomplete field |
| Create `Sources/BugVoice/UI/Library/LabelsBox.swift` | Folder/Tags/Suggested box |
| Create `Sources/BugVoice/UI/Library/ManageFoldersSheet.swift` | Folders sheet |
| Modify `Sources/BugVoice/UI/MeetingsPage.swift`, `Sources/BugVoice/UI/NotesPage.swift`, `Sources/BugVoice/UI/UploadPage.swift` | page integration |
| Modify `docs/testing/manual-checklist.md`, `docs/progress/HANDOFF.md` | checks and status |

---

### Task 1: FolderID, TagName, ItemLabels

**Files:**
- Create: `Sources/VoiceCore/LibraryLabels.swift`
- Test: `Tests/VoiceCoreTests/LibraryLabelsTests.swift`

**Interfaces:**
- Produces: `FolderID` (`rawValue: String`, `static func new() -> FolderID`, Codable as a plain string); `TagName.normalize(_ raw: String) -> String?`, `TagName.maxLength = 32`; `ItemLabels { folderID: FolderID?; tags: [String]; static let maxTags = 10; mutating func addTag(_:) -> ItemLabels.AddResult; mutating func removeTag(_:) }`, `AddResult { added, duplicate, invalid, full }`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import VoiceCore

struct LibraryLabelsTests {
    @Test(arguments: [
        ("#Decision", "decision"),
        ("  Họp  team ", "họp-team"),
        ("a/b", "a/b"),
        ("client_X", "client_x"),
        ("##todo", "todo"),
        ("ship🚀it", "shipit"),
        ("-edge-", "edge"),
    ])
    func normalizes(raw: String, expected: String) {
        #expect(TagName.normalize(raw) == expected)
    }

    @Test(arguments: ["###", "   ", "🚀", String(repeating: "a", count: 33)])
    func rejects(raw: String) {
        #expect(TagName.normalize(raw) == nil)
    }

    @Test func keepsThirtyTwoCharacters() {
        let name = String(repeating: "a", count: 32)
        #expect(TagName.normalize(name) == name)
    }

    @Test func folderIDEncodesAsPlainString() throws {
        let id = FolderID(rawValue: "abc")
        let data = try JSONEncoder().encode(["id": id])
        #expect(String(decoding: data, as: UTF8.self) == #"{"id":"abc"}"#)
        let fresh = FolderID.new()
        #expect(fresh.rawValue == fresh.rawValue.lowercased())
        #expect(fresh != FolderID.new())
    }

    @Test func addTagNormalizesDedupesAndKeepsOrder() {
        var labels = ItemLabels()
        #expect(labels.addTag("#Sprint") == .added)
        #expect(labels.addTag("decision") == .added)
        #expect(labels.addTag("SPRINT") == .duplicate)
        #expect(labels.addTag("###") == .invalid)
        #expect(labels.tags == ["sprint", "decision"])
        labels.removeTag("sprint")
        #expect(labels.tags == ["decision"])
    }

    @Test func eleventhTagIsRefused() {
        var labels = ItemLabels()
        for index in 0..<10 { #expect(labels.addTag("t\(index)") == .added) }
        #expect(labels.addTag("extra") == .full)
        #expect(labels.tags.count == 10)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter LibraryLabelsTests`
Expected: compile error "cannot find 'TagName' in scope".

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Stable id of a folder in `library.json`. Survives folder renames.
public struct FolderID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func new() -> FolderID {
        FolderID(rawValue: UUID().uuidString.lowercased())
    }

    public var description: String { rawValue }
}

/// Tag names are stored lowercase, without `#`. Letters of any script,
/// digits, `-`, `_` and `/` are kept; spaces become `-`.
public enum TagName {
    public static let maxLength = 32

    public static func normalize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("#") { text.removeFirst() }
        text = text
            .precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: "-")

        var kept = String.UnicodeScalarView()
        var previousWasLetter = false
        for scalar in text.unicodeScalars {
            let isLetter = scalar.properties.isAlphabetic
            let isDigit = scalar.properties.numericType == .decimal
            let isPunctuation = scalar == "-" || scalar == "_" || scalar == "/"
            let isMark = scalar.properties.generalCategory == .nonspacingMark
            if isLetter || isDigit || isPunctuation || (isMark && previousWasLetter) {
                kept.append(scalar)
                previousWasLetter = isLetter || (isMark && previousWasLetter)
            } else {
                previousWasLetter = false
            }
        }
        let result = String(kept)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_/"))
            .precomposedStringWithCanonicalMapping
        guard !result.isEmpty, result.count <= maxLength else { return nil }
        return result
    }
}

/// The folder and tags one note or meeting carries.
public struct ItemLabels: Codable, Equatable, Sendable {
    public static let maxTags = 10

    public enum AddResult: Equatable, Sendable {
        case added, duplicate, invalid, full
    }

    public var folderID: FolderID?
    public var tags: [String]

    public init(folderID: FolderID? = nil, tags: [String] = []) {
        self.folderID = folderID
        self.tags = tags
    }

    @discardableResult
    public mutating func addTag(_ raw: String) -> AddResult {
        guard let tag = TagName.normalize(raw) else { return .invalid }
        guard !tags.contains(tag) else { return .duplicate }
        guard tags.count < Self.maxTags else { return .full }
        tags.append(tag)
        return .added
    }

    public mutating func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter LibraryLabelsTests`
Expected: all pass. If `"ship🚀it"` keeps a variation selector, the `previousWasLetter` rule is wrong: fix the loop, not the test.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceCore/LibraryLabels.swift Tests/VoiceCoreTests/LibraryLabelsTests.swift
git commit -m "feat(core): add folder ids, tag names and item labels

Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 2: Library file, folder operations and store

**Files:**
- Create: `Sources/VoiceCore/Library.swift`
- Modify: `Sources/VoiceCore/AppPaths.swift` (add `library` after `insights`)
- Test: `Tests/VoiceCoreTests/LibraryTests.swift`

**Interfaces:**
- Consumes: `FolderID` (Task 1).
- Produces: `LibraryFolder { id, name, createdAt }`; `LibraryFile { version, folders, lastUploadFolderID; static currentVersion = 1 }`; `LibraryFolderError` (LocalizedError); `LibraryFolders.create(_:in:now:) throws -> LibraryFolder`, `.rename(_:to:in:) throws`, `.delete(_:in:)`, `.sorted(_:) -> [LibraryFolder]`, `.maxNameLength = 40`; `LibraryLoadResult { loaded(LibraryFile), missing, reset(backupName: String), newer(LibraryFile) }`; `actor LibraryStore(url:now:)` with `load() -> LibraryLoadResult`, `save(_:) throws`; `AppPaths.library: URL`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import VoiceCore

struct LibraryTests {
    @Test func createTrimsAndSortsByName() throws {
        var file = LibraryFile()
        _ = try LibraryFolders.create("  Project A ", in: &file)
        _ = try LibraryFolders.create("IT team", in: &file)
        _ = try LibraryFolders.create("finance / client", in: &file)
        #expect(LibraryFolders.sorted(file.folders).map(\.name) == ["finance / client", "IT team", "Project A"])
    }

    @Test func duplicateIgnoresCaseAndDiacritics() throws {
        var file = LibraryFile()
        _ = try LibraryFolders.create("Họp nhóm", in: &file)
        #expect(throws: LibraryFolderError.duplicate) { try LibraryFolders.create("hop NHOM", in: &file) }
    }

    @Test func rejectsEmptyLongAndReservedNames() {
        var file = LibraryFile()
        #expect(throws: LibraryFolderError.empty) { try LibraryFolders.create("   ", in: &file) }
        #expect(throws: LibraryFolderError.tooLong) { try LibraryFolders.create(String(repeating: "a", count: 41), in: &file) }
        #expect(throws: LibraryFolderError.reserved) { try LibraryFolders.create("unfiled", in: &file) }
        #expect(throws: LibraryFolderError.reserved) { try LibraryFolders.create("ALL", in: &file) }
    }

    @Test func renameKeepsIDAndAllowsSameNameDifferentCase() throws {
        var file = LibraryFile()
        let folder = try LibraryFolders.create("project a", in: &file)
        try LibraryFolders.rename(folder.id, to: "Project A", in: &file)
        #expect(file.folders == [LibraryFolder(id: folder.id, name: "Project A", createdAt: folder.createdAt)])
        let other = try LibraryFolders.create("Other", in: &file)
        #expect(throws: LibraryFolderError.duplicate) { try LibraryFolders.rename(other.id, to: "PROJECT A", in: &file) }
        #expect(throws: LibraryFolderError.missing) { try LibraryFolders.rename(FolderID(rawValue: "gone"), to: "X", in: &file) }
    }

    @Test func deleteClearsUploadDefault() throws {
        var file = LibraryFile()
        let folder = try LibraryFolders.create("Personal", in: &file)
        file.lastUploadFolderID = folder.id
        LibraryFolders.delete(folder.id, in: &file)
        #expect(file.folders.isEmpty)
        #expect(file.lastUploadFolderID == nil)
    }

    @Test func storeRoundTripsAndReportsMissing() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(url: directory.appendingPathComponent("library.json"))
        #expect(await store.load() == .missing)
        var file = LibraryFile()
        _ = try LibraryFolders.create("IT team", in: &file, now: Date(timeIntervalSince1970: 0))
        try await store.save(file)
        #expect(await store.load() == .loaded(file))
    }

    @Test func corruptFileIsBackedUpAndReset() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.json")
        try Data("{not json".utf8).write(to: url)
        let store = LibraryStore(url: url, now: { Date(timeIntervalSince1970: 0) })
        guard case .reset(let backupName) = await store.load() else {
            Issue.record("expected reset")
            return
        }
        #expect(backupName.hasPrefix("library.corrupt-"))
        #expect(backupName.hasSuffix(".json"))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(backupName).path))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func newerVersionIsReadOnly() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.json")
        try Data(#"{"version":2,"folders":[{"id":"a","name":"Kept","createdAt":"2026-10-15T00:00:00Z"}],"shape":"new"}"#.utf8).write(to: url)
        let result = await LibraryStore(url: url).load()
        guard case .newer(let file) = result else {
            Issue.record("expected newer")
            return
        }
        #expect(file.folders.map(\.name) == ["Kept"])
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter LibraryTests`
Expected: compile error "cannot find 'LibraryFile' in scope".

- [ ] **Step 3: Implement**

`Sources/VoiceCore/Library.swift`:

```swift
import Foundation

public struct LibraryFolder: Codable, Equatable, Sendable, Identifiable {
    public let id: FolderID
    public var name: String
    public let createdAt: Date

    public init(id: FolderID, name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// `library.json`: the folder list. Notes and meetings store their own labels.
public struct LibraryFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var folders: [LibraryFolder]
    public var lastUploadFolderID: FolderID?

    public init(version: Int = LibraryFile.currentVersion, folders: [LibraryFolder] = [], lastUploadFolderID: FolderID? = nil) {
        self.version = version
        self.folders = folders
        self.lastUploadFolderID = lastUploadFolderID
    }

    public func folder(_ id: FolderID?) -> LibraryFolder? {
        guard let id else { return nil }
        return folders.first { $0.id == id }
    }

    public var knownIDs: Set<FolderID> { Set(folders.map(\.id)) }
}

public enum LibraryFolderError: Error, Equatable, Sendable, LocalizedError {
    case empty, tooLong, duplicate, reserved, missing, readOnly

    public var errorDescription: String? {
        switch self {
        case .empty: "Enter a folder name."
        case .tooLong: "Folder names can be up to 40 characters."
        case .duplicate: "A folder with this name already exists."
        case .reserved: "This name is reserved."
        case .missing: "This folder no longer exists."
        case .readOnly: "Folders were saved by a newer BugVoice. Folder changes are turned off."
        }
    }
}

public enum LibraryFolders {
    public static let maxNameLength = 40
    static let reservedKeys: Set<String> = ["unfiled", "all"]

    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "đ", with: "d")
    }

    static func validate(_ name: String, in file: LibraryFile, excluding: FolderID?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryFolderError.empty }
        guard trimmed.count <= maxNameLength else { throw LibraryFolderError.tooLong }
        let candidate = key(trimmed)
        guard !reservedKeys.contains(candidate) else { throw LibraryFolderError.reserved }
        guard !file.folders.contains(where: { $0.id != excluding && key($0.name) == candidate }) else {
            throw LibraryFolderError.duplicate
        }
        return trimmed
    }

    @discardableResult
    public static func create(_ name: String, in file: inout LibraryFile, now: Date = Date()) throws -> LibraryFolder {
        let trimmed = try validate(name, in: file, excluding: nil)
        let folder = LibraryFolder(id: .new(), name: trimmed, createdAt: now)
        file.folders.append(folder)
        return folder
    }

    public static func rename(_ id: FolderID, to name: String, in file: inout LibraryFile) throws {
        guard let index = file.folders.firstIndex(where: { $0.id == id }) else { throw LibraryFolderError.missing }
        file.folders[index].name = try validate(name, in: file, excluding: id)
    }

    /// Removes the folder only. Items keeping its id show as Unfiled.
    public static func delete(_ id: FolderID, in file: inout LibraryFile) {
        file.folders.removeAll { $0.id == id }
        if file.lastUploadFolderID == id { file.lastUploadFolderID = nil }
    }

    public static func sorted(_ folders: [LibraryFolder]) -> [LibraryFolder] {
        folders.sorted {
            let left = key($0.name), right = key($1.name)
            return left == right ? $0.id.rawValue < $1.id.rawValue : left < right
        }
    }
}

public enum LibraryLoadResult: Equatable, Sendable {
    case loaded(LibraryFile)
    case missing
    /// The file could not be read; it was renamed to `backupName` in the same folder.
    case reset(backupName: String)
    /// Written by a newer BugVoice: show what can be read, never write.
    case newer(LibraryFile)
}

public actor LibraryStore {
    private let url: URL
    private let now: @Sendable () -> Date

    public init(url: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.url = url
        self.now = now
    }

    public func load() -> LibraryLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url) else { return backup() }
        if let header = try? decoder.decode(VersionHeader.self, from: data), header.version > LibraryFile.currentVersion {
            let folders = (try? decoder.decode(FoldersOnly.self, from: data))?.folders ?? []
            return .newer(LibraryFile(version: header.version, folders: folders))
        }
        guard let file = try? decoder.decode(LibraryFile.self, from: data) else { return backup() }
        return .loaded(file)
    }

    public func save(_ file: LibraryFile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    private func backup() -> LibraryLoadResult {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        var name = "library.corrupt-\(formatter.string(from: now())).json"
        var destination = url.deletingLastPathComponent().appendingPathComponent(name)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            name = "library.corrupt-\(formatter.string(from: now()))-\(suffix).json"
            destination = url.deletingLastPathComponent().appendingPathComponent(name)
            suffix += 1
        }
        try? FileManager.default.moveItem(at: url, to: destination)
        return .reset(backupName: name)
    }

    private struct VersionHeader: Decodable { let version: Int }
    private struct FoldersOnly: Decodable { let folders: [LibraryFolder] }
}
```

In `Sources/VoiceCore/AppPaths.swift`, after the `insights` line add:

```swift
    /// Folder list for Notes, Meetings and Upload. Items store their own labels.
    public var library: URL { root.appendingPathComponent("library.json") }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter LibraryTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceCore/Library.swift Sources/VoiceCore/AppPaths.swift Tests/VoiceCoreTests/LibraryTests.swift
git commit -m "feat(core): store folders in library.json

Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 3: Note front matter

**Files:**
- Modify: `Sources/VoiceCore/NotesDocument.swift`
- Modify: `Sources/VoiceCore/Notes.swift` (`NoteDocument`, `NotesListItem`)
- Modify: `Sources/VoiceCore/NotesListProjection.swift`
- Test: `Tests/VoiceCoreTests/NotesFrontMatterTests.swift`

**Interfaces:**
- Consumes: `FolderID`, `TagName`, `ItemLabels.maxTags` (Task 1).
- Produces: `NoteFrontMatter { folderID: FolderID?; tags: [String]; extra: [String]; var isEmpty: Bool; var labels: ItemLabels }`; `NotesMarkdownParseResult.frontMatter`; `NotesMarkdownDocument.serialize(title:body:frontMatter:) -> Data` (the old `serialize(title:body:)` stays and writes no front matter); `NoteDocument.frontMatter: NoteFrontMatter` (init parameter `frontMatter: NoteFrontMatter = NoteFrontMatter()` added last); `NotesListItem.tags: [String]` (init parameter `tags: [String] = []` added last).

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import VoiceCore

struct NotesFrontMatterTests {
    @Test func fileWithoutFrontMatterIsUnchanged() throws {
        let data = Data("# Ideas\n\nbody".utf8)
        let parsed = try NotesMarkdownDocument.parse(data: data, filename: "ideas.md")
        #expect(parsed.frontMatter == NoteFrontMatter())
        #expect(parsed.body == "body")
        #expect(!parsed.needsNormalization)
        #expect(NotesMarkdownDocument.serialize(title: "Ideas", body: "body", frontMatter: NoteFrontMatter()) == data)
    }

    @Test func folderAndTagsRoundTrip() throws {
        let front = NoteFrontMatter(folderID: FolderID(rawValue: "f1"), tags: ["decision", "họp"])
        let data = NotesMarkdownDocument.serialize(title: "Sprint", body: "Body\n", frontMatter: front)
        #expect(String(decoding: data, as: UTF8.self) == "---\nfolder: f1\ntags: [decision, họp]\n---\n# Sprint\n\nBody\n")
        let parsed = try NotesMarkdownDocument.parse(data: data, filename: "sprint.md")
        #expect(parsed.frontMatter == front)
        #expect(parsed.title == "Sprint")
        #expect(parsed.body == "Body\n")
        #expect(!parsed.needsNormalization)
    }

    @Test func otherAppsKeysArePreservedInOrder() throws {
        let source = "---\naliases: [VPN]\nfolder: f1\ncreated: 2026-10-01\ntags: [\"vpn\", 'Idea']\n---\n# VPN\n\nText"
        let parsed = try NotesMarkdownDocument.parse(data: Data(source.utf8), filename: "vpn.md")
        #expect(parsed.frontMatter.folderID == FolderID(rawValue: "f1"))
        #expect(parsed.frontMatter.tags == ["vpn", "idea"])
        #expect(parsed.frontMatter.extra == ["aliases: [VPN]", "created: 2026-10-01"])
        let written = NotesMarkdownDocument.serialize(title: parsed.title, body: parsed.body, frontMatter: parsed.frontMatter)
        #expect(String(decoding: written, as: UTF8.self) == "---\nfolder: f1\ntags: [vpn, idea]\naliases: [VPN]\ncreated: 2026-10-01\n---\n# VPN\n\nText")
    }

    @Test func crlfFrontMatterIsAccepted() throws {
        let source = "---\r\nfolder: f1\r\ntags: [a]\r\n---\r\n# T\r\n\r\nB"
        let parsed = try NotesMarkdownDocument.parse(data: Data(source.utf8), filename: "t.md")
        #expect(parsed.frontMatter == NoteFrontMatter(folderID: FolderID(rawValue: "f1"), tags: ["a"]))
        #expect(parsed.title == "T")
        #expect(parsed.needsNormalization)
    }

    @Test func unclosedFrontMatterIsBody() throws {
        let source = "---\nfolder: f1\nno closing line"
        let parsed = try NotesMarkdownDocument.parse(data: Data(source.utf8), filename: "loose.md")
        #expect(parsed.frontMatter == NoteFrontMatter())
        #expect(parsed.title == "loose")
        #expect(parsed.body == source)
    }

    @Test func malformedTagsLineIsKeptAsExtra() throws {
        let source = "---\ntags: decision\n---\n# T\n\nB"
        let parsed = try NotesMarkdownDocument.parse(data: Data(source.utf8), filename: "t.md")
        #expect(parsed.frontMatter.tags.isEmpty)
        #expect(parsed.frontMatter.extra == ["tags: decision"])
    }

    @Test func removingLabelsRemovesFrontMatter() throws {
        let data = NotesMarkdownDocument.serialize(title: "T", body: "B", frontMatter: NoteFrontMatter())
        #expect(String(decoding: data, as: UTF8.self) == "# T\n\nB")
    }

    @Test func searchMatchesTags() {
        let item = NotesListItem(id: NoteID(rawValue: "a"), title: "Plan", body: "text", modifiedAt: .now, tags: ["acme"])
        #expect(NotesListProjection.filter([item], query: "#acme").count == 1)
        #expect(NotesListProjection.filter([item], query: "acme").count == 1)
        #expect(NotesListProjection.filter([item], query: "zzz").isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter NotesFrontMatterTests`
Expected: compile error "cannot find 'NoteFrontMatter' in scope".

- [ ] **Step 3: Implement**

In `Sources/VoiceCore/NotesDocument.swift`, add above `NotesMarkdownParseResult`:

```swift
/// BugVoice's keys at the top of a note file. Lines from other apps are kept
/// verbatim in `extra` and written back after BugVoice's keys.
public struct NoteFrontMatter: Equatable, Sendable {
    public var folderID: FolderID?
    public var tags: [String]
    public var extra: [String]

    public init(folderID: FolderID? = nil, tags: [String] = [], extra: [String] = []) {
        self.folderID = folderID
        self.tags = tags
        self.extra = extra
    }

    public var isEmpty: Bool { folderID == nil && tags.isEmpty && extra.isEmpty }
    public var labels: ItemLabels { ItemLabels(folderID: folderID, tags: tags) }
}
```

Replace `NotesMarkdownParseResult` with:

```swift
public struct NotesMarkdownParseResult: Sendable, Equatable {
    public let title: String
    public let body: String
    public let frontMatter: NoteFrontMatter
    public let needsNormalization: Bool

    public init(title: String, body: String, frontMatter: NoteFrontMatter = NoteFrontMatter(), needsNormalization: Bool) {
        self.title = title
        self.body = body
        self.frontMatter = frontMatter
        self.needsNormalization = needsNormalization
    }
}
```

Replace `parse(data:filename:)` and `serialize(title:body:)` in `NotesMarkdownDocument` with:

```swift
    public static func parse(data: Data, filename: String) throws -> NotesMarkdownParseResult {
        guard let original = String(data: data, encoding: .utf8) else {
            throw NotesDocumentError.invalidUTF8
        }
        let (frontMatter, source) = splitFrontMatter(original) ?? (NoteFrontMatter(), original)

        if let parsed = parseHeading(source) {
            let canonical = serialize(title: parsed.title, body: parsed.body, frontMatter: frontMatter)
            return NotesMarkdownParseResult(
                title: parsed.title,
                body: parsed.body,
                frontMatter: frontMatter,
                needsNormalization: canonical != data
            )
        }

        return NotesMarkdownParseResult(
            title: title(from: filename),
            body: source,
            frontMatter: frontMatter,
            needsNormalization: true
        )
    }

    /// Writes no front matter; used for export and copy.
    public static func serialize(title: String, body: String) -> Data {
        serialize(title: title, body: body, frontMatter: NoteFrontMatter())
    }

    public static func serialize(title: String, body: String, frontMatter: NoteFrontMatter) -> Data {
        var text = ""
        if !frontMatter.isEmpty {
            text += "---\n"
            if let folderID = frontMatter.folderID { text += "folder: \(folderID.rawValue)\n" }
            if !frontMatter.tags.isEmpty { text += "tags: [\(frontMatter.tags.joined(separator: ", "))]\n" }
            for line in frontMatter.extra { text += line + "\n" }
            text += "---\n"
        }
        text += "# \(title)\n\n\(body)"
        return Data(text.utf8)
    }

    /// Returns nil when the file does not start with a closed `---` block.
    private static func splitFrontMatter(_ source: String) -> (NoteFrontMatter, String)? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, stripCR(first) == "---", lines.count > 1 else { return nil }
        guard let close = lines.indices.dropFirst().first(where: { stripCR(lines[$0]) == "---" }) else { return nil }

        var front = NoteFrontMatter()
        for raw in lines[1..<close] {
            let line = stripCR(raw)
            if line.hasPrefix("folder:") {
                let value = unquote(String(line.dropFirst("folder:".count)))
                front.folderID = value.isEmpty ? nil : FolderID(rawValue: value)
            } else if line.hasPrefix("tags:"), let tags = parseTagList(String(line.dropFirst("tags:".count))) {
                front.tags = tags
            } else {
                front.extra.append(line)
            }
        }
        let remainder = lines[(close + 1)...].joined(separator: "\n")
        return (front, remainder)
    }

    private static func parseTagList(_ raw: String) -> [String]? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("["), value.hasSuffix("]") else { return nil }
        var tags: [String] = []
        for part in value.dropFirst().dropLast().split(separator: ",") {
            guard let tag = TagName.normalize(unquote(String(part))), !tags.contains(tag) else { continue }
            if tags.count < ItemLabels.maxTags { tags.append(tag) }
        }
        return tags
    }

    private static func unquote(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, let last = value.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func stripCR(_ line: String) -> String {
        line.hasSuffix("\r") ? String(line.dropLast()) : line
    }
```

Note: a CRLF file's heading/body is parsed by the existing `parseHeading`, which already strips `\r` from the heading and the CRLF after it; the body keeps its CRLFs (as today).

In `Sources/VoiceCore/Notes.swift`:

- `NotesListItem`: add `public let tags: [String]` and extend the init to `public init(id: NoteID, title: String, body: String, modifiedAt: Date, tags: [String] = [])` assigning `self.tags = tags`.
- `NoteDocument`: add `public var frontMatter: NoteFrontMatter`; add the init parameter `frontMatter: NoteFrontMatter = NoteFrontMatter()` after `slug: String? = nil`, assigning `self.frontMatter = frontMatter`.

In `Sources/VoiceCore/NotesListProjection.swift`, change the filter condition to:

```swift
        return sorted.filter { item in
            normalize(item.title).contains(normalizedQuery)
                || normalize(item.body).contains(normalizedQuery)
                || LibraryTagSearch.matches(item.tags, query: query)
        }
```

and add at the end of the file (Task 6 reuses it for meetings):

```swift
/// Search text `acme` or `#acme` matches an item tagged `acme`.
public enum LibraryTagSearch {
    public static func matches(_ tags: [String], query: String) -> Bool {
        guard let needle = TagName.normalize(query) else { return false }
        return tags.contains { $0.contains(needle) }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter NotesFrontMatterTests` then `swift test`
Expected: all pass (existing Notes document tests unchanged).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceCore/NotesDocument.swift Sources/VoiceCore/Notes.swift Sources/VoiceCore/NotesListProjection.swift Tests/VoiceCoreTests/NotesFrontMatterTests.swift
git commit -m "feat(core): keep note folder and tags in front matter

Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 4: Notes store and controller write labels

**Files:**
- Modify: `Sources/BugVoiceMac/NotesStore.swift`
- Modify: `Sources/BugVoiceMac/NotesController.swift`
- Test: `Tests/BugVoiceMacTests/NotesControllerTests.swift`

**Interfaces:**
- Consumes: `NoteFrontMatter`, `NoteDocument.frontMatter`, `serialize(title:body:frontMatter:)` (Task 3).
- Produces: `NotesStore.create(title:body:frontMatter:)`; `NotesController.create(title: String = "Untitled", frontMatter: NoteFrontMatter = NoteFrontMatter()) async throws -> NoteDocument`; `NotesController.setLabels(id: NoteID, folderID: FolderID?, tags: [String]) async throws`.

- [ ] **Step 1: Write the failing tests** (append inside `struct NotesControllerTests`, before its private helpers)

```swift
    @Test func labelsAreWrittenAsFrontMatterAndSurviveRename() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Plan", body: "body")
        let controller = NotesController(store: store)

        try await controller.setLabels(id: created.id, folderID: FolderID(rawValue: "f1"), tags: ["acme"])
        await controller.flush(id: created.id)
        let text = try String(contentsOf: root.appendingPathComponent("plan.md"), encoding: .utf8)
        #expect(text == "---\nfolder: f1\ntags: [acme]\n---\n# Plan\n\nbody")

        let note = try #require(controller.note(id: created.id))
        _ = try await store.rename(id: created.id, title: "Plan B", revision: note.revision, expectedVersion: note.fileVersion)
        let renamed = try String(contentsOf: root.appendingPathComponent("plan-b.md"), encoding: .utf8)
        #expect(renamed.hasPrefix("---\nfolder: f1\ntags: [acme]\n---\n# Plan B"))
    }

    @Test func labelChangeKeepsUnsavedTyping() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Typing", body: "start")
        let controller = NotesController(store: store)
        try await controller.load(id: created.id)

        controller.updateBody(id: created.id, body: "start and more")
        try await controller.setLabels(id: created.id, folderID: nil, tags: ["todo"])
        await controller.flush(id: created.id)

        let persisted = try await store.open(id: created.id)
        #expect(persisted.body == "start and more")
        #expect(persisted.frontMatter.tags == ["todo"])
    }

    @Test func createPutsNoteInFolder() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = NotesController(store: NotesStore(directory: root))
        let note = try await controller.create(frontMatter: NoteFrontMatter(folderID: FolderID(rawValue: "f9")))
        let persisted = try await NotesStore(directory: root).list()
        #expect(persisted.first?.frontMatter.folderID == FolderID(rawValue: "f9"))
        #expect(note.frontMatter.folderID == FolderID(rawValue: "f9"))
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter NotesControllerTests`
Expected: compile error "value of type 'NotesController' has no member 'setLabels'".

- [ ] **Step 3: Implement**

`Sources/BugVoiceMac/NotesStore.swift`:

- `create`: change the signature to `public func create(title: String, body: String = "", frontMatter: NoteFrontMatter = NoteFrontMatter()) throws -> NoteDocument`; build data with `NotesMarkdownDocument.serialize(title: title, body: body, frontMatter: frontMatter)`; return `NoteDocument(id: id, title: title, body: body, modifiedAt: version.modifiedAt, fileVersion: version, slug: slug, frontMatter: frontMatter)`.
- `save`: replace `NotesMarkdownDocument.serialize(title: note.title, body: note.body)` with `NotesMarkdownDocument.serialize(title: note.title, body: note.body, frontMatter: note.frontMatter)`.
- `rename`: replace `NotesMarkdownDocument.serialize(title: title, body: previous.body)` with `NotesMarkdownDocument.serialize(title: title, body: previous.body, frontMatter: previous.frontMatter)`.
- `read`: add `frontMatter: parsed.frontMatter` as the last `NoteDocument` argument.

`Sources/BugVoiceMac/NotesController.swift`:

Replace `create(title:)` with:

```swift
    @discardableResult
    public func create(title: String = "Untitled", frontMatter: NoteFrontMatter = NoteFrontMatter()) async throws -> NoteDocument {
        if let selectedNoteID {
            guard await flush(id: selectedNoteID) else { throw NotesControllerError.saveFailed(selectedNoteID) }
        }
        let note = try await store.create(title: title, frontMatter: frontMatter)
        loaded[note.id] = LoadedNote(note: note)
        selectedNoteID = note.id
        await reloadList()
        changed()
        return note
    }
```

Add after `updateBody(id:body:)`:

```swift
    /// Changes a note's folder and tags. Loads the note if needed; the change
    /// rides the same autosave as body edits, so unsaved typing is kept.
    public func setLabels(id: NoteID, folderID: FolderID?, tags: [String]) async throws {
        try await load(id: id)
        guard let state = loaded[id] else { return }
        guard state.note.frontMatter.folderID != folderID || state.note.frontMatter.tags != tags else { return }
        state.note.frontMatter.folderID = folderID
        state.note.frontMatter.tags = tags
        state.note.revision &+= 1
        state.isDirty = true
        state.saveError = nil
        updateListRow(state.note)
        scheduleSave(id: id)
        changed()
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter NotesControllerTests` then `swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BugVoiceMac/NotesStore.swift Sources/BugVoiceMac/NotesController.swift Tests/BugVoiceMacTests/NotesControllerTests.swift
git commit -m "feat(core): save note folder and tags through the notes controller

Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 5: Meeting manifest labels and session writes

**Files:**
- Modify: `Sources/VoiceCore/Meeting.swift` (`MeetingManifest`, `MeetingListProjection.matches`)
- Modify: `Sources/VoiceCore/MeetingSession.swift`
- Test: `Tests/VoiceCoreTests/MeetingLabelsTests.swift`, `Tests/VoiceCoreTests/MeetingSessionTests.swift`

**Interfaces:**
- Consumes: `FolderID`, `ItemLabels` (Task 1), `LibraryTagSearch` (Task 3).
- Produces: `MeetingManifest.folderID: FolderID?`, `.tags: [String]`, `.suggestedTags: [String]` (init parameters `folderID: FolderID? = nil, tags: [String] = [], suggestedTags: [String] = []` added last); `MeetingSession.start(labels: ItemLabels = ItemLabels())`; `MeetingSession.setLabels(folderID: FolderID?, tags: [String], suggestedTags: [String]?) async throws`.

- [ ] **Step 1: Write the failing tests**

`Tests/VoiceCoreTests/MeetingLabelsTests.swift`:

```swift
import Foundation
import Testing
@testable import VoiceCore

struct MeetingLabelsTests {
    @Test func oldManifestDecodesWithoutLabels() throws {
        let json = """
        {"schemaVersion":1,"id":"m1","title":"T","startedAt":"2026-10-15T00:00:00Z","duration":0,
         "state":"ready","audioFormat":{"sampleRate":16000,"channels":1,"journalEncoding":"pcm16","finalEncoding":"aac"},
         "chunks":[],"marks":[],"segments":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meeting = try decoder.decode(MeetingManifest.self, from: Data(json.utf8))
        #expect(meeting.folderID == nil)
        #expect(meeting.tags.isEmpty)
        #expect(meeting.suggestedTags.isEmpty)
    }

    @Test func labelsRoundTrip() throws {
        var meeting = MeetingManifest(startedAt: Date(timeIntervalSince1970: 0))
        meeting.folderID = FolderID(rawValue: "f1")
        meeting.tags = ["acme"]
        meeting.suggestedTags = ["todo"]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeetingManifest.self, from: encoder.encode(meeting))
        #expect(decoded == meeting)
    }

    @Test func searchMatchesTags() {
        var meeting = MeetingManifest(startedAt: Date())
        meeting.tags = ["acme"]
        #expect(MeetingListProjection.matches(meeting, query: "#acme"))
        #expect(!MeetingListProjection.matches(meeting, query: "#zzz"))
    }
}
```

If the `audioFormat` JSON keys above do not match `MeetingAudioFormat`'s Codable keys, build the JSON by encoding `MeetingManifest(startedAt:)` with `JSONEncoder`, removing the `folderID`, `tags` and `suggestedTags` keys with `JSONSerialization`, and decoding that instead; the point of the test is an old file without the three keys.

Append to `struct MeetingSessionTests` in `Tests/VoiceCoreTests/MeetingSessionTests.swift`:

```swift
    @Test func labelsSetDuringRecordingSurviveStop() async throws {
        let rig = SessionRig()
        let session = rig.makeSession()
        let started = try await session.start(labels: ItemLabels(folderID: FolderID(rawValue: "f1")))
        #expect(started.folderID == FolderID(rawValue: "f1"))
        try await session.setLabels(folderID: FolderID(rawValue: "f2"), tags: ["acme"], suggestedTags: nil)
        let stopped = try await session.stop()
        #expect(stopped.folderID == FolderID(rawValue: "f2"))
        #expect(stopped.tags == ["acme"])
        let saved = await rig.store.meetings[stopped.id]
        #expect(saved?.tags == ["acme"])
    }
```

(`SessionRig`, `rig.store.meetings` and `session.stop()` already exist in that file. If `stop()` in `SessionRig` needs a scheduler result first, copy the setup of the existing test that calls `session.stop()` near line 43.)

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter "MeetingLabelsTests|MeetingSessionTests"`
Expected: compile error "value of type 'MeetingManifest' has no member 'folderID'".

- [ ] **Step 3: Implement**

`Sources/VoiceCore/Meeting.swift`, in `MeetingManifest`:

1. After `public var importedAt: Date?` add:

```swift
    /// Folder from `library.json`; nil or an unknown id means Unfiled.
    public var folderID: FolderID?
    public var tags: [String]
    /// Existing tags the Meetings model proposed after the last summary. Shown until clicked or dismissed.
    public var suggestedTags: [String]
```

2. Add init parameters after `importedAt: Date? = nil`: `folderID: FolderID? = nil, tags: [String] = [], suggestedTags: [String] = []`, and assign them at the end of the init body.
3. `CodingKeys`: append `folderID, tags, suggestedTags` to the last `case` line.
4. In `init(from:)` add at the end:

```swift
        folderID = try c.decodeIfPresent(FolderID.self, forKey: .folderID)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        suggestedTags = try c.decodeIfPresent([String].self, forKey: .suggestedTags) ?? []
```

5. In `MeetingListProjection.matches(_:query:)`, return true also when `LibraryTagSearch.matches(meeting.tags, query: needle)`. Add it as the first check after the empty-needle guard:

```swift
        if LibraryTagSearch.matches(meeting.tags, query: needle) { return true }
```

`Sources/VoiceCore/MeetingSession.swift`:

Change `start()` to take labels:

```swift
    @discardableResult
    public func start(labels: ItemLabels = ItemLabels()) async throws -> MeetingManifest {
        guard manifest == nil else { throw MeetingSessionError.invalidState }
        let now = clock.now()
        var meeting = MeetingManifest(id: meetingID, startedAt: now, state: .recording)
        meeting.folderID = labels.folderID
        meeting.tags = labels.tags
        manifest = meeting
```

(the rest of `start` is unchanged.)

Add after `rename(title:)`:

```swift
    /// Folder and tag changes while this session owns the manifest. Pass nil
    /// `suggestedTags` to leave the suggestions as they are.
    public func setLabels(folderID: FolderID?, tags: [String], suggestedTags: [String]?) async throws {
        guard var meeting = manifest else { throw MeetingSessionError.invalidState }
        meeting.folderID = folderID
        meeting.tags = tags
        if let suggestedTags { meeting.suggestedTags = suggestedTags }
        manifest = meeting
        try await store.save(meeting)
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceCore/Meeting.swift Sources/VoiceCore/MeetingSession.swift Tests/VoiceCoreTests/MeetingLabelsTests.swift Tests/VoiceCoreTests/MeetingSessionTests.swift
git commit -m "feat(core): add folder and tags to meetings

Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 6: Filtering, counts and tag catalog

**Files:**
- Create: `Sources/VoiceCore/LibraryProjection.swift`
- Test: `Tests/VoiceCoreTests/LibraryProjectionTests.swift`

**Interfaces:**
- Consumes: `FolderID`, `MeetingManifest` labels, `NoteDocument.frontMatter`.
- Produces: `FolderFilter` (`.all`, `.unfiled`, `.folder(FolderID)`; `init(rawValue: String)`, `rawValue: String`, `resolved(known: Set<FolderID>) -> FolderFilter`, `newItemFolderID: FolderID?`); protocol `LibraryLabeled { var labelFolderID: FolderID? { get }; var labelTags: [String] { get } }` adopted by `MeetingManifest` and `NoteDocument`; `FolderCounts { all, unfiled, byFolder: [FolderID: Int]; func count(_ id: FolderID) -> Int }`; `TagCount { name, count }`; `LibraryProjection.matches(_:folder:tags:known:) -> Bool`, `.filter(_:folder:tags:known:) -> [T]`, `.counts(_:known:) -> FolderCounts`, `.catalog(_:) -> [TagCount]`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import VoiceCore

struct LibraryProjectionTests {
    struct Item: LibraryLabeled, Equatable {
        let name: String
        let labelFolderID: FolderID?
        let labelTags: [String]
    }

    let a = FolderID(rawValue: "a")
    let gone = FolderID(rawValue: "gone")

    var items: [Item] {
        [
            Item(name: "1", labelFolderID: a, labelTags: ["decision", "acme"]),
            Item(name: "2", labelFolderID: a, labelTags: ["decision"]),
            Item(name: "3", labelFolderID: nil, labelTags: ["acme"]),
            Item(name: "4", labelFolderID: gone, labelTags: []),
        ]
    }

    @Test func filtersByFolderTreatingUnknownAsUnfiled() {
        let known: Set<FolderID> = [a]
        #expect(LibraryProjection.filter(items, folder: .all, tags: [], known: known).map(\.name) == ["1", "2", "3", "4"])
        #expect(LibraryProjection.filter(items, folder: .folder(a), tags: [], known: known).map(\.name) == ["1", "2"])
        #expect(LibraryProjection.filter(items, folder: .unfiled, tags: [], known: known).map(\.name) == ["3", "4"])
    }

    @Test func tagChipsMustAllMatch() {
        let result = LibraryProjection.filter(items, folder: .all, tags: ["decision", "acme"], known: [a])
        #expect(result.map(\.name) == ["1"])
    }

    @Test func countsPerFolder() {
        let counts = LibraryProjection.counts(items, known: [a])
        #expect(counts.all == 4)
        #expect(counts.unfiled == 2)
        #expect(counts.count(a) == 2)
        #expect(counts.count(gone) == 0)
    }

    @Test func catalogSortsByUseThenName() {
        #expect(LibraryProjection.catalog(items) == [TagCount(name: "acme", count: 2), TagCount(name: "decision", count: 2)])
    }

    @Test func filterRawValuesRoundTrip() {
        #expect(FolderFilter(rawValue: "all") == .all)
        #expect(FolderFilter(rawValue: "unfiled") == .unfiled)
        #expect(FolderFilter(rawValue: "a") == .folder(a))
        #expect(FolderFilter.folder(a).rawValue == "a")
    }

    @Test func deletedFolderFilterFallsBackToAll() {
        #expect(FolderFilter.folder(gone).resolved(known: [a]) == .all)
        #expect(FolderFilter.folder(a).resolved(known: [a]) == .folder(a))
        #expect(FolderFilter.unfiled.resolved(known: []) == .unfiled)
    }

    @Test func newItemsGoIntoTheViewedFolder() {
        #expect(FolderFilter.folder(a).newItemFolderID == a)
        #expect(FolderFilter.all.newItemFolderID == nil)
        #expect(FolderFilter.unfiled.newItemFolderID == nil)
    }

    @Test func meetingsAndNotesAreLabeled() {
        var meeting = MeetingManifest(startedAt: Date())
        meeting.folderID = a
        meeting.tags = ["x"]
        #expect(meeting.labelFolderID == a)
        #expect(meeting.labelTags == ["x"])
        let note = NoteDocument(title: "T", body: "", frontMatter: NoteFrontMatter(folderID: a, tags: ["y"]))
        #expect(note.labelFolderID == a)
        #expect(note.labelTags == ["y"])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter LibraryProjectionTests`
Expected: compile error "cannot find type 'LibraryLabeled' in scope".

- [ ] **Step 3: Implement**

```swift
import Foundation

/// The folder menu choice on a page. Stored in settings as its raw value.
public enum FolderFilter: Hashable, Sendable {
    case all
    case unfiled
    case folder(FolderID)

    public init(rawValue: String) {
        switch rawValue {
        case "all", "": self = .all
        case "unfiled": self = .unfiled
        default: self = .folder(FolderID(rawValue: rawValue))
        }
    }

    public var rawValue: String {
        switch self {
        case .all: "all"
        case .unfiled: "unfiled"
        case .folder(let id): id.rawValue
        }
    }

    /// A filter naming a deleted folder shows everything.
    public func resolved(known: Set<FolderID>) -> FolderFilter {
        if case .folder(let id) = self, !known.contains(id) { return .all }
        return self
    }

    /// New notes and meetings go into the folder being viewed.
    public var newItemFolderID: FolderID? {
        if case .folder(let id) = self { return id }
        return nil
    }
}

public protocol LibraryLabeled {
    var labelFolderID: FolderID? { get }
    var labelTags: [String] { get }
}

extension MeetingManifest: LibraryLabeled {
    public var labelFolderID: FolderID? { folderID }
    public var labelTags: [String] { tags }
}

extension NoteDocument: LibraryLabeled {
    public var labelFolderID: FolderID? { frontMatter.folderID }
    public var labelTags: [String] { frontMatter.tags }
}

public struct FolderCounts: Equatable, Sendable {
    public var all = 0
    public var unfiled = 0
    public var byFolder: [FolderID: Int] = [:]

    public init() {}

    public func count(_ id: FolderID) -> Int { byFolder[id] ?? 0 }
}

public struct TagCount: Equatable, Sendable, Identifiable {
    public let name: String
    public let count: Int
    public var id: String { name }

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public enum LibraryProjection {
    /// An unknown folder id counts as Unfiled.
    static func effectiveFolder(_ id: FolderID?, known: Set<FolderID>) -> FolderID? {
        guard let id, known.contains(id) else { return nil }
        return id
    }

    public static func matches<T: LibraryLabeled>(_ item: T, folder: FolderFilter, tags: [String], known: Set<FolderID>) -> Bool {
        let effective = effectiveFolder(item.labelFolderID, known: known)
        switch folder {
        case .all: break
        case .unfiled: if effective != nil { return false }
        case .folder(let id): if effective != id { return false }
        }
        return tags.allSatisfy(item.labelTags.contains)
    }

    public static func filter<T: LibraryLabeled>(_ items: [T], folder: FolderFilter, tags: [String], known: Set<FolderID>) -> [T] {
        items.filter { matches($0, folder: folder, tags: tags, known: known) }
    }

    public static func counts<T: LibraryLabeled>(_ items: [T], known: Set<FolderID>) -> FolderCounts {
        var counts = FolderCounts()
        for item in items {
            counts.all += 1
            if let id = effectiveFolder(item.labelFolderID, known: known) {
                counts.byFolder[id, default: 0] += 1
            } else {
                counts.unfiled += 1
            }
        }
        return counts
    }

    public static func catalog<T: LibraryLabeled>(_ items: [T]) -> [TagCount] {
        var totals: [String: Int] = [:]
        for item in items {
            for tag in Set(item.labelTags) { totals[tag, default: 0] += 1 }
        }
        return totals.map { TagCount(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter LibraryProjectionTests` then `swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceCore/LibraryProjection.swift Tests/VoiceCoreTests/LibraryProjectionTests.swift
git commit -m "feat(core): filter and count notes and meetings by folder and tag

Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 7: Tag suggestion prompt and parser

**Files:**
- Create: `Sources/VoiceCore/TagSuggestion.swift`
- Test: `Tests/VoiceCoreTests/TagSuggestionTests.swift`

**Interfaces:**
- Consumes: `TagName` (Task 1), `CleanupRequest` (existing, `Sources/VoiceCore/TextModel.swift`).
- Produces: `TagSuggestion.request(summary: String, allowed: [String]) -> CleanupRequest`; `TagSuggestion.parse(_ answer: String, allowed: [String], existing: [String]) -> [String]`; constants `maxSuggestions = 3`, `maxAllowed = 200`, `system`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import VoiceCore

struct TagSuggestionTests {
    let allowed = ["decision", "todo", "acme", "sprint"]

    @Test func keepsAllowedTagsInOrderUpToThree() {
        let answer = "1. #todo\n- acme\n* Decision\nsprint"
        #expect(TagSuggestion.parse(answer, allowed: allowed, existing: []) == ["todo", "acme", "decision"])
    }

    @Test func dropsInventedExistingAndDuplicateTags() {
        let answer = "todo\nbudget\ntodo\nsprint"
        #expect(TagSuggestion.parse(answer, allowed: allowed, existing: ["sprint"]) == ["todo"])
    }

    @Test func noneAndThinkingGiveNothing() {
        #expect(TagSuggestion.parse("none", allowed: allowed, existing: []).isEmpty)
        #expect(TagSuggestion.parse("<think>maybe todo</think>\nNone.", allowed: allowed, existing: []).isEmpty)
    }

    @Test func proseLinesAreIgnored() {
        let answer = "Here are the tags that fit:\ntodo"
        #expect(TagSuggestion.parse(answer, allowed: allowed, existing: []) == ["todo"])
    }

    @Test func requestListsAllowedTagsAndSummary() {
        let request = TagSuggestion.request(summary: "We agreed on scope.", allowed: ["todo", "acme"])
        #expect(request.system == TagSuggestion.system)
        #expect(request.user == "Allowed tags:\ntodo\nacme\n\nSummary:\nWe agreed on scope.")
        #expect(request.maxTokens == 64)
        #expect(request.disableThinking)
    }

    @Test func requestCapsAllowedList() {
        let many = (0..<250).map { "t\($0)" }
        let request = TagSuggestion.request(summary: "S", allowed: many)
        #expect(request.user.components(separatedBy: "\n").filter { $0.hasPrefix("t") }.count == 200)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter TagSuggestionTests`
Expected: compile error "cannot find 'TagSuggestion' in scope".

- [ ] **Step 3: Implement**

```swift
import Foundation

/// After a meeting summary, the Meetings model may propose existing tags.
/// Nothing it says is added without the user's click.
public enum TagSuggestion {
    public static let maxSuggestions = 3
    public static let maxAllowed = 200
    public static let system = """
    You label meeting notes. From the allowed tags, pick at most 3 that fit the summary. \
    Answer with tag names only, one per line, or the word none. Never invent a tag.
    """

    /// `allowed` is the tag catalog, most-used first.
    public static func request(summary: String, allowed: [String]) -> CleanupRequest {
        let list = allowed.prefix(maxAllowed).joined(separator: "\n")
        return CleanupRequest(
            system: system,
            user: "Allowed tags:\n\(list)\n\nSummary:\n\(summary)",
            maxTokens: 64,
            temperature: 0,
            disableThinking: true
        )
    }

    public static func parse(_ answer: String, allowed: [String], existing: [String]) -> [String] {
        let withoutThinking = answer.replacingOccurrences(of: "(?s)<think>.*?</think>", with: "", options: .regularExpression)
        let allowedSet = Set(allowed)
        var result: [String] = []
        for rawLine in withoutThinking.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            line = line.replacingOccurrences(of: #"^(\d+[.)]|[-*•])\s*"#, with: "", options: .regularExpression)
            guard let tag = TagName.normalize(line),
                  allowedSet.contains(tag),
                  !existing.contains(tag),
                  !result.contains(tag) else { continue }
            result.append(tag)
            if result.count == maxSuggestions { break }
        }
        return result
    }
}
```

(`TagName.normalize("Here are the tags that fit:")` yields `here-are-the-tags-that-fit`, which is not in `allowed`, so prose is dropped. "None." normalizes to `none`, also not allowed.)

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter TagSuggestionTests`
Expected: all pass. If `CleanupRequest`'s init has no `temperature:` label, check `Sources/VoiceCore/TextModel.swift:12` and match its parameter order.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceCore/TagSuggestion.swift Tests/VoiceCoreTests/TagSuggestionTests.swift
git commit -m "feat(core): prompt and parse meeting tag suggestions

Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 8: Settings for page folder filters

**Files:**
- Modify: `Sources/VoiceCore/Settings.swift`
- Test: `Tests/VoiceCoreTests/LibrarySettingsTests.swift`

**Interfaces:**
- Produces: `LibrarySettings { meetingsFolderFilter: String = "all"; notesFolderFilter: String = "all" }`; `AppSettings.library: LibrarySettings`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import VoiceCore

struct LibrarySettingsTests {
    @Test func defaultsToAllAndToleratesMissingKeys() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.library.meetingsFolderFilter == "all")
        #expect(settings.library.notesFolderFilter == "all")
        let partial = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"library":{"notesFolderFilter":"f1"}}"#.utf8))
        #expect(partial.library.notesFolderFilter == "f1")
        #expect(partial.library.meetingsFolderFilter == "all")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter LibrarySettingsTests`
Expected: compile error "value of type 'AppSettings' has no member 'library'".

- [ ] **Step 3: Implement**

In `Sources/VoiceCore/Settings.swift`, add before `public struct AppSettings`:

```swift
/// Which folder each page shows. "all", "unfiled" or a folder id.
public struct LibrarySettings: Codable, Equatable, Sendable {
    public var meetingsFolderFilter = "all"
    public var notesFolderFilter = "all"

    public init() {}
}

extension LibrarySettings {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meetingsFolderFilter = c.value(.meetingsFolderFilter, default: meetingsFolderFilter)
        notesFolderFilter = c.value(.notesFolderFilter, default: notesFolderFilter)
    }
}
```

In `AppSettings`, after `public var styles = StyleSettings()` add `public var library = LibrarySettings()`. In `extension AppSettings`'s `init(from:)`, after `styles = c.value(.styles, default: styles)` add `library = c.value(.library, default: library)`.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceCore/Settings.swift Tests/VoiceCoreTests/LibrarySettingsTests.swift
git commit -m "feat(core): remember each page's folder filter

Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 9: AppModel library state, folder operations and label routing

**Files:**
- Modify: `Sources/BugVoice/AppModel.swift`
- Modify: `Sources/BugVoice/MeetingController.swift`
- Modify: `Sources/BugVoice/UploadController.swift`

**Interfaces:**
- Consumes: Tasks 1–8.
- Produces on `AppModel`:
  - `var library: LibraryFile`, `var libraryReadOnly: Bool`, `var meetingTagFilter: [String]`, `var notesTagFilter: [String]`
  - `var meetingsFolderFilter: FolderFilter { get set }`, `var notesFolderFilter: FolderFilter { get set }` (backed by `settings.library`, resolved against known folders)
  - `var sortedFolders: [LibraryFolder]`, `func folderName(_ id: FolderID?) -> String?`
  - `func createFolder(_ name: String) async -> Result<LibraryFolder, LibraryFolderError>`, `func renameFolder(_ id: FolderID, to name: String) async -> LibraryFolderError?`, `func deleteFolder(_ id: FolderID) async`
  - `var meetingTagCatalog: [TagCount]`, `var noteTagCatalog: [TagCount]`, `var allTagCatalog: [TagCount]`
  - `func setMeetingLabels(id: MeetingID, folderID: FolderID?, tags: [String], suggestedTags: [String]? = nil) async`
  - `func setNoteLabels(id: NoteID, folderID: FolderID?, tags: [String]) async`
  - `func setLastUploadFolder(_ id: FolderID?) async`
- Produces on controllers: `MeetingController.setLabelsInSession(id:folderID:tags:suggestedTags:) async throws -> Bool`, `UploadController.setLabelsInSession(id:folderID:tags:suggestedTags:) async throws -> Bool`.

No new tests: this task is app wiring over tested VoiceCore units; it must build and keep `swift test` green.

- [ ] **Step 1: Add state to `AppModel`**

After `var meetingSearchQuery = ""` add:

```swift
    /// Folders from `library.json`. Notes and meetings carry their own labels.
    var library = LibraryFile()
    /// True when `library.json` was written by a newer BugVoice: shown, never written.
    var libraryReadOnly = false
    var meetingTagFilter: [String] = []
    var notesTagFilter: [String] = []
```

After `@ObservationIgnored let dictionaryStore = …` add:

```swift
    @ObservationIgnored let libraryStore = LibraryStore(url: AppPaths.standard().library)
```

- [ ] **Step 2: Load the library at launch**

In `bootstrap()`, right after `await loadInsights()`, add `await loadLibrary()`. Add the method next to `loadInsights()`:

```swift
    private func loadLibrary() async {
        switch await libraryStore.load() {
        case .loaded(let file):
            library = file
        case .missing:
            library = LibraryFile()
        case .reset(let backupName):
            library = LibraryFile()
            saveError = "Folders file was damaged and has been reset. The old file was kept as \(backupName)."
        case .newer(let file):
            library = file
            libraryReadOnly = true
            saveError = LibraryFolderError.readOnly.errorDescription
        }
    }

    private func saveLibrary() async {
        guard !libraryReadOnly else { return }
        do {
            try await libraryStore.save(library)
        } catch {
            saveError = "Could not save folders: \(error.localizedDescription)"
        }
    }
```

- [ ] **Step 3: Filters, names and catalogs**

Add to `AppModel`:

```swift
    var sortedFolders: [LibraryFolder] { LibraryFolders.sorted(library.folders) }

    /// nil for Unfiled, including ids of deleted folders.
    func folderName(_ id: FolderID?) -> String? { library.folder(id)?.name }

    var meetingsFolderFilter: FolderFilter {
        get { FolderFilter(rawValue: settings.library.meetingsFolderFilter).resolved(known: library.knownIDs) }
        set { settings.library.meetingsFolderFilter = newValue.rawValue }
    }

    var notesFolderFilter: FolderFilter {
        get { FolderFilter(rawValue: settings.library.notesFolderFilter).resolved(known: library.knownIDs) }
        set { settings.library.notesFolderFilter = newValue.rawValue }
    }

    var meetingTagCatalog: [TagCount] { LibraryProjection.catalog(meetingManifests) }
    var noteTagCatalog: [TagCount] { LibraryProjection.catalog(notesController.notes) }
    var allTagCatalog: [TagCount] {
        var totals: [String: Int] = [:]
        for tag in meetingTagCatalog + noteTagCatalog { totals[tag.name, default: 0] += tag.count }
        return totals.map { TagCount(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }
```

- [ ] **Step 4: Folder operations**

```swift
    func createFolder(_ name: String) async -> Result<LibraryFolder, LibraryFolderError> {
        guard !libraryReadOnly else { return .failure(.readOnly) }
        do {
            let folder = try LibraryFolders.create(name, in: &library)
            await saveLibrary()
            return .success(folder)
        } catch let error as LibraryFolderError {
            return .failure(error)
        } catch {
            return .failure(.empty)
        }
    }

    func renameFolder(_ id: FolderID, to name: String) async -> LibraryFolderError? {
        guard !libraryReadOnly else { return .readOnly }
        do {
            try LibraryFolders.rename(id, to: name, in: &library)
            await saveLibrary()
            return nil
        } catch let error as LibraryFolderError {
            return error
        } catch {
            return .missing
        }
    }

    /// Removes the folder from `library.json` only; its items show as Unfiled.
    func deleteFolder(_ id: FolderID) async {
        guard !libraryReadOnly else { return }
        LibraryFolders.delete(id, in: &library)
        if case .folder(id) = FolderFilter(rawValue: settings.library.meetingsFolderFilter) { meetingsFolderFilter = .all }
        if case .folder(id) = FolderFilter(rawValue: settings.library.notesFolderFilter) { notesFolderFilter = .all }
        await saveLibrary()
    }

    func setLastUploadFolder(_ id: FolderID?) async {
        guard library.lastUploadFolderID != id else { return }
        library.lastUploadFolderID = id
        await saveLibrary()
    }
```

- [ ] **Step 5: Label routing**

Add to `MeetingController` after `renameSession`:

```swift
    func setLabelsInSession(id: MeetingID, folderID: FolderID?, tags: [String], suggestedTags: [String]?) async throws -> Bool {
        guard meetingID == id, let session else { return false }
        try await session.setLabels(folderID: folderID, tags: tags, suggestedTags: suggestedTags)
        return true
    }
```

Add to `UploadController` after `renameSession`:

```swift
    func setLabelsInSession(id: MeetingID, folderID: FolderID?, tags: [String], suggestedTags: [String]?) async throws -> Bool {
        guard activeDirectory?.lastPathComponent == id.rawValue, let session else { return false }
        try await session.setLabels(folderID: folderID, tags: tags, suggestedTags: suggestedTags)
        return true
    }
```

Add to `AppModel` after `renameMeeting`:

```swift
    /// Same routing as rename: a live recording or upload session owns its manifest.
    func setMeetingLabels(id: MeetingID, folderID: FolderID?, tags: [String], suggestedTags: [String]? = nil) async {
        let remainingSuggestions = suggestedTags
            ?? meetingManifests.first(where: { $0.id == id }).map { meeting in
                meeting.suggestedTags.filter { !tags.contains($0) }
            }
        do {
            if let uploads,
               try await uploads.setLabelsInSession(id: id, folderID: folderID, tags: tags, suggestedTags: remainingSuggestions) {
                await reloadMeetings()
                return
            }
            if let meetings,
               try await meetings.setLabelsInSession(id: id, folderID: folderID, tags: tags, suggestedTags: remainingSuggestions) {
                await reloadMeetings()
                return
            }
            var meeting = try await meetingStore.load(id: id)
            meeting.folderID = folderID
            meeting.tags = tags
            if let remainingSuggestions { meeting.suggestedTags = remainingSuggestions }
            try await meetingStore.save(meeting)
            await reloadMeetings()
        } catch {
            saveError = "Could not update meeting: \(error.localizedDescription)"
        }
    }

    func setNoteLabels(id: NoteID, folderID: FolderID?, tags: [String]) async {
        do {
            try await notesController.setLabels(id: id, folderID: folderID, tags: tags)
        } catch {
            saveError = "Could not update note: \(error.localizedDescription)"
        }
    }
```

- [ ] **Step 6: New items go into the viewed folder**

In `AppModel.createNoteAndShow()`, replace `_ = try await notesController.create()` with:

```swift
                _ = try await notesController.create(
                    frontMatter: NoteFrontMatter(folderID: notesFolderFilter.newItemFolderID))
```

In `MeetingController.start()`, replace `_ = try await session.start()` with:

```swift
            _ = try await session.start(labels: ItemLabels(folderID: model.meetingsFolderFilter.newItemFolderID))
```

- [ ] **Step 7: Upload drafts carry labels**

In `UploadController.Draft`, add `var labels = ItemLabels()` after `let scoped: Bool`.

In `choose(_:)`, replace `selected.append(Draft(url: url, metadata: metadata, scoped: scoped))` with:

```swift
                var draft = Draft(url: url, metadata: metadata, scoped: scoped)
                draft.labels.folderID = model.library.folder(model.library.lastUploadFolderID)?.id
                selected.append(draft)
```

Add after `clearDraft()`:

```swift
    func setDraftLabels(_ id: UUID, _ labels: ItemLabels) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].labels = labels
    }

    /// Copies the first card's folder and tags to every card.
    func applyFirstLabelsToAll() {
        guard let first = drafts.first?.labels else { return }
        for index in drafts.indices { drafts[index].labels = first }
    }
```

In `submit()`, before `drafts.removeAll()` add:

```swift
        let lastFolder = drafts.last?.labels.folderID
        Task { await model.setLastUploadFolder(lastFolder) }
```

In `run(_:)`, in the `MeetingManifest(` call that builds the upload manifest, add after `importedAt: now`:

```swift
                    importedAt: now,
                    folderID: draft.labels.folderID,
                    tags: draft.labels.tags
```

(replace the existing `importedAt: now` line; keep its closing parenthesis.)

- [ ] **Step 8: Build and test**

Run: `swift build && swift test`
Expected: build succeeds, all tests pass.

- [ ] **Step 9: Commit**

```bash
git add Sources/BugVoice/AppModel.swift Sources/BugVoice/MeetingController.swift Sources/BugVoice/UploadController.swift
git commit -m "feat(app): load folders and route label changes

Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 10: Shared library views

**Files:**
- Create: `Sources/BugVoice/UI/Library/FolderControls.swift`
- Create: `Sources/BugVoice/UI/Library/TagField.swift`
- Create: `Sources/BugVoice/UI/Library/LabelsBox.swift`
- Create: `Sources/BugVoice/UI/Library/ManageFoldersSheet.swift`

**Interfaces:**
- Consumes: Task 9 `AppModel` API.
- Produces: `FolderFilterMenu(model:filter:counts:allTitle:onManage:)`, `TagFilterBar(catalog:selected:)`, `FolderPicker(model:folderID:onChange:)`, `NewFolderSheet(model:onCreated:)`, `TagField(tags:catalog:noun:onChange:)`, `LabelsBox(model:labels:catalog:noun:suggested:suggestionSource:onChange:onAcceptSuggestion:onDismissSuggestions:)`, `ManageFoldersSheet(model:)`.

- [ ] **Step 1: `FolderControls.swift`**

```swift
import SwiftUI
import VoiceCore

/// List-header menu: All, Unfiled, each folder with counts, New folder…, Manage folders….
struct FolderFilterMenu: View {
    let model: AppModel
    @Binding var filter: FolderFilter
    let counts: FolderCounts
    let allTitle: String
    let onManage: () -> Void
    @State private var creating = false

    var body: some View {
        Menu {
            Button { filter = .all } label: { menuLabel(allTitle, count: counts.all, on: filter == .all) }
            Button { filter = .unfiled } label: { menuLabel("Unfiled", count: counts.unfiled, on: filter == .unfiled) }
            Divider()
            ForEach(model.sortedFolders) { folder in
                Button { filter = .folder(folder.id) } label: {
                    menuLabel(folder.name, count: counts.count(folder.id), on: filter == .folder(folder.id))
                }
            }
            Divider()
            Button("New folder…") { creating = true }.disabled(model.libraryReadOnly)
            Button("Manage folders…", action: onManage)
        } label: {
            Label(title, systemImage: "folder")
        }
        .fixedSize()
        .sheet(isPresented: $creating) {
            NewFolderSheet(model: model) { folder in filter = .folder(folder.id) }
        }
    }

    private var title: String {
        switch filter {
        case .all: allTitle
        case .unfiled: "Unfiled"
        case .folder(let id): model.folderName(id) ?? allTitle
        }
    }

    private func menuLabel(_ name: String, count: Int, on: Bool) -> some View {
        HStack {
            if on { Image(systemName: "checkmark") }
            Text("\(name)  \(count)")
        }
    }
}

/// Tags menu plus removable chips. Several chips mean all must match.
struct TagFilterBar: View {
    let catalog: [TagCount]
    @Binding var selected: [String]

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                if catalog.isEmpty { Text("No tags yet") }
                ForEach(catalog) { tag in
                    Button("#\(tag.name)  \(tag.count)") {
                        if !selected.contains(tag.name) { selected.append(tag.name) }
                    }
                }
            } label: {
                Label("Tags", systemImage: "tag")
            }
            .fixedSize()
            ForEach(selected, id: \.self) { tag in
                TagChip(name: tag) { selected.removeAll { $0 == tag } }
            }
        }
    }
}

struct TagChip: View {
    let name: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(name)").font(.caption)
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark").font(.caption2) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove tag \(name)")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}

/// Folder button for a single item: Unfiled, each folder, New folder….
struct FolderPicker: View {
    let model: AppModel
    let folderID: FolderID?
    let onChange: (FolderID?) -> Void
    @State private var creating = false

    var body: some View {
        Menu {
            Button { onChange(nil) } label: { row("Unfiled", on: model.folderName(folderID) == nil) }
            Divider()
            ForEach(model.sortedFolders) { folder in
                Button { onChange(folder.id) } label: { row(folder.name, on: folder.id == folderID) }
            }
            Divider()
            Button("New folder…") { creating = true }.disabled(model.libraryReadOnly)
        } label: {
            Label(model.folderName(folderID) ?? "Unfiled", systemImage: "folder")
        }
        .fixedSize()
        .sheet(isPresented: $creating) {
            NewFolderSheet(model: model) { folder in onChange(folder.id) }
        }
    }

    private func row(_ name: String, on: Bool) -> some View {
        HStack {
            if on { Image(systemName: "checkmark") }
            Text(name)
        }
    }
}

struct NewFolderSheet: View {
    let model: AppModel
    let onCreated: (LibraryFolder) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New folder").font(.headline)
            TextField("Folder name", text: $name)
                .onSubmit(create)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create", action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func create() {
        Task {
            switch await model.createFolder(name) {
            case .success(let folder):
                onCreated(folder)
                dismiss()
            case .failure(let failure):
                error = failure.errorDescription
            }
        }
    }
}
```

- [ ] **Step 2: `TagField.swift`**

```swift
import SwiftUI
import VoiceCore

/// Tag chips with `+ Add tag`. Typing shows catalog tags containing the text
/// (prefix matches first) and `Create tag "#x"` for a new name. Return picks
/// the first entry; Escape cancels.
struct TagField: View {
    let tags: [String]
    let catalog: [TagCount]
    /// "meeting" or "note", for the limit message.
    let noun: String
    let onChange: ([String]) -> Void
    @State private var editing = false
    @State private var text = ""
    @State private var message: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FlowRow {
                ForEach(tags, id: \.self) { tag in
                    TagChip(name: tag) { onChange(tags.filter { $0 != tag }) }
                }
                if editing {
                    TextField("#tag", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .focused($focused)
                        .onSubmit { pick(options.first) }
                        .onExitCommand(perform: cancel)
                        .onAppear { focused = true }
                } else {
                    Button("+ Add tag") { editing = true; message = nil }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if editing, !options.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(options, id: \.self) { option in
                        Button { pick(option) } label: { optionLabel(option) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private enum Option: Hashable {
        case existing(String, Int)
        case create(String)
    }

    private var options: [Option] {
        let needle = TagName.normalize(text)
        guard let needle else { return [] }
        let matches = catalog
            .filter { $0.name.contains(needle) && !tags.contains($0.name) }
            .sorted { lhs, rhs in
                let left = lhs.name.hasPrefix(needle), right = rhs.name.hasPrefix(needle)
                return left != right ? left : lhs.count > rhs.count
            }
            .prefix(6)
            .map { Option.existing($0.name, $0.count) }
        let exists = catalog.contains { $0.name == needle } || tags.contains(needle)
        return matches + (exists ? [] : [.create(needle)])
    }

    @ViewBuilder private func optionLabel(_ option: Option) -> some View {
        switch option {
        case .existing(let name, let count):
            HStack { Text("#\(name)"); Spacer(); Text("\(count)").foregroundStyle(.secondary) }
                .font(.caption).frame(width: 200)
        case .create(let name):
            Text("Create tag \"#\(name)\"").font(.caption).frame(width: 200, alignment: .leading)
        }
    }

    private func pick(_ option: Option?) {
        guard let option else {
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                message = "Tags use letters, numbers, - _ and /, up to 32 characters."
            }
            return
        }
        let name: String
        switch option {
        case .existing(let value, _): name = value
        case .create(let value): name = value
        }
        var labels = ItemLabels(tags: tags)
        switch labels.addTag(name) {
        case .added: onChange(labels.tags)
        case .full: message = "A \(noun) can have up to 10 tags."
        case .invalid: message = "Tags use letters, numbers, - _ and /, up to 32 characters."
        case .duplicate: break
        }
        cancel()
    }

    private func cancel() {
        text = ""
        editing = false
    }
}

/// Wraps chips onto new lines.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
```

Note: `.existing` case labels in `optionLabel` include the count; `Option` is `Hashable` so `ForEach(options, id: \.self)` works.

- [ ] **Step 3: `LabelsBox.swift`**

```swift
import SwiftUI
import VoiceCore

/// Folder, Tags and (meetings only) Suggested rows under an item's title.
struct LabelsBox: View {
    let model: AppModel
    let labels: ItemLabels
    let catalog: [TagCount]
    let noun: String
    var suggested: [String] = []
    var suggestionSource: String = ""
    let onChange: (ItemLabels) -> Void
    var onAcceptSuggestion: (String) -> Void = { _ in }
    var onDismissSuggestions: () -> Void = {}

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Folder").font(.caption).foregroundStyle(.secondary)
                FolderPicker(model: model, folderID: labels.folderID) { id in
                    onChange(ItemLabels(folderID: id, tags: labels.tags))
                }
            }
            GridRow {
                Text("Tags").font(.caption).foregroundStyle(.secondary)
                TagField(tags: labels.tags, catalog: catalog, noun: noun) { tags in
                    onChange(ItemLabels(folderID: labels.folderID, tags: tags))
                }
            }
            if !suggested.isEmpty {
                GridRow {
                    Text("Suggested").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(suggested, id: \.self) { tag in
                            Button("+ #\(tag)") { onAcceptSuggestion(tag) }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .foregroundStyle(.purple)
                                .overlay(Capsule().strokeBorder(.purple, style: StrokeStyle(lineWidth: 1, dash: [3])))
                        }
                        Text("From the summary · \(suggestionSource) · click to add")
                            .font(.caption).foregroundStyle(.secondary)
                        Button(action: onDismissSuggestions) { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Dismiss suggestions")
                            .accessibilityLabel("Dismiss suggestions")
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.25)))
    }
}
```

- [ ] **Step 4: `ManageFoldersSheet.swift`**

```swift
import SwiftUI
import VoiceCore

struct ManageFoldersSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: FolderID?
    @State private var draft = ""
    @State private var error: String?
    @State private var pendingDelete: LibraryFolder?
    @State private var creating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Folders").font(.headline)
            if model.sortedFolders.isEmpty {
                Text("No folders yet.").foregroundStyle(.secondary)
            }
            ForEach(model.sortedFolders) { folder in
                HStack(spacing: 8) {
                    if editing == folder.id {
                        TextField("Folder name", text: $draft).onSubmit { save(folder.id) }
                    } else {
                        Label(folder.name, systemImage: "folder")
                    }
                    Spacer()
                    Text(countText(folder.id)).font(.caption).foregroundStyle(.secondary)
                    if editing == folder.id {
                        Button("Save") { save(folder.id) }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Rename") { editing = folder.id; draft = folder.name; error = nil }
                        Button("Delete", role: .destructive) { pendingDelete = folder }
                    }
                }
                .disabled(model.libraryReadOnly)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("+ New folder") { creating = true }.disabled(model.libraryReadOnly)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            Text("Deleting a folder moves its meetings and notes to Unfiled. Nothing is deleted, and files on disk never move.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 460)
        .sheet(isPresented: $creating) { NewFolderSheet(model: model) { _ in } }
        .confirmationDialog(
            "Delete folder \"\(pendingDelete?.name ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { folder in
            Button("Delete", role: .destructive) { Task { await model.deleteFolder(folder.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its meetings and notes move to Unfiled. No files are deleted.")
        }
    }

    private func countText(_ id: FolderID) -> String {
        let meetings = LibraryProjection.counts(model.meetingManifests, known: model.library.knownIDs).count(id)
        let notes = LibraryProjection.counts(model.notesController.notes, known: model.library.knownIDs).count(id)
        return "\(meetings) \(meetings == 1 ? "meeting" : "meetings") · \(notes) \(notes == 1 ? "note" : "notes")"
    }

    private func save(_ id: FolderID) {
        Task {
            if let failure = await model.renameFolder(id, to: draft) {
                error = failure.errorDescription
            } else {
                editing = nil
                error = nil
            }
        }
    }
}
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: succeeds. Fix compile errors in these four files only.

- [ ] **Step 6: Commit**

```bash
git add Sources/BugVoice/UI/Library
git commit -m "feat(app): add folder menu, tag field, labels box and folders sheet

Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 11: Meetings page

**Files:**
- Modify: `Sources/BugVoice/UI/MeetingsPage.swift`

**Interfaces:**
- Consumes: Task 9 and Task 10 views.

- [ ] **Step 1: Filtered groups**

In `MeetingsPage`, replace the `groups` property with:

```swift
    private var visibleMeetings: [MeetingManifest] {
        LibraryProjection.filter(
            model.meetingManifests,
            folder: model.meetingsFolderFilter,
            tags: model.meetingTagFilter,
            known: model.library.knownIDs
        )
    }

    private var groups: [MeetingDayGroup] {
        MeetingListProjection.groups(meetings: visibleMeetings, query: model.meetingSearchQuery)
    }
```

Add state: `@State private var managingFolders = false`, `@State private var tagEditMeetingID: MeetingID?`.

- [ ] **Step 2: Filter bar**

In `library`, between the header `HStack` and the search `TextField`, insert:

```swift
            HStack(spacing: 6) {
                FolderFilterMenu(
                    model: model,
                    filter: Binding(get: { model.meetingsFolderFilter }, set: { model.meetingsFolderFilter = $0 }),
                    counts: LibraryProjection.counts(model.meetingManifests, known: model.library.knownIDs),
                    allTitle: "All meetings",
                    onManage: { managingFolders = true }
                )
                TagFilterBar(catalog: model.meetingTagCatalog, selected: $model.meetingTagFilter)
                Spacer(minLength: 0)
            }
```

After the `.confirmationDialog` on `library` (added in commit `337e07e`), add:

```swift
        .sheet(isPresented: $managingFolders) { ManageFoldersSheet(model: model) }
```

In the empty states, when `groups.isEmpty` and `model.meetingManifests` is not empty, the existing "No matching meetings" view already covers filtered-out results.

- [ ] **Step 3: Row tags and folder**

Give `MeetingListRow` a `let folderName: String?` (pass `model.meetingsFolderFilter == .all ? model.folderName(meeting.folderID) : nil`). Under the time/duration `Text`, add:

```swift
                if folderName != nil || !meeting.tags.isEmpty {
                    HStack(spacing: 4) {
                        if let folderName {
                            Label(folderName, systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(meeting.tags.prefix(3), id: \.self) { TagChip(name: $0) }
                        if meeting.tags.count > 3 {
                            Text("+\(meeting.tags.count - 3)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
```

- [ ] **Step 4: Context menu**

Replace the row `.contextMenu { … }` with:

```swift
                                    .contextMenu {
                                        Button("Rename…") {
                                            renameTitle = meeting.title
                                            pendingRename = meeting
                                        }
                                        Menu("Move to folder") {
                                            Button("Unfiled") {
                                                Task { await model.setMeetingLabels(id: meeting.id, folderID: nil, tags: meeting.tags) }
                                            }
                                            Divider()
                                            ForEach(model.sortedFolders) { folder in
                                                Button {
                                                    Task { await model.setMeetingLabels(id: meeting.id, folderID: folder.id, tags: meeting.tags) }
                                                } label: {
                                                    if folder.id == meeting.folderID { Label(folder.name, systemImage: "checkmark") } else { Text(folder.name) }
                                                }
                                            }
                                        }
                                        Button("Tags…") { model.selectedMeetingID = meeting.id }
                                        if meeting.state != .recording, meeting.state != .paused {
                                            Divider()
                                            Button("Delete…", role: .destructive) { pendingDelete = meeting }
                                        }
                                    }
```

- [ ] **Step 5: Labels box in details**

In `MeetingDetails.body`, after the date/duration `Text(…)` block (the one ending `.foregroundStyle(.secondary)`), insert:

```swift
            LabelsBox(
                model: model,
                labels: ItemLabels(folderID: meeting.folderID, tags: meeting.tags),
                catalog: model.allTagCatalog,
                noun: "meeting",
                suggested: meeting.suggestedTags,
                suggestionSource: model.plan(for: .meetings).shortName ?? "Meetings model",
                onChange: { labels in
                    Task { await model.setMeetingLabels(id: meeting.id, folderID: labels.folderID, tags: labels.tags) }
                },
                onAcceptSuggestion: { tag in
                    var labels = ItemLabels(folderID: meeting.folderID, tags: meeting.tags)
                    labels.addTag(tag)
                    Task {
                        await model.setMeetingLabels(
                            id: meeting.id, folderID: labels.folderID, tags: labels.tags,
                            suggestedTags: meeting.suggestedTags.filter { $0 != tag })
                    }
                },
                onDismissSuggestions: {
                    Task { await model.setMeetingLabels(id: meeting.id, folderID: meeting.folderID, tags: meeting.tags, suggestedTags: []) }
                }
            )
```

(`model.plan(for:)` and `.shortName` exist; `DictationController` uses `model.plan(for: feature).shortName`.)

- [ ] **Step 6: Build and commit**

Run: `swift build && swift test`
Expected: succeeds.

```bash
git add Sources/BugVoice/UI/MeetingsPage.swift
git commit -m "feat(app): filter, file and tag meetings

Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 12: Notes page

**Files:**
- Modify: `Sources/BugVoice/UI/NotesPage.swift`

- [ ] **Step 1: Filtered list**

Replace `filteredNotes` with:

```swift
    private var filteredNotes: [NotesListItem] {
        let visible = LibraryProjection.filter(
            controller.notes,
            folder: model.notesFolderFilter,
            tags: model.notesTagFilter,
            known: model.library.knownIDs
        )
        return NotesListProjection.filter(
            visible.map {
                NotesListItem(id: $0.id, title: $0.title, body: $0.body, modifiedAt: $0.modifiedAt, tags: $0.frontMatter.tags)
            },
            query: searchText
        )
    }
```

Add state: `@State private var managingFolders = false`.

- [ ] **Step 2: Filter bar**

Under the search/New note `HStack(…).padding(12)`, insert:

```swift
            HStack(spacing: 6) {
                FolderFilterMenu(
                    model: model,
                    filter: Binding(get: { model.notesFolderFilter }, set: { model.notesFolderFilter = $0 }),
                    counts: LibraryProjection.counts(controller.notes, known: model.library.knownIDs),
                    allTitle: "All notes",
                    onManage: { managingFolders = true }
                )
                TagFilterBar(catalog: model.noteTagCatalog, selected: $model.notesTagFilter)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
```

Add `.sheet(isPresented: $managingFolders) { ManageFoldersSheet(model: model) }` after the last `.confirmationDialog` on the page.

- [ ] **Step 3: New note uses the viewed folder**

In `createNote()`, replace `_ = try await controller.create()` with:

```swift
                _ = try await controller.create(frontMatter: NoteFrontMatter(folderID: model.notesFolderFilter.newItemFolderID))
```

- [ ] **Step 4: Row tags and context menu**

In `noteRow(_:)`, after the date/word-count `HStack`, add:

```swift
            if !item.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(item.tags.prefix(3), id: \.self) { TagChip(name: $0) }
                    if item.tags.count > 3 { Text("+\(item.tags.count - 3)").font(.caption).foregroundStyle(.secondary) }
                }
            }
```

On the row `Button { … } label: { noteRow(item) }`, after `.buttonStyle(.plain)`, add:

```swift
                        .contextMenu {
                            Menu("Move to folder") {
                                Button("Unfiled") { Task { await model.setNoteLabels(id: item.id, folderID: nil, tags: item.tags) } }
                                Divider()
                                ForEach(model.sortedFolders) { folder in
                                    Button(folder.name) {
                                        Task { await model.setNoteLabels(id: item.id, folderID: folder.id, tags: item.tags) }
                                    }
                                }
                            }
                            Button("Tags…") { Task { try? await controller.select(id: item.id) } }
                            Divider()
                            Button("Delete…", role: .destructive) {
                                Task {
                                    try? await controller.select(id: item.id)
                                    confirmDelete = true
                                }
                            }
                        }
```

(Notes rename stays in the title field, as today.)

- [ ] **Step 5: Labels box under the title**

In `editor`, after the `Text("Markdown · saved to Notes/…")` view and its modifiers, insert:

```swift
                LabelsBox(
                    model: model,
                    labels: note.frontMatter.labels,
                    catalog: model.allTagCatalog,
                    noun: "note",
                    onChange: { labels in
                        Task { await model.setNoteLabels(id: note.id, folderID: labels.folderID, tags: labels.tags) }
                    }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
```

- [ ] **Step 6: Build and commit**

Run: `swift build && swift test`

```bash
git add Sources/BugVoice/UI/NotesPage.swift
git commit -m "feat(app): filter, file and tag notes

Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 13: Upload folder picker and tag suggestions

**Files:**
- Modify: `Sources/BugVoice/UI/UploadPage.swift`
- Modify: `Sources/BugVoice/AppModel.swift` (`performMeetingText`)

- [ ] **Step 1: Upload card labels**

In `UploadPage`, replace the `ForEach(controller.drafts) { draft in metadataCard(…) }` block with:

```swift
                            ForEach(controller.drafts) { draft in
                                VStack(spacing: 10) {
                                    metadataCard(
                                        name: draft.metadata.fileName, kind: draft.metadata.kind,
                                        duration: draft.metadata.duration, bytes: draft.metadata.byteSize)
                                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                                        GridRow {
                                            Text("Save to").font(.caption).foregroundStyle(.secondary)
                                            HStack(spacing: 8) {
                                                FolderPicker(model: model, folderID: draft.labels.folderID) { id in
                                                    controller.setDraftLabels(draft.id, ItemLabels(folderID: id, tags: draft.labels.tags))
                                                }
                                                if draft.labels.folderID != nil, draft.labels.folderID == model.library.lastUploadFolderID {
                                                    Text("Last used").font(.caption).foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        GridRow {
                                            Text("Tags").font(.caption).foregroundStyle(.secondary)
                                            TagField(tags: draft.labels.tags, catalog: model.allTagCatalog, noun: "meeting") { tags in
                                                controller.setDraftLabels(draft.id, ItemLabels(folderID: draft.labels.folderID, tags: tags))
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    if controller.drafts.count > 1, draft.id == controller.drafts.first?.id {
                                        Button("Apply to all") { controller.applyFirstLabelsToAll() }
                                    }
                                }
                            }
```

- [ ] **Step 2: Suggestions after a summary**

In `AppModel.performMeetingText`, every successful path returns `text` after saving. Wrap the three `return text` points so a summary triggers suggestions. Add this method:

```swift
    /// Asks the Meetings model for up to 3 existing tags. Failures stay silent.
    private func suggestTags(for id: MeetingID, summary: String, model textModel: any TextModel) async {
        let allowed = allTagCatalog.map(\.name)
        guard !allowed.isEmpty, !summary.isEmpty,
              let meeting = meetingManifests.first(where: { $0.id == id }) else { return }
        guard let answer = try? await textModel.clean(TagSuggestion.request(summary: summary, allowed: allowed)) else { return }
        let suggestions = TagSuggestion.parse(answer, allowed: allowed, existing: meeting.tags)
        guard !suggestions.isEmpty else { return }
        let current = meetingManifests.first(where: { $0.id == id }) ?? meeting
        await setMeetingLabels(id: id, folderID: current.folderID, tags: current.tags, suggestedTags: suggestions)
    }
```

Then in `performMeetingText`, change each of the three success exits from

```swift
            await reloadMeetings()
            return text
```

to

```swift
            await reloadMeetings()
            if kind == .summary {
                let suggestionModel = textModel
                Task { await suggestTags(for: id, summary: text, model: suggestionModel) }
            }
            return text
```

and the final store path's `await reloadMeetings()` / `return text` the same way. The suggestion runs in its own `Task` so the summary shows without waiting for it.

- [ ] **Step 3: Build, test, build the app**

Run: `swift build && swift test && Scripts/build-app.sh`
Expected: tests pass; the script ends with "Built …/build/BugVoice.app".

- [ ] **Step 4: Commit**

```bash
git add Sources/BugVoice/UI/UploadPage.swift Sources/BugVoice/AppModel.swift
git commit -m "feat(app): choose upload folder and suggest tags after a summary

Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 14: Checklist and status docs

**Files:**
- Modify: `docs/testing/manual-checklist.md`
- Modify: `docs/progress/HANDOFF.md`

- [ ] **Step 1: Append manual checks** after the last table row (currently 125):

```markdown
| 126 | Meetings / Notes | Folder menu → New folder… "Project A"; Manage folders… rename it "Project Atlas"; try "unfiled" and a duplicate | Folder appears on both pages; rename keeps its items; reserved and duplicate names show the message | |
| 127 | Meetings | Filter by a folder, then add a tag chip; search "#tag" | List shows only matching meetings; counts in the menu match | |
| 128 | Meetings / Notes | Right-click a row → Move to folder › another folder | Row leaves the filtered list and appears under the new folder | |
| 129 | Meetings / Notes | In the labels box type "#onb", pick an existing tag, then create a new one; add an 11th tag | Autocomplete lists existing tags first; 11th tag shows the limit message | |
| 130 | Upload | Drop 2 files; set Save to and tags on the first; Apply to all; Transcribe | Both meetings are in that folder with those tags; next upload defaults to it with "Last used" | |
| 131 | Meetings | With some tags in use, generate a Summary | Up to 3 purple suggested chips; clicking adds the tag; ✕ clears them; nothing added without a click | |
| 132 | Meetings / Notes | Delete a folder that has items | Items show under Unfiled; no files deleted; page filter falls back to All | |
| 133 | Notes | Tag and file a note, then open its .md file in TextEdit or Obsidian | File starts with --- folder/tags --- then # Title; other apps' keys kept after an edit | |
| 134 | Meetings | While recording, change the meeting's folder and tags; stop | Labels kept after transcription finishes | |
```

- [ ] **Step 2: HANDOFF status**

In `docs/progress/HANDOFF.md`, add under the current status section a short paragraph: "Folders and tags (roadmap item 9) implemented on `feat/folders-tags`: spec `docs/superpowers/specs/2026-10-15-folders-tags-design.md`, plan `docs/superpowers/plans/2026-10-15-folders-tags.md`. Device checks 126–134 pending."

- [ ] **Step 3: Commit**

```bash
git add docs/testing/manual-checklist.md docs/progress/HANDOFF.md
git commit -m "docs: add folders and tags checks 126-134 and handoff status

Co-Authored-By: Codex <noreply@openai.com>"
```

---

## Self-review notes

- Spec 3.1 → Task 2; 3.2 meetings → Task 5, notes → Tasks 3–4; 3.3 → Task 1; 4.1 → Tasks 6, 8, 11, 12; 4.2 → Tasks 10–12; 4.3 → Tasks 11–12; 4.4 → Task 9 Step 6; 4.5 → Tasks 9 Step 7, 13; 4.6 → Task 10; 5 → Tasks 7, 13; 7 errors → Tasks 2, 9.
- Deviation from spec 6: upload labels ride on `UploadController.Draft` (already keyed to the job in `inputs`) instead of new `UploadJob` fields; the manifest is created from the draft, so the behavior is the same.
- Row folder name shows only under the All filter, as the spec says.
