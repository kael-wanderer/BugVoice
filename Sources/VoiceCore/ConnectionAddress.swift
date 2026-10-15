import Foundation

/// Which address a connection may be called at. A key only ever goes to a
/// fixed cloud address, an https server, or this Mac.
public enum ConnectionAddress {
    public static func fixedURL(for kind: ConnectionKind) -> URL? {
        switch kind {
        case .openAI: URL(string: "https://api.openai.com")
        case .anthropic: URL(string: "https://api.anthropic.com")
        case .openRouter: URL(string: "https://openrouter.ai/api")
        case .openAICompatible, .anthropicCompatible: nil
        }
    }

    /// The address to call, or nil when the typed one breaks a rule.
    public static func baseURL(for connection: ModelConnection) -> URL? {
        if let fixed = fixedURL(for: connection.kind) { return fixed }
        guard problem(connection.baseURL) == nil else { return nil }
        return URL(string: connection.baseURL.trimmingCharacters(in: .whitespaces))
    }

    /// Nil when the address is usable; otherwise the sentence to show.
    public static func problem(_ typed: String) -> String? {
        let text = typed.trimmingCharacters(in: .whitespaces)
        guard let parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host, !host.isEmpty
        else { return "Enter an address like http://localhost:1234." }
        if parts.user != nil || parts.password != nil {
            return "Remove the user name and password from the address."
        }
        if parts.query != nil || parts.fragment != nil {
            return "Remove the ? or # part of the address."
        }
        if scheme == "http", !isLoopback(host: host) {
            return "Use https:// for a server that is not on this Mac."
        }
        return nil
    }

    /// The host itself, not a name that merely starts with "localhost".
    public static func isLoopback(host: String) -> Bool {
        let h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return h == "localhost" || h == "127.0.0.1" || h == "::1"
    }

    public static func isLocal(_ url: URL) -> Bool {
        url.host.map { isLoopback(host: $0) } ?? false
    }
}
