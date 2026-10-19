import Foundation
import Testing
@testable import BugVoiceMac
import VoiceCore

struct ProjectScannerTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bv-project-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ contents: Data, at relative: String, in root: URL) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url)
    }

    @Test func walkSkipsIgnoredFolders() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["node_modules/x.js", ".build/y.swift", ".hidden/z.swift", "Sources/App.swift"] {
            try write(Data("class AppModel {}".utf8), at: path, in: root)
        }
        #expect(await ProjectScanner.listFiles(in: root) == ["Sources/App.swift"])
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
    func gitListRespectsIgnore() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Data("Generated/\n".utf8), at: ".gitignore", in: root)
        try write(Data("class IgnoredGenerated {}".utf8), at: "Generated/G.swift", in: root)
        try write(Data("class AppModel {}".utf8), at: "Sources/AppModel.swift", in: root)
        let initRepo = Process()
        initRepo.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        initRepo.arguments = ["-C", root.path, "init", "-q"]
        try initRepo.run(); initRepo.waitUntilExit()
        let add = Process()
        add.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        add.arguments = ["-C", root.path, "add", "-A"]
        try add.run(); add.waitUntilExit()
        #expect(initRepo.terminationStatus == 0 && add.terminationStatus == 0)
        let files = await ProjectScanner.listFiles(in: root)
        #expect(files.contains("Sources/AppModel.swift"))
        #expect(!files.contains("Generated/G.swift"))
    }

    @Test func scanFindsWords() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Data("final class AppModel { func replaceLast() {} }".utf8), at: "Sources/AppModel.swift", in: root)
        let result = try await ProjectScanner.scan(folder: root, hidden: [])
        #expect(result.words.map(\.word).contains("AppModel"))
        #expect(result.words.map(\.word).contains("replaceLast"))
        #expect(result.fileCount == 1)
    }

    @Test func largeAndBinaryFilesSkipped() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let large = Data((String(repeating: "class HugeSecretName {}\n", count: 20_000)).utf8)
        try write(large, at: "Large.swift", in: root)
        try write(Data([0, 67, 108, 97, 115, 115, 32] + Array("BinaryTokenName".utf8)), at: "Binary.swift", in: root)
        let result = try await ProjectScanner.scan(folder: root, hidden: [])
        #expect(!result.words.contains(where: { ["HugeSecretName", "BinaryTokenName"].contains($0.word) }))
    }

    @Test func secretFileNeverRead() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Data("SECRET_TOKEN_VALUE=private".utf8), at: ".env", in: root)
        try write(Data("class LeakedCredential {}".utf8), at: "aws_credentials.py", in: root)
        try write(Data("class SafeController {}".utf8), at: "Sources/Safe.swift", in: root)
        let result = try await ProjectScanner.scan(folder: root, hidden: [])
        #expect(!result.words.contains(where: { ["SECRET_TOKEN_VALUE", "LeakedCredential"].contains($0.word) }))
    }

    @Test func missingFolderThrows() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        await #expect(throws: ProjectScanError.folderNotFound) { try await ProjectScanner.scan(folder: missing, hidden: []) }
    }

    @Test func emptyFolderThrows() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Data("nothing here".utf8), at: "README.md", in: root)
        await #expect(throws: ProjectScanError.noCodeFiles) { try await ProjectScanner.scan(folder: root, hidden: []) }
    }

    @Test func timeLimitStopsEarly() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Data("class AppModel {}".utf8), at: "App.swift", in: root)
        let result = try await ProjectScanner.scan(folder: root, hidden: [], timeLimit: .zero)
        #expect(result.stoppedEarly)
    }
}
