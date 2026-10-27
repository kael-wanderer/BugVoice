import Foundation

public struct CleanupRequest: Sendable, Equatable {
    public var system: String
    public var user: String
    public var maxTokens: Int
    public var temperature: Double
    /// Ask the server to skip the model's reasoning phase. Honoured by
    /// OpenAI-compatible servers through `chat_template_kwargs`.
    public var disableThinking: Bool

    public init(system: String, user: String, maxTokens: Int = 512, temperature: Double = 0.2, disableThinking: Bool = false) {
        self.system = system
        self.user = user
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.disableThinking = disableThinking
    }
}

public protocol TextModel: Sendable {
    func clean(_ request: CleanupRequest) async throws -> String
}

public enum ProviderError: Error, Equatable, Sendable, LocalizedError {
    case invalidURL(String)
    case http(status: Int, body: String)
    case malformedResponse(String)
    case unavailable(String)
    case redirected

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url): "The address \(url) is not valid."
        case .http(let status, _):
            switch status {
            case 401, 403: "The key was refused."
            case 404: "The model or address was not found."
            case 429: "The service is rate limiting requests."
            case 500...599: "The service had an error."
            default: "The service answered with status \(status)."
            }
        case .malformedResponse: "The service sent an answer BugVoice could not read."
        case .unavailable(let reason): reason
        case .redirected: "The server redirected the request. BugVoice does not follow it with a key."
        }
    }
}
