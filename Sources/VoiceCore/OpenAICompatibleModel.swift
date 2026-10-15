import Foundation

/// `POST {base}/v1/chat/completions`. LM Studio, Ollama, MLX servers, vLLM,
/// llama.cpp server, OpenAI, OpenRouter.
public struct OpenAICompatibleModel: TextModel {
    public enum Flavor: Sendable, Equatable {
        /// Local or self-hosted server: `max_tokens`, `temperature`, and
        /// `chat_template_kwargs` to turn thinking off.
        case local
        /// api.openai.com: newer models reject `max_tokens` and `temperature`;
        /// reasoning tokens count against `max_completion_tokens`.
        case openAI
        case openRouter
    }

    static let openAIMinimumCompletionTokens = 2048

    public var baseURL: URL
    public var model: String
    public var apiKey: String?
    public var flavor: Flavor
    public var requestTimeout: TimeInterval
    public var session: URLSession

    public init(baseURL: URL, model: String, apiKey: String? = nil, flavor: Flavor = .local,
                requestTimeout: TimeInterval = 60, session: URLSession = HTTP.noRedirectSession) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.flavor = flavor
        self.requestTimeout = requestTimeout
        self.session = session
    }

    struct Body: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let messages: [Message]
        let temperature: Double?
        let max_tokens: Int?
        let max_completion_tokens: Int?
        let stream = false
        /// Present only for local servers when thinking is disabled.
        let chat_template_kwargs: [String: Bool]?
    }

    struct Reply: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    public func clean(_ request: CleanupRequest) async throws -> String {
        var headers: [String: String] = [:]
        let keyed = !(apiKey ?? "").isEmpty
        if keyed, let apiKey { headers["Authorization"] = "Bearer \(apiKey)" }
        if flavor == .openRouter { headers["X-Title"] = "BugVoice" }
        let openAI = flavor == .openAI
        let body = Body(
            model: model,
            messages: [.init(role: "system", content: request.system), .init(role: "user", content: request.user)],
            temperature: openAI ? nil : request.temperature,
            max_tokens: openAI ? nil : request.maxTokens,
            max_completion_tokens: openAI ? max(request.maxTokens, Self.openAIMinimumCompletionTokens) : nil,
            chat_template_kwargs: flavor == .local && request.disableThinking ? ["enable_thinking": false] : nil
        )
        let urlRequest = try HTTP.jsonRequest(url: Endpoint.join(baseURL, "chat/completions"), body: body, headers: headers, timeout: requestTimeout)
        let reply = try HTTP.decode(Reply.self, from: try await HTTP.send(urlRequest, session: session, redactBody: keyed))
        guard let content = reply.choices.first?.message.content else {
            throw ProviderError.malformedResponse("no choices[0].message.content")
        }
        return content
    }
}
