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
