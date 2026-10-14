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

public enum ProviderError: Error, Equatable, Sendable {
    case invalidURL(String)
    case http(status: Int, body: String)
    case malformedResponse(String)
    case unavailable(String)
}
