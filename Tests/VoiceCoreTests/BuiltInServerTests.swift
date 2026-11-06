import Foundation
import Testing
@testable import VoiceCore

/// Stub with its own locked state, so it never shares a handler with suites
/// that use `StubURLProtocol`.
final class BuiltInStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var requests: [(URLRequest, Data)] = []
    private static let lock = NSLock()

    static func reset() { lock.withLock { requests = [] } }
    static var seen: [(URLRequest, Data)] { lock.withLock { requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = StubURLProtocol.body(of: request)
        Self.lock.withLock { Self.requests.append((request, body)) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"choices":[{"message":{"content":"Clean."}}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BuiltInStubProtocol.self]
        return URLSession(configuration: config)
    }
}

private actor FakeServer: BuiltInServing {
    enum Failure: Error, Equatable { case boom }
    let result: Result<BuiltInEndpoint, Failure>
    private(set) var uses = 0
    private(set) var asked: [String] = []

    init(_ result: Result<BuiltInEndpoint, Failure>) { self.result = result }

    func endpoint(for model: BuiltInModel) async throws -> BuiltInEndpoint {
        asked.append(model.id)
        return try result.get()
    }

    func noteUse() async { uses += 1 }
}

@Suite(.serialized)
struct BuiltInServerTests {
    let model = BuiltInCatalog.models[0]
    let request = CleanupRequest(system: "SYS", user: "USER", maxTokens: 64, temperature: 0.1, disableThinking: true)

    @Test func argumentsAreExact() {
        #expect(BuiltInServerArguments.make(modelPath: "/m/x.gguf", port: 51234, apiKey: "abc") == [
            "-m", "/m/x.gguf", "--host", "127.0.0.1", "--port", "51234", "--api-key", "abc",
            "-c", "4096", "-ngl", "999", "--jinja",
        ])
    }

    @Test func idleStopsAtTheLimitNotBefore() {
        let last = Date(timeIntervalSinceReferenceDate: 1_000_000)
        #expect(!BuiltInIdle.shouldStop(lastUse: last, now: last.addingTimeInterval(14 * 60 + 59), idleMinutes: 15))
        #expect(BuiltInIdle.shouldStop(lastUse: last, now: last.addingTimeInterval(15 * 60), idleMinutes: 15))
    }

    @Test func serverFailureIsThrownByClean() async {
        let server = FakeServer(.failure(.boom))
        let text = BuiltInTextModel(model: model, server: server, requestTimeout: 5, session: BuiltInStubProtocol.session())
        await #expect(throws: FakeServer.Failure.boom) {
            _ = try await text.clean(request)
        }
        #expect(await server.uses == 0)
    }

    @Test func cleanSendsKeyAndModelIDAndNotesUse() async throws {
        BuiltInStubProtocol.reset()
        let server = FakeServer(.success(BuiltInEndpoint(baseURL: URL(string: "http://127.0.0.1:51234")!, apiKey: "KEY123")))
        let text = BuiltInTextModel(model: model, server: server, requestTimeout: 5, session: BuiltInStubProtocol.session())

        #expect(try await text.clean(request) == "Clean.")

        let seen = BuiltInStubProtocol.seen
        try #require(seen.count == 1)
        let (req, body) = seen[0]
        #expect(req.url?.absoluteString == "http://127.0.0.1:51234/v1/chat/completions")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer KEY123")
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["model"] as? String == model.id)
        #expect((json?["chat_template_kwargs"] as? [String: Bool]) == ["enable_thinking": false])
        #expect(await server.uses == 1)
        #expect(await server.asked == [model.id])
    }
}
