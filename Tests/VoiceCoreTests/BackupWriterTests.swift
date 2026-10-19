import Foundation
import Testing
@testable import VoiceCore

struct BackupWriterTests {
    private let counts = BackupManifest.Counts(notes: 1, meetings: 2, dictations: 3, dictionaryWords: 4, folders: 5, tags: 6)

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ path: String, _ text: String, in root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func archive(root: URL, to destination: URL, writer: BackupWriter = BackupWriter(), progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> Int64 {
        try await writer.write(plan: BackupPlan.make(root: root), root: root, to: destination,
                               createdAt: Date(timeIntervalSince1970: 1_760_864_400), appVersion: "0.1.0", build: "210", counts: counts, progress: progress)
    }

    @Test func roundTripKeepsUnicodeNames() async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("library")
        try write("settings.json", "{}", in: root)
        try write("Notes/ghi chú tuần 1.md", "xin chào", in: root)
        let destination = parent.appendingPathComponent("out/BugVoice Backup x.bugvoicebackup")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let writer = BackupWriter()
        let bytes = try await archive(root: root, to: destination)
        #expect(bytes > 0)
        #expect(bytes == (try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value)
        let manifest = try await writer.readManifest(destination)
        #expect(manifest.format == 1)
        #expect(manifest.files.map(\.path).sorted() == ["Notes/ghi chú tuần 1.md", "settings.json"])
        #expect(manifest.counts == counts)
        let extracted = parent.appendingPathComponent("extracted")
        try await writer.extract(destination, into: extracted)
        #expect(try String(contentsOf: extracted.appendingPathComponent("data/Notes/ghi chú tuần 1.md"), encoding: .utf8) == "xin chào")
        #expect(manifest.problems(in: extracted.appendingPathComponent("data")).isEmpty)
    }

    @Test func writerRefusesDestinationInsideLibrary() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("backups/x.bugvoicebackup")
        await #expect(throws: BackupError.destinationInsideLibrary) { try await archive(root: root, to: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func writerRefusesDestinationEqualToLibrary() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("settings.json", "preserved", in: root)
        await #expect(throws: BackupError.destinationInsideLibrary) { try await archive(root: root, to: root) }
        #expect(try String(contentsOf: root.appendingPathComponent("settings.json"), encoding: .utf8) == "preserved")
    }

    @Test func failedZipLeavesNoFile() async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("library")
        try write("settings.json", "{}", in: root)
        let destination = parent.appendingPathComponent("x.bugvoicebackup")
        await #expect(throws: BackupError.failed("Could not write the backup: disk failure")) {
            try await archive(root: root, to: destination, writer: BackupWriter(runner: FailedArchiveRunner()))
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".partial"))
    }

    @Test func readManifestRejectsZipWithoutManifest() async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let source = parent.appendingPathComponent("source")
        try write("a.txt", "hello", in: source)
        let destination = parent.appendingPathComponent("x.zip")
        let result = try await FoundationProcessRunner().run(executable: "/usr/bin/ditto", arguments: ["-c", "-k", source.path, destination.path], stdin: "", workingDirectory: nil, timeout: 60)
        #expect(result.exitCode == 0)
        await #expect(throws: BackupError.notABackup) { try await BackupWriter().readManifest(destination) }
    }

    @Test func readManifestRejectsNonZip() async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        try write("x.bugvoicebackup", "hello", in: parent)
        await #expect(throws: BackupError.notABackup) { try await BackupWriter().readManifest(parent.appendingPathComponent("x.bugvoicebackup")) }
    }

    @Test func progressReportsEveryFile() async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("library")
        for path in ["settings.json", "dictionary.json", "Notes/a.md"] { try write(path, "{}", in: root) }
        let progress = BackupProgressRecorder()
        _ = try await archive(root: root, to: parent.appendingPathComponent("x.bugvoicebackup")) { done, total in progress.record(done, total) }
        #expect(progress.values.map { $0.0 } == [1, 2, 3])
        #expect(progress.values.map { $0.1 } == [3, 3, 3])
    }
}

private struct FailedArchiveRunner: ProcessRunner {
    func run(executable: String, arguments: [String], stdin: String, workingDirectory: URL?, timeout: TimeInterval) async throws -> ProcessResult {
        // Leave an incomplete archive so the failure path must remove it.
        try Data("partial".utf8).write(to: URL(fileURLWithPath: arguments.last!))
        return ProcessResult(exitCode: 1, stdout: "", stderr: "disk failure\nmore detail")
    }
}

private final class BackupProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(Int, Int)] = []
    func record(_ done: Int, _ total: Int) { lock.withLock { recorded.append((done, total)) } }
    var values: [(Int, Int)] { lock.withLock { recorded } }
}
