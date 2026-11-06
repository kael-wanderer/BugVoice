import Foundation
import Testing
@testable import BugVoiceMac
import VoiceCore

@Suite struct BuiltInDownloaderTests {
    private func tempFile(_ text: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("m.gguf")
        try Data(text.utf8).write(to: file)
        return file
    }

    static let abcHash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    @Test func sha256OfAbc() throws {
        let file = try tempFile("abc")
        #expect(try BuiltInDownloader.sha256Hex(of: file) == Self.abcHash)
    }

    @Test func verifyAcceptsMatchingHash() throws {
        let file = try tempFile("abc")
        try BuiltInDownloader.verify(file, sha256: Self.abcHash)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func verifyDeletesFileOnMismatch() throws {
        let file = try tempFile("abc")
        #expect(throws: BuiltInDownloadError.hashMismatch) {
            try BuiltInDownloader.verify(file, sha256: String(repeating: "0", count: 64))
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func onlyHttpsIsAccepted() throws {
        try BuiltInDownloader.requireHTTPS(URL(string: "https://huggingface.co/x.gguf")!)
        #expect(throws: BuiltInDownloadError.insecureURL) {
            try BuiltInDownloader.requireHTTPS(URL(string: "http://example.com/x.gguf")!)
        }
        #expect(throws: BuiltInDownloadError.insecureURL) {
            try BuiltInDownloader.requireHTTPS(URL(string: "file:///etc/passwd")!)
        }
    }
}
