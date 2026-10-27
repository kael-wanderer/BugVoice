import Foundation
import Testing
@testable import VoiceCore

@Suite(.serialized)
struct ProviderTests {
    let request = CleanupRequest(system: "SYS", user: "USER", maxTokens: 64, temperature: 0.1)

    @Test func errorDescriptionsNeverIncludeTheBody() {
        let http = ProviderError.http(status: 418, body: "SENTINEL-SECRET")
        #expect(http.localizedDescription == "The service answered with status 418.")
    }

    @Test func malformedReplyKeepsNoReplyText() {
        #expect(throws: ProviderError.self) {
            _ = try HTTP.decode([String: Int].self, from: Data("SENTINEL-SECRET".utf8))
        }
        do {
            _ = try HTTP.decode([String: Int].self, from: Data("SENTINEL-SECRET".utf8))
        } catch {
            #expect(!String(describing: error).contains("SENTINEL"))
        }
    }

    func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    @Test func endpointJoinHandlesV1AndSlashes() {
        #expect(Endpoint.join(URL(string: "http://h:1234")!, "chat/completions").absoluteString == "http://h:1234/v1/chat/completions")
        #expect(Endpoint.join(URL(string: "http://h:1234/v1/")!, "chat/completions").absoluteString == "http://h:1234/v1/chat/completions")
        #expect(Endpoint.join(URL(string: "http://h/api/v1")!, "messages").absoluteString == "http://h/api/v1/messages")
    }

    @Test func openAIRequestShapeAndParse() async throws {
        StubURLProtocol.handler = { req, body in
            #expect(req.url?.path == "/v1/chat/completions")
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer KEY")
            let j = self.json(body)
            #expect(j["model"] as? String == "qwen")
            #expect(j["stream"] as? Bool == false)
            #expect(j["max_tokens"] as? Int == 64)
            let messages = j["messages"] as? [[String: String]]
            #expect(messages?[0] == ["role": "system", "content": "SYS"])
            #expect(messages?[1] == ["role": "user", "content": "USER"])
            return (200, Data(#"{"choices":[{"message":{"role":"assistant","content":"OK"}}]}"#.utf8))
        }
        let model = OpenAICompatibleModel(baseURL: URL(string: "http://localhost:1234")!, model: "qwen", apiKey: "KEY", session: StubURLProtocol.session())
        #expect(try await model.clean(request) == "OK")
    }

    @Test func openAISendsEnableThinkingFalseOnlyWhenDisabled() async throws {
        var seen: [[String: Any]] = []
        StubURLProtocol.handler = { _, body in
            seen.append(self.json(body))
            return (200, Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8))
        }
        let model = OpenAICompatibleModel(baseURL: URL(string: "http://h")!, model: "qwen", session: StubURLProtocol.session())
        _ = try await model.clean(CleanupRequest(system: "S", user: "U", disableThinking: true))
        _ = try await model.clean(CleanupRequest(system: "S", user: "U"))
        #expect((seen[0]["chat_template_kwargs"] as? [String: Bool]) == ["enable_thinking": false])
        #expect(seen[1]["chat_template_kwargs"] == nil)
    }

    @Test func openAIOmitsAuthorizationWithoutKey() async throws {
        StubURLProtocol.handler = { req, _ in
            #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
            return (200, Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8))
        }
        let model = OpenAICompatibleModel(baseURL: URL(string: "http://h")!, model: "m", apiKey: "", session: StubURLProtocol.session())
        _ = try await model.clean(request)
    }

    @Test func httpErrorSurfaces() async {
        StubURLProtocol.handler = { _, _ in (404, Data(#"{"error":"model not loaded"}"#.utf8)) }
        let model = OpenAICompatibleModel(baseURL: URL(string: "http://h")!, model: "m", session: StubURLProtocol.session())
        await #expect(throws: ProviderError.http(status: 404, body: #"{"error":"model not loaded"}"#)) {
            try await model.clean(request)
        }
    }

    @Test func malformedJSONSurfaces() async {
        StubURLProtocol.handler = { _, _ in (200, Data("not json".utf8)) }
        let model = OpenAICompatibleModel(baseURL: URL(string: "http://h")!, model: "m", session: StubURLProtocol.session())
        await #expect(throws: ProviderError.self) { try await model.clean(request) }
    }

    @Test func anthropicRequestShapeAndParse() async throws {
        StubURLProtocol.handler = { req, body in
            #expect(req.url?.path == "/v1/messages")
            #expect(req.value(forHTTPHeaderField: "x-api-key") == "K")
            #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            let j = self.json(body)
            #expect(j["system"] as? String == "SYS")
            #expect(j["max_tokens"] as? Int == 64)
            #expect((j["messages"] as? [[String: String]])?.first == ["role": "user", "content": "USER"])
            return (200, Data(#"{"content":[{"type":"thinking","thinking":"x"},{"type":"text","text":"A"},{"type":"text","text":"B"}]}"#.utf8))
        }
        let model = AnthropicCompatibleModel(baseURL: URL(string: "http://h")!, model: "m", apiKey: "K", session: StubURLProtocol.session())
        #expect(try await model.clean(request) == "AB")
    }

    @Test func catalogListsModelIDs() async throws {
        StubURLProtocol.handler = { req, _ in
            #expect(req.url?.path == "/v1/models")
            return (200, Data(#"{"data":[{"id":"qwen3.8-27b-mlx"},{"id":"nomic"}]}"#.utf8))
        }
        let ids = try await ModelCatalog.list(baseURL: URL(string: "http://h")!, apiKey: nil, anthropic: false, session: StubURLProtocol.session())
        #expect(ids == ["qwen3.8-27b-mlx", "nomic"])
    }

    @Test func openAIFlavorBody() async throws {
        StubURLProtocol.handler = { _, body in
            let j = self.json(body)
            #expect(j["max_completion_tokens"] as? Int == 2048)
            #expect(j["max_tokens"] == nil)
            #expect(j["temperature"] == nil)
            #expect(j["chat_template_kwargs"] == nil)
            return (200, Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8))
        }
        let model = OpenAICompatibleModel(baseURL: URL(string: "https://api.openai.com")!, model: "gpt-5.5-mini", apiKey: "K",
                                          flavor: .openAI, session: StubURLProtocol.session())
        _ = try await model.clean(CleanupRequest(system: "S", user: "U", maxTokens: 60, disableThinking: true))
    }

    @Test func openAIFlavorKeepsLargerBudgets() async throws {
        StubURLProtocol.handler = { _, body in
            #expect(self.json(body)["max_completion_tokens"] as? Int == 4096)
            return (200, Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8))
        }
        let model = OpenAICompatibleModel(baseURL: URL(string: "https://api.openai.com")!, model: "m", flavor: .openAI, session: StubURLProtocol.session())
        _ = try await model.clean(CleanupRequest(system: "S", user: "U", maxTokens: 4096))
    }

    @Test func openRouterSendsTitleAndLocalBody() async throws {
        StubURLProtocol.handler = { req, body in
            #expect(req.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
            #expect(req.value(forHTTPHeaderField: "X-Title") == "BugVoice")
            let j = self.json(body)
            #expect(j["max_tokens"] as? Int == 64)
            #expect(j["chat_template_kwargs"] == nil)
            return (200, Data(#"{"choices":[{"message":{"content":"x"}}]}"#.utf8))
        }
        let model = OpenAICompatibleModel(baseURL: URL(string: "https://openrouter.ai/api")!, model: "m", apiKey: "K", flavor: .openRouter, session: StubURLProtocol.session())
        _ = try await model.clean(CleanupRequest(system: "S", user: "U", maxTokens: 64, disableThinking: true))
    }

    @Test func requestTimeoutIsApplied() async throws {
        StubURLProtocol.handler = { req, _ in
            #expect(req.timeoutInterval == 600)
            return (200, Data(#"{"content":[{"type":"text","text":"x"}]}"#.utf8))
        }
        let model = AnthropicCompatibleModel(baseURL: URL(string: "http://localhost:1")!, model: "m", requestTimeout: 600, session: StubURLProtocol.session())
        _ = try await model.clean(request)
    }

    @Test func redirectIsAnErrorNotFollowed() async {
        StubURLProtocol.handler = { _, _ in (302, Data()) }
        let model = OpenAICompatibleModel(baseURL: URL(string: "https://h")!, model: "m", apiKey: "K", session: StubURLProtocol.session())
        await #expect(throws: ProviderError.redirected) { try await model.clean(request) }
        #expect(ProviderError.redirected.localizedDescription == "The server redirected the request. BugVoice does not follow it with a key.")
    }

    @Test func noRedirectDelegateRefuses() async {
        let response = HTTPURLResponse(url: URL(string: "https://a")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let task = URLSession.shared.dataTask(with: URL(string: "https://a")!)
        let next = await NoRedirectDelegate().urlSession(.shared, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://b")!))
        #expect(next == nil)
    }

    @Test func keyedErrorsDoNotEchoTheBody() async {
        StubURLProtocol.handler = { _, _ in (401, Data(#"{"error":"bad key sk-123"}"#.utf8)) }
        let model = OpenAICompatibleModel(baseURL: URL(string: "https://h")!, model: "m", apiKey: "sk-123", session: StubURLProtocol.session())
        await #expect(throws: ProviderError.http(status: 401, body: "")) { try await model.clean(request) }
    }

    @Test(arguments: [
        (401, "The key was refused."), (403, "The key was refused."),
        (404, "The model or address was not found."), (429, "The service is rate limiting requests."),
        (500, "The service had an error."), (503, "The service had an error."),
    ])
    func statusSentences(status: Int, sentence: String) {
        #expect(ProviderError.http(status: status, body: "x").localizedDescription == sentence)
    }
}
