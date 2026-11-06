import CryptoKit
import Foundation
import Testing
@testable import BugVoiceMac
@testable import VoiceCore

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
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(try BuiltInDownloader.sha256Hex(of: file) == Self.abcHash)
    }

    @Test func verifyAcceptsMatchingHash() throws {
        let file = try tempFile("abc")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try BuiltInDownloader.verify(file, sha256: Self.abcHash)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func verifyDeletesFileOnMismatch() throws {
        let file = try tempFile("abc")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
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

// MARK: - Network behaviour with a stubbed URLSession

final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Reply { var status: Int; var headers: [String: String] = [:]; var body: Data = Data() }
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Reply)?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let handler = Self.handler
        Self.lock.unlock()
        let reply = handler?(request) ?? Reply(status: 500)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct BuiltInDownloaderNetworkTests {
    static let content = Data("0123456789".utf8)
    static var hash: String { SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined() }

    func model(url: String = "https://example.com/m.gguf") -> BuiltInModel {
        BuiltInModel(id: "t", tier: .small, name: "t", summary: "", fileName: "m.gguf",
                     url: URL(string: url)!, sha256: Self.hash, bytes: Int64(Self.content.count),
                     memoryBytes: 1, speed: 1, quality: 1)
    }

    func session(_ handler: @escaping @Sendable (URLRequest) -> StubProtocol.Reply) -> (BuiltInDownloader, URL) {
        StubProtocol.lock.lock()
        StubProtocol.handler = handler
        StubProtocol.requests = []
        StubProtocol.lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (BuiltInDownloader(session: URLSession(configuration: config)), dir)
    }

    func seedPart(_ dir: URL, _ text: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: dir.appendingPathComponent("m.gguf.part"))
    }

    var requestCount: Int { StubProtocol.lock.lock(); defer { StubProtocol.lock.unlock() }; return StubProtocol.requests.count }
    func range(at i: Int) -> String? { StubProtocol.requests[i].value(forHTTPHeaderField: "Range") }

    @Test func fullDownloadVerifiesAndInstalls() async throws {
        let (dl, dir) = session { _ in .init(status: 200, body: Self.content) }
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try await dl.download(model(), into: dir) { _ in }
        #expect(try Data(contentsOf: url) == Self.content)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("m.gguf.part").path))
    }

    @Test func serverAnswering200ToRangeRestartsAtZero() async throws {
        let (dl, dir) = session { _ in .init(status: 200, body: Self.content) }
        defer { try? FileManager.default.removeItem(at: dir) }
        try seedPart(dir, "0123")
        let url = try await dl.download(model(), into: dir) { _ in }
        #expect(range(at: 0) == "bytes=4-")
        #expect(try Data(contentsOf: url) == Self.content)
    }

    @Test func good206Resumes() async throws {
        let (dl, dir) = session { _ in
            .init(status: 206, headers: ["Content-Range": "bytes 4-9/10", "Content-Length": "6"],
                  body: Data("456789".utf8))
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        try seedPart(dir, "0123")
        let url = try await dl.download(model(), into: dir) { _ in }
        #expect(requestCount == 1)
        #expect(try Data(contentsOf: url) == Self.content)
    }

    @Test func mismatchedContentRangeRestartsFromZero() async throws {
        let (dl, dir) = session { req in
            if req.value(forHTTPHeaderField: "Range") != nil {
                return .init(status: 206, headers: ["Content-Range": "bytes 0-5/10"], body: Data("012345".utf8))
            }
            return .init(status: 200, body: Self.content)
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        try seedPart(dir, "0123")
        let url = try await dl.download(model(), into: dir) { _ in }
        #expect(requestCount == 2)
        #expect(range(at: 1) == nil)
        #expect(try Data(contentsOf: url) == Self.content)
    }

    @Test func resumedSizeMismatchRestartsFromZero() async throws {
        let (dl, dir) = session { req in
            if req.value(forHTTPHeaderField: "Range") != nil {
                return .init(status: 206, headers: ["Content-Range": "bytes 4-9/10", "Content-Length": "3"],
                             body: Data("456".utf8))
            }
            return .init(status: 200, body: Self.content)
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        try seedPart(dir, "0123")
        let url = try await dl.download(model(), into: dir) { _ in }
        #expect(requestCount == 2)
        #expect(range(at: 1) == nil)
        #expect(try Data(contentsOf: url) == Self.content)
    }

    @Test func resumedSizeMismatchTwiceThrowsAndKeepsNoPart() async throws {
        let (dl, dir) = session { req in
            req.value(forHTTPHeaderField: "Range") != nil
                ? .init(status: 206, headers: ["Content-Range": "bytes 4-9/10", "Content-Length": "3"], body: Data("456".utf8))
                : .init(status: 200, headers: ["Content-Length": "99"], body: Self.content)
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        try seedPart(dir, "0123")
        await #expect(throws: BuiltInDownloadError.sizeMismatch) {
            _ = try await dl.download(model(), into: dir) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("m.gguf.part").path))
    }

    @Test func status416RestartsFromZero() async throws {
        let (dl, dir) = session { req in
            req.value(forHTTPHeaderField: "Range") != nil
                ? .init(status: 416) : .init(status: 200, body: Self.content)
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        try seedPart(dir, "0123")
        let url = try await dl.download(model(), into: dir) { _ in }
        #expect(requestCount == 2)
        #expect(try Data(contentsOf: url) == Self.content)
    }

    @Test func status404ThrowsAndWritesNothing() async throws {
        let (dl, dir) = session { _ in .init(status: 404) }
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: BuiltInDownloadError.badStatus(404)) {
            _ = try await dl.download(model(), into: dir) { _ in }
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        #expect(files.isEmpty)
    }

    @Test func oversizedBodyThrowsAndDeletesPart() async throws {
        let (dl, dir) = session { _ in .init(status: 200, body: Self.content + Data("extra".utf8)) }
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: BuiltInDownloadError.tooLarge) {
            _ = try await dl.download(model(), into: dir) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("m.gguf.part").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("m.gguf").path))
    }

    @Test func wrongContentLengthIsRejected() async throws {
        let (dl, dir) = session { _ in .init(status: 200, headers: ["Content-Length": "99"], body: Self.content) }
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: BuiltInDownloadError.sizeMismatch) {
            _ = try await dl.download(model(), into: dir) { _ in }
        }
    }

    @Test func existingFinalFileIsReturnedWithoutRequest() async throws {
        let (dl, dir) = session { _ in .init(status: 500) }
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Self.content.write(to: dir.appendingPathComponent("m.gguf"))
        _ = try await dl.download(model(), into: dir) { _ in }
        #expect(requestCount == 0)
    }

    @Test func httpURLIsRejectedBeforeAnyRequest() async throws {
        let (dl, dir) = session { _ in .init(status: 200, body: Self.content) }
        await #expect(throws: BuiltInDownloadError.insecureURL) {
            _ = try await dl.download(model(url: "http://example.com/m.gguf"), into: dir) { _ in }
        }
        #expect(requestCount == 0)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }
}
