import Foundation
import Testing
@testable import VoiceCore

struct RestoreApplierTests {
    private let now = Date(timeIntervalSince1970: 1_760_864_400)
    private let zone = TimeZone(secondsFromGMT: 0)!
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("BugVoice")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func write(_ root: URL, _ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    private func exists(_ root: URL, _ path: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) }
    private func read(_ root: URL, _ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
    private func backup(_ root: URL, damaged: Bool = false, size: Int = 3) async throws -> URL {
        let source = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try write(source, "data/settings.json", String(repeating: "n", count: size))
        try write(source, "data/Notes/b.md", "")
        let manifest = BackupManifest(format: 1, createdAt: now, appVersion: "1", build: "1", counts: .init(notes: 1, meetings: 0, dictations: 0, dictionaryWords: 0, folders: 0, tags: 0), files: [.init(path: "settings.json", size: Int64(size + (damaged ? 1 : 0))), .init(path: "Notes/b.md", size: 0)])
        try manifest.encoded().write(to: source.appendingPathComponent("backup.json"))
        let archive = source.appendingPathExtension("zip")
        let result = try await FoundationProcessRunner().run(executable: "/usr/bin/ditto", arguments: ["-c", "-k", source.path, archive.path], stdin: "", workingDirectory: nil, timeout: 60)
        #expect(result.exitCode == 0)
        return archive
    }
    private func stage(_ root: URL) async throws {
        _ = try await RestoreApplier.stage(archive: backup(root), root: root, writer: BackupWriter(), meetingActive: false, availableBytes: 100_000)
    }
    @Test func stageRefusesActiveMeeting() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        await #expect(throws: BackupError.meetingActive) { try await RestoreApplier.stage(archive: root, root: root, writer: BackupWriter(), meetingActive: true, availableBytes: 1000) }
    }
    @Test func stageRefusesWhenSpaceIsShort() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let archive = try await backup(root, size: 1000)
        await #expect(throws: BackupError.notEnoughSpace(bytes: 100)) { try await RestoreApplier.stage(archive: archive, root: root, writer: BackupWriter(), meetingActive: false, availableBytes: 1000) }
    }
    @Test func stageRefusesDamagedBackup() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let archive = try await backup(root, damaged: true)
        await #expect(throws: BackupError.damaged(count: 1)) { try await RestoreApplier.stage(archive: archive, root: root, writer: BackupWriter(), meetingActive: false, availableBytes: 1000) }
        #expect(!exists(RestoreApplier.pendingDirectory(for: root), ""))
    }
    @Test func stageWritesReadyLast() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try await stage(root)
        let pending = RestoreApplier.pendingDirectory(for: root)
        #expect(exists(pending, "data/settings.json")); #expect(exists(pending, "backup.json"))
        #expect(try Data(contentsOf: pending.appendingPathComponent("ready")).isEmpty)
    }
    @Test func applyReplacesLibraryAndKeepsSafetyCopy() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        for (path, value) in [("settings.json", "old"), ("Notes/a.md", "a"), ("credentials.json", "key"), ("models/m", "model"), ("SearchIndex/i", "index")] { try write(root, path, value) }
        try await stage(root)
        let outcome = try #require(try RestoreApplier.applyPending(root: root, now: now, timeZone: zone))
        #expect(outcome.backupCreatedAt == now); #expect(try read(root, "settings.json") == "nnn")
        #expect(exists(root, "Notes/b.md")); #expect(!exists(root, "Notes/a.md"))
        #expect(try read(root, "credentials.json") == "key"); #expect(try read(root, "models/m") == "model")
        #expect(!exists(root, "SearchIndex")); #expect(!exists(RestoreApplier.pendingDirectory(for: root), ""))
        #expect(try read(outcome.safetyCopy, "settings.json") == "old"); #expect(exists(outcome.safetyCopy, "Notes/a.md"))
    }
    @Test func pendingWithoutReadyIsDeletedAndLibraryUntouched() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try write(root, "settings.json", "old"); try write(RestoreApplier.pendingDirectory(for: root), "data/settings.json", "new")
        #expect(try RestoreApplier.applyPending(root: root, now: now, timeZone: zone) == nil)
        #expect(try read(root, "settings.json") == "old"); #expect(!exists(RestoreApplier.pendingDirectory(for: root), ""))
    }
    @Test func failedMoveRollsBack() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try write(root, "settings.json", "old"); try write(root, "Notes/a.md", "a")
        try await stage(root)
        do {
            _ = try RestoreApplier.applyPending(root: root, now: now, timeZone: zone, mover: ThirdMoveFails())
            Issue.record("Expected a restore failure")
        } catch {
            guard case .failed = error as? BackupError else { Issue.record("Expected BackupError.failed"); return }
        }
        #expect(try read(root, "settings.json") == "old"); #expect(try read(root, "Notes/a.md") == "a")
        #expect(!exists(root, "Notes/b.md")); #expect(RestoreApplier.safetyCopies(in: root).isEmpty)
    }
    @Test func secondRestoreKeepsOnlyNewestSafetyCopy() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try await stage(root); _ = try RestoreApplier.applyPending(root: root, now: now, timeZone: zone)
        try await stage(root)
        let second = try #require(try RestoreApplier.applyPending(root: root, now: now.addingTimeInterval(120), timeZone: zone))
        #expect(RestoreApplier.safetyCopies(in: root).map(\.lastPathComponent) == [second.safetyCopy.lastPathComponent])
    }
    @Test func failedRollbackPreservesRecoveryDataAcrossLaunches() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try write(root, "settings.json", "old"); try write(root, "Notes/a.md", "a")
        try await stage(root)
        #expect(throws: (any Error).self) { try RestoreApplier.applyPending(root: root, now: now, timeZone: zone, mover: RollbackFails()) }
        let safety = try #require(RestoreApplier.safetyCopies(in: root).first)
        let pending = RestoreApplier.pendingDirectory(for: root)
        #expect(try read(safety, "settings.json") == "old")
        #expect(exists(pending, "data/settings.json"))
        #expect(throws: (any Error).self) { try RestoreApplier.applyPending(root: root, now: now, timeZone: zone) }
        #expect(try read(safety, "settings.json") == "old")
        #expect(exists(pending, "data/settings.json"))
        await #expect(throws: (any Error).self) { try await stage(root) }
        #expect(try read(safety, "settings.json") == "old")
        #expect(exists(pending, "rollback-failed"))
    }
    @Test func sameMinuteRestoreDoesNotOverwriteSafetyCopy() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try await stage(root); _ = try RestoreApplier.applyPending(root: root, now: now, timeZone: zone)
        try write(root, "settings.json", "second original")
        try await stage(root)
        let outcome = try #require(try RestoreApplier.applyPending(root: root, now: now, timeZone: zone))
        #expect(try read(outcome.safetyCopy, "settings.json") == "second original")
        #expect(RestoreApplier.safetyCopies(in: root).map(\.lastPathComponent) == [outcome.safetyCopy.lastPathComponent])
    }
    @Test func cleanupFailureCannotReplayAnEmptyRestore() async throws {
        let root = try fixture()
        let index = root.appendingPathComponent("SearchIndex")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: index.path)
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        }
        try write(root, "settings.json", "old")
        try write(root, "SearchIndex/i", "index")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: index.path)
        try await stage(root)
        #expect(throws: (any Error).self) { try RestoreApplier.applyPending(root: root, now: now, timeZone: zone) }
        #expect(try read(root, "settings.json") == "nnn")
        _ = try? RestoreApplier.applyPending(root: root, now: now, timeZone: zone)
        #expect(try read(root, "settings.json") == "nnn")
        #expect(exists(root, "Notes/b.md"))
    }
    @Test func nothingPendingReturnsNil() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        #expect(try RestoreApplier.applyPending(root: root, now: now, timeZone: zone) == nil)
    }
}
private final class ThirdMoveFails: FileMoving, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func moveItem(at source: URL, to destination: URL) throws {
        let fail = lock.withLock { count += 1; return count == 3 }
        if fail { throw BackupError.failed("injected move failure") }
        try FileManager.default.moveItem(at: source, to: destination)
    }
}

private final class RollbackFails: FileMoving, @unchecked Sendable {
    private var count = 0
    func moveItem(at source: URL, to destination: URL) throws {
        count += 1
        if count >= 3 { throw BackupError.failed("persistent move failure") }
        try FileManager.default.moveItem(at: source, to: destination)
    }
}
