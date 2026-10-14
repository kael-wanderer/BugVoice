import Foundation

public struct CleanupRequest: Sendable, Equatable {
    public var system: String
    public var user: String
    public var maxTokens: Int
    public var temperature: Double

    public init(system: String, user: String, maxTokens: Int = 512, temperature: Double = 0.2) {
        self.system = system
        self.user = user
        self.maxTokens = maxTokens
        self.temperature = temperature
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
