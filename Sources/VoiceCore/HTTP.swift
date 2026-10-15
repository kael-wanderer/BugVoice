import Foundation

public final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? { nil }
}

enum Endpoint {
    /// `path` is relative to `/v1`. A base that already ends in `/v1` is not doubled.
    static func join(_ base: URL, _ path: String) -> URL {
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        if !root.hasSuffix("/v1") { root += "/v1" }
        return URL(string: root + "/" + path)!
    }
}

public enum HTTP {
    public static let noRedirectSession = URLSession(configuration: .default, delegate: NoRedirectDelegate(), delegateQueue: nil)
    static func send(_ request: URLRequest, session: URLSession, redactBody: Bool = false) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (300..<400).contains(status) { throw ProviderError.redirected }
        guard (200..<300).contains(status) else {
            throw ProviderError.http(status: status, body: redactBody ? "" : String(decoding: data.prefix(2_000), as: UTF8.self))
        }
        return data
    }

    static func jsonRequest(url: URL, body: some Encodable, headers: [String: String], timeout: TimeInterval = 60) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ProviderError.malformedResponse(String(decoding: data.prefix(500), as: UTF8.self))
        }
    }
}
