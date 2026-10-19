import Foundation

public struct AppLanguageRule: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case app, website, terminalPanel }

    public var kind: Kind
    public var id: String
    public var language: SpeechLanguage

    public init(kind: Kind, id: String, language: SpeechLanguage) {
        self.kind = kind
        self.id = id
        self.language = language
    }

    public static let defaults: [AppLanguageRule] = [
        .init(kind: .app, id: "com.stablyai.orca", language: .en),
        .init(kind: .app, id: "com.mitchellh.ghostty", language: .en),
        .init(kind: .app, id: "com.apple.Terminal", language: .en),
        .init(kind: .app, id: "com.googlecode.iterm2", language: .en),
        .init(kind: .app, id: "dev.warp.Warp-Stable", language: .en),
        .init(kind: .terminalPanel, id: "com.microsoft.VSCode", language: .en),
        .init(kind: .terminalPanel, id: "com.todesktop.230313mzl4w4u92", language: .en),
        .init(kind: .app, id: "com.anthropic.claudefordesktop", language: .vi),
        .init(kind: .website, id: "chatgpt.com", language: .vi),
    ]
}

public enum LanguageKey: String, Codable, Sendable, CaseIterable { case off, shift, option }

public struct LanguageResolver: Sendable {
    private let settings: SpeechSettings

    public init(settings: SpeechSettings) { self.settings = settings }

    public func language(for focus: FocusSnapshot, keyChoice: SpeechLanguage? = nil) -> SpeechLanguage {
        if let keyChoice { return keyChoice }
        if settings.language != .auto { return settings.language }
        return ruleLanguage(for: focus) ?? .auto
    }

    public func ruleLanguage(for focus: FocusSnapshot) -> SpeechLanguage? {
        if let host = Self.host(from: focus.url),
           let rule = settings.appLanguages.first(where: { $0.kind == .website && Self.host(host, matches: $0.id) }) {
            return rule.language
        }
        if focus.isTerminalPanel, let bundleID = focus.bundleID,
           let rule = settings.appLanguages.first(where: { $0.kind == .terminalPanel && $0.id == bundleID }) {
            return rule.language
        }
        if let bundleID = focus.bundleID,
           let rule = settings.appLanguages.first(where: { $0.kind == .app && $0.id == bundleID }) {
            return rule.language
        }
        return nil
    }

    private static func host(from address: String?) -> String? {
        guard let address, let components = URLComponents(string: address),
              let host = components.host?.lowercased() else { return nil }
        return host
    }

    private static func host(_ host: String, matches ruleHost: String) -> Bool {
        let ruleHost = ruleHost.lowercased()
        return host == ruleHost || host.hasSuffix("." + ruleHost)
    }
}
