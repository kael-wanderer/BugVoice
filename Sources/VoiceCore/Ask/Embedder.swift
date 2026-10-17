import Foundation

/// Turns text into meaning vectors for Ask's meaning search.
public protocol Embedder: Sendable {
    var modelID: String { get }
    /// One L2-normalised vector per input, in input order.
    func embed(_ inputs: [String]) async throws -> [[Float]]
}

/// `POST {base}/v1/embeddings` on a local OpenAI-compatible server (oMLX, LM Studio, Ollama).
public struct OpenAICompatibleEmbedder: Embedder {
    public static let batchSize = 32

    public let baseURL: URL
    public let model: String
    public let apiKey: String?
    public let timeout: TimeInterval
    public let session: URLSession

    public var modelID: String { model }

    public init(baseURL: URL, model: String, apiKey: String?, timeout: TimeInterval = 60,
                session: URLSession = HTTP.noRedirectSession) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
        self.session = session
    }

    struct Body: Encodable { let model: String; let input: [String] }
    struct Reply: Decodable {
        struct Item: Decodable { let index: Int; let embedding: [Float] }
        let data: [Item]
    }

    public func embed(_ inputs: [String]) async throws -> [[Float]] {
        var result: [[Float]] = []
        result.reserveCapacity(inputs.count)
        var start = 0
        while start < inputs.count {
            let end = min(start + Self.batchSize, inputs.count)
            result += try await embedBatch(Array(inputs[start..<end]))
            start = end
        }
        return result
    }

    private func embedBatch(_ batch: [String]) async throws -> [[Float]] {
        var headers: [String: String] = [:]
        if let apiKey, !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        let request = try HTTP.jsonRequest(url: Endpoint.join(baseURL, "embeddings"),
                                           body: Body(model: model, input: batch), headers: headers, timeout: timeout)
        // Inputs are user text: never put the response body in an error.
        let data = try await HTTP.send(request, session: session, redactBody: true)
        let reply = try HTTP.decode(Reply.self, from: data)
        guard reply.data.count == batch.count else {
            throw ProviderError.malformedResponse("expected \(batch.count) embeddings, got \(reply.data.count)")
        }
        let sorted = reply.data.sorted { $0.index < $1.index }
        guard sorted.map(\.index) == Array(0..<batch.count) else {
            throw ProviderError.malformedResponse("embedding indexes are not 0..<\(batch.count)")
        }
        return sorted.map { Self.normalised($0.embedding) }
    }

    static func normalised(_ v: [Float]) -> [Float] {
        var sum: Float = 0
        for x in v { sum += x * x }
        guard sum > 0 else { return v }
        let norm = sum.squareRoot()
        return v.map { $0 / norm }
    }
}
