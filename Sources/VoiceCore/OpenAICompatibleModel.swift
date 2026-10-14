import Foundation

/// `POST {base}/v1/chat/completions`. LM Studio, Ollama, MLX servers, vLLM,
/// llama.cpp server.
public struct OpenAICompatibleModel: TextModel {
    public var baseURL: URL
    public var model: String
    public var apiKey: String?
    public var session: URLSession

    public init(baseURL: URL, model: String, apiKey: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.session = session
    }

    struct Body: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let messages: [Message]
        let temperature: Double
        let max_tokens: Int
        let stream = false
        /// Present only when thinking is disabled (Qwen3 chat templates).
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
        if let apiKey, !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        let body = Body(
            model: model,
            messages: [.init(role: "system", content: request.system), .init(role: "user", content: request.user)],
            temperature: request.temperature,
            max_tokens: request.maxTokens,
            chat_template_kwargs: request.disableThinking ? ["enable_thinking": false] : nil
        )
        let urlRequest = try HTTP.jsonRequest(url: Endpoint.join(baseURL, "chat/completions"), body: body, headers: headers)
        let reply = try HTTP.decode(Reply.self, from: try await HTTP.send(urlRequest, session: session))
        guard let content = reply.choices.first?.message.content else {
            throw ProviderError.malformedResponse("no choices[0].message.content")
        }
        return content
    }
}
