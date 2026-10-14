import Foundation

public enum ModelCatalog {
    struct Listing: Decodable {
        struct Item: Decodable { let id: String }
        let data: [Item]
    }

    /// `GET {base}/v1/models`. Both API families return `{ data: [{ id }] }`.
    public static func list(baseURL: URL, apiKey: String?, anthropic: Bool, session: URLSession = .shared) async throws -> [String] {
        var request = URLRequest(url: Endpoint.join(baseURL, "models"), timeoutInterval: 10)
        if let apiKey, !apiKey.isEmpty {
            if anthropic {
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            } else {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
        if anthropic { request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version") }
        let data = try await HTTP.send(request, session: session)
        return try HTTP.decode(Listing.self, from: data).data.map(\.id)
    }
}
