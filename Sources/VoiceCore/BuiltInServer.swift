import Foundation

/// Where the running llama-server answers, and the key it requires.
public struct BuiltInEndpoint: Sendable, Equatable {
    public let baseURL: URL
    public let apiKey: String

    public init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
}

/// Starts the bundled llama-server on demand and keeps it alive while in use.
public protocol BuiltInServing: Sendable {
    /// Starts the server for `model` if needed and returns where it answers.
    func endpoint(for model: BuiltInModel) async throws -> BuiltInEndpoint
    /// Resets the idle clock.
    func noteUse() async
}

public enum BuiltInServerArguments {
    /// The llama-server command line. Binds 127.0.0.1 only and requires the key.
    public static func make(modelPath: String, port: Int, apiKey: String) -> [String] {
        ["-m", modelPath, "--host", "127.0.0.1", "--port", "\(port)", "--api-key", apiKey,
         "-c", "4096", "-ngl", "999", "--jinja"]
    }
}

public enum BuiltInIdle {
    /// True once `idleMinutes` have passed since the last use.
    public static func shouldStop(lastUse: Date, now: Date, idleMinutes: Int) -> Bool {
        now.timeIntervalSince(lastUse) >= TimeInterval(idleMinutes * 60)
    }
}

/// Cleanup through the bundled llama-server: waits for the server, then sends
/// an OpenAI-compatible request with this launch's key.
public struct BuiltInTextModel: TextModel {
    public let model: BuiltInModel
    public let server: any BuiltInServing
    public let requestTimeout: TimeInterval
    let session: URLSession

    public init(model: BuiltInModel, server: any BuiltInServing, requestTimeout: TimeInterval,
                session: URLSession = HTTP.noRedirectSession) {
        self.model = model
        self.server = server
        self.requestTimeout = requestTimeout
        self.session = session
    }

    public func clean(_ request: CleanupRequest) async throws -> String {
        let endpoint = try await server.endpoint(for: model)
        let text = OpenAICompatibleModel(
            baseURL: endpoint.baseURL, model: model.id, apiKey: endpoint.apiKey,
            flavor: .local, requestTimeout: requestTimeout, session: session)
        do {
            let output = try await text.clean(request)
            await server.noteUse()
            return output
        } catch {
            await server.noteUse()
            throw error
        }
    }
}
