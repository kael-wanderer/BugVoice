import Foundation
import Testing
@testable import VoiceCore

/// Stub with its own locked state, so it never shares a handler with suites
/// that use `StubURLProtocol`.
final class BuiltInStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var requests: [(URLRequest, Data)] = []
    nonisolated(unsafe) private static var replyText = "Clean."
    private static let lock = NSLock()

    static func reset(reply: String = "Clean.") { lock.withLock { requests = []; replyText = reply } }
    static var seen: [(URLRequest, Data)] { lock.withLock { requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = StubURLProtocol.body(of: request)
        Self.lock.withLock { Self.requests.append((request, body)) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let reply = Self.lock.withLock { Self.replyText }
        let json = try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": reply]]]])
        client?.urlProtocol(self, didLoad: json)
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
    private(set) var begins = 0
    private(set) var asked: [String] = []

    init(_ result: Result<BuiltInEndpoint, Failure>) { self.result = result }

    func endpoint(for model: BuiltInModel) async throws -> BuiltInEndpoint {
        asked.append(model.id)
        return try result.get()
    }

    func beginRequest() async { begins += 1 }
    func endRequest() async { uses += 1 }
}

/// A server that is cold: its first `endpoint(for:)` waits `loadSeconds`, as
/// llama-server does while it loads the model. Later calls answer at once.
private actor ColdServer: BuiltInServing {
    let loadSeconds: Double
    private var loaded = false
    init(loadSeconds: Double) { self.loadSeconds = loadSeconds }

    func endpoint(for model: BuiltInModel) async throws -> BuiltInEndpoint {
        if !loaded {
            try await Task.sleep(for: .seconds(loadSeconds))
            loaded = true
        }
        return BuiltInEndpoint(baseURL: URL(string: "http://127.0.0.1:51234")!, apiKey: "KEY123")
    }

    func beginRequest() async {}
    func endRequest() async {}
}

@Suite(.serialized)
struct BuiltInServerTests {
    let model = BuiltInCatalog.models[0]
    let request = CleanupRequest(system: "SYS", user: "USER", maxTokens: 64, temperature: 0.1, disableThinking: true)

    @Test func argumentsAreExact() {
        #expect(BuiltInServerArguments.make(modelPath: "/m/x.gguf", port: 51234, apiKey: "abc") == [
            "-m", "/m/x.gguf", "--host", "127.0.0.1", "--port", "51234", "--api-key", "abc",
            "-c", "4096", "-ngl", "999", "--jinja", "--no-webui",
        ])
    }

    @Test func idleStopsAtTheLimitNotBefore() {
        let last = Date(timeIntervalSinceReferenceDate: 1_000_000)
        #expect(!BuiltInIdle.shouldStop(lastUse: last, now: last.addingTimeInterval(14 * 60 + 59), idleMinutes: 15))
        #expect(BuiltInIdle.shouldStop(lastUse: last, now: last.addingTimeInterval(15 * 60), idleMinutes: 15))
    }

    @Test func idleNeverStopsWhileARequestRuns() {
        let last = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let late = last.addingTimeInterval(60 * 60)
        #expect(!BuiltInIdle.shouldStop(lastUse: last, now: late, idleMinutes: 15, inFlight: 1))
        #expect(BuiltInIdle.shouldStop(lastUse: last, now: late, idleMinutes: 15, inFlight: 0))
    }

    @Test func modelLoadDoesNotCountAgainstCleanupTimeout() async {
        BuiltInStubProtocol.reset(reply: "Hello world.")
        let server = ColdServer(loadSeconds: 0.6)
        let text = BuiltInTextModel(model: model, server: server, requestTimeout: 5, session: BuiltInStubProtocol.session())
        let pipeline = DictationPipeline(
            transcriber: FakeTranscriber(),
            cleanup: CleanupModel(model: text, modelID: model.id, disableThinking: true, timeoutSeconds: 0.2),
            insertion: RecordingInsertion(), focus: FixedFocus(focus: notionFocus),
            settings: AppSettings(), vocabulary: Vocabulary())
        let r = await pipeline.run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.rawReason == nil)
        #expect(r.cleaned == "Hello world.")
        #expect(r.finalText == "Hello world.")
    }

    @Test func serverThatFailsToStartLeavesRawText() async {
        let server = FakeServer(.failure(.boom))
        let text = BuiltInTextModel(model: model, server: server, requestTimeout: 5, session: BuiltInStubProtocol.session())
        let pipeline = DictationPipeline(
            transcriber: FakeTranscriber(),
            cleanup: CleanupModel(model: text, modelID: model.id, disableThinking: true, timeoutSeconds: 0.2),
            insertion: RecordingInsertion(), focus: FixedFocus(focus: notionFocus),
            settings: AppSettings(), vocabulary: Vocabulary())
        let r = await pipeline.run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.rawReason == .modelError)
        #expect(r.cleaned == nil)
        #expect(r.finalText == "hello world")
    }

    @Test func serverFailureIsThrownByClean() async {
        let server = FakeServer(.failure(.boom))
        let text = BuiltInTextModel(model: model, server: server, requestTimeout: 5, session: BuiltInStubProtocol.session())
        await #expect(throws: FakeServer.Failure.boom) {
            _ = try await text.clean(request)
        }
        #expect(await server.uses == 0)
        #expect(await server.begins == 0)
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
        #expect(await server.begins == 1)
        #expect(await server.uses == 1)
        #expect(await server.asked == [model.id])
    }
}
