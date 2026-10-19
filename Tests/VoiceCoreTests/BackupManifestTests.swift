import Foundation
import Testing
@testable import VoiceCore

struct BackupManifestTests {
    private func manifest(format: Int = 1, files: [BackupManifest.File] = []) -> BackupManifest {
        BackupManifest(format: format, createdAt: Date(timeIntervalSince1970: 1_760_864_400),
                       appVersion: "0.1.0", build: "210",
                       counts: .init(notes: 1, meetings: 2, dictations: 3, dictionaryWords: 4, folders: 5, tags: 6),
                       files: files)
    }

    @Test func roundTrips() throws {
        let original = manifest(files: [.init(path: "Notes/a.md", size: 42), .init(path: "history.jsonl", size: 17)])
        #expect(BackupManifest.currentFormat == 1)
        let data = try original.encoded()
        #expect(try BackupManifest.decode(data) == original)
        #expect(original.totalBytes == 59)
        #expect(manifest().totalBytes == 0)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\n"))
        #expect(json.contains("2025-10-19T"))
    }

    @Test func rejectsGarbageAndNewerFormat() throws {
        #expect(throws: BackupError.notABackup) { try BackupManifest.decode(Data("hello".utf8)) }
        #expect(throws: BackupError.notABackup) { try BackupManifest.decode(Data("{}".utf8)) }
        let data = try manifest(format: 2).encoded()
        #expect(throws: BackupError.newerFormat) { try BackupManifest.decode(data) }
    }

    @Test func problemsListsMissingAndWrongSize() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Notes"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("abc".utf8).write(to: directory.appendingPathComponent("a.json"))
        try Data("12345".utf8).write(to: directory.appendingPathComponent("Notes/b.md"))
        let value = manifest(files: [.init(path: "a.json", size: 3), .init(path: "Notes/b.md", size: 4), .init(path: "c.json", size: 1)])
        #expect(value.problems(in: directory) == ["Notes/b.md", "c.json"])
    }

    @Test func damagedMessageCountsInSingular() {
        #expect(BackupError.damaged(count: 1).errorDescription == "The backup is damaged: 1 file is missing or the wrong size. Nothing was changed.")
        #expect(BackupError.damaged(count: 2).errorDescription == "The backup is damaged: 2 files are missing or the wrong size. Nothing was changed.")
        #expect(BackupError.notABackup.errorDescription == "This file is not a BugVoice backup.")
        #expect(BackupError.newerFormat.errorDescription == "This backup is from a newer BugVoice format. Update BugVoice first.")
        #expect(BackupError.meetingActive.errorDescription == "A meeting is recording. Stop the meeting first.")
        #expect(BackupError.destinationInsideLibrary.errorDescription == "Choose a folder outside the BugVoice data folder.")
        #expect(BackupError.failed("Failure detail").errorDescription == "Failure detail")
        let bytes: Int64 = 1_000_000
        #expect(BackupError.notEnoughSpace(bytes: bytes).errorDescription == "Not enough free space to restore. Free \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) and try again.")
    }
}
