import Foundation

/// `POST {base}/v1/messages`.
public struct AnthropicCompatibleModel: TextModel {
    public var baseURL: URL
    public var model: String
    public var apiKey: String?
    public var version: String
    public var requestTimeout: TimeInterval
    public var session: URLSession

    public init(baseURL: URL, model: String, apiKey: String? = nil, version: String = "2023-06-01",
                requestTimeout: TimeInterval = 60, session: URLSession = HTTP.noRedirectSession) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.version = version
        self.requestTimeout = requestTimeout
        self.session = session
    }

    struct Body: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let max_tokens: Int
        let temperature: Double
        let system: String
        let messages: [Message]
    }

    struct Reply: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
    }

    public func clean(_ request: CleanupRequest) async throws -> String {
        var headers = ["anthropic-version": version]
        if let apiKey, !apiKey.isEmpty { headers["x-api-key"] = apiKey }
        let body = Body(
            model: model,
            max_tokens: request.maxTokens,
            temperature: request.temperature,
            system: request.system,
            messages: [.init(role: "user", content: request.user)]
        )
        let urlRequest = try HTTP.jsonRequest(url: Endpoint.join(baseURL, "messages"), body: body, headers: headers, timeout: requestTimeout)
        let reply = try HTTP.decode(Reply.self, from: try await HTTP.send(urlRequest, session: session, redactBody: !(apiKey ?? "").isEmpty))
        return reply.content.filter { $0.type == "text" }.compactMap(\.text).joined()
    }
}
