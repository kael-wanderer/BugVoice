import Foundation

enum Endpoint {
    /// `path` is relative to `/v1`. A base that already ends in `/v1` is not doubled.
    static func join(_ base: URL, _ path: String) -> URL {
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        if !root.hasSuffix("/v1") { root += "/v1" }
        return URL(string: root + "/" + path)!
    }
}

enum HTTP {
    static func send(_ request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ProviderError.http(status: status, body: String(decoding: data.prefix(2_000), as: UTF8.self))
        }
        return data
    }

    static func jsonRequest(url: URL, body: some Encodable, headers: [String: String]) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 60)
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
