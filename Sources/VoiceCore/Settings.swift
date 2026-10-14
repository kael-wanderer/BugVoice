import Foundation

public enum Style: String, Codable, Sendable, CaseIterable {
    case terminal, document, chat, email, other
}

public enum HotkeyKey: String, Codable, Sendable, CaseIterable {
    case rightOption, rightCommand, fn, f13, f14, f15, f16, f17, f18, f19
}

public enum SpeechEngine: String, Codable, Sendable, CaseIterable {
    case whisperKit, openAICompatible
}

public enum TextModelProvider: String, Codable, Sendable, CaseIterable {
    case openAICompatible, anthropicCompatible, appleIntelligence, none
}

public enum Retention: String, Codable, Sendable, CaseIterable {
    case forever, days30, days7, off

    public var maxAge: TimeInterval? {
        switch self {
        case .forever, .off: nil
        case .days30: 30 * 86_400
        case .days7: 7 * 86_400
        }
    }
}

public struct SpeechSettings: Codable, Equatable, Sendable {
    public var engine: SpeechEngine = .whisperKit
    public var whisperModel = "large-v3-v20240930_turbo"
    public var language: SpeechLanguage = .auto
    public var useVocabularyHints = true
    public var serverBaseURL = "http://localhost:8000"
    public var serverModel = "whisper-1"
    /// Core Audio device UID; nil = system default input.
    public var microphoneUID: String?

    public init() {}
}

public struct TextModelSettings: Codable, Equatable, Sendable {
    public var provider: TextModelProvider = .openAICompatible
    public var baseURL = "http://localhost:1234"
    public var model = "qwen3.8-27b-mlx"
    public var timeoutSeconds: Double = 3
    public var disableThinking = true
    public var anthropicVersion = "2023-06-01"

    public init() {}
}

public struct StyleSettings: Codable, Equatable, Sendable {
    /// Keyed by `Style.rawValue`. A missing key means cleanup is on.
    public var cleanupEnabled: [String: Bool] = [Style.terminal.rawValue: false]
    /// Bundle ID → style.
    public var appOverrides: [String: Style] = [:]
    /// Keyed by `Style.rawValue`; replaces the built-in style rules.
    public var customRules: [String: String] = [:]

    public init() {}

    public func isCleanupEnabled(for style: Style) -> Bool {
        cleanupEnabled[style.rawValue] ?? true
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var hotkey: HotkeyKey = .rightOption
    public var handsFreeEnabled = true
    public var handsFreeLimitMinutes = 10
    public var soundsEnabled = true
    public var restoreClipboard = true
    public var launchAtLogin = false
    /// Master switch from the menu bar; per-style switches apply under it.
    public var cleanupEnabled = true
    public var historyRetention: Retention = .forever
    public var speech = SpeechSettings()
    public var textModel = TextModelSettings()
    public var styles = StyleSettings()

    public init() {}
}

// Tolerant decoding: a key that is missing or has a value this build does not
// understand keeps its default, so an older or newer settings.json never
// resets everything else.
extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

extension SpeechSettings {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        engine = c.value(.engine, default: engine)
        whisperModel = c.value(.whisperModel, default: whisperModel)
        language = c.value(.language, default: language)
        useVocabularyHints = c.value(.useVocabularyHints, default: useVocabularyHints)
        serverBaseURL = c.value(.serverBaseURL, default: serverBaseURL)
        serverModel = c.value(.serverModel, default: serverModel)
        microphoneUID = c.value(.microphoneUID, default: microphoneUID)
    }
}

extension TextModelSettings {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = c.value(.provider, default: provider)
        baseURL = c.value(.baseURL, default: baseURL)
        model = c.value(.model, default: model)
        timeoutSeconds = c.value(.timeoutSeconds, default: timeoutSeconds)
        disableThinking = c.value(.disableThinking, default: disableThinking)
        anthropicVersion = c.value(.anthropicVersion, default: anthropicVersion)
    }
}

extension StyleSettings {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cleanupEnabled = c.value(.cleanupEnabled, default: cleanupEnabled)
        appOverrides = c.value(.appOverrides, default: appOverrides)
        customRules = c.value(.customRules, default: customRules)
    }
}

extension AppSettings {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = c.value(.hotkey, default: hotkey)
        handsFreeEnabled = c.value(.handsFreeEnabled, default: handsFreeEnabled)
        handsFreeLimitMinutes = c.value(.handsFreeLimitMinutes, default: handsFreeLimitMinutes)
        soundsEnabled = c.value(.soundsEnabled, default: soundsEnabled)
        restoreClipboard = c.value(.restoreClipboard, default: restoreClipboard)
        launchAtLogin = c.value(.launchAtLogin, default: launchAtLogin)
        cleanupEnabled = c.value(.cleanupEnabled, default: cleanupEnabled)
        historyRetention = c.value(.historyRetention, default: historyRetention)
        speech = c.value(.speech, default: speech)
        textModel = c.value(.textModel, default: textModel)
        styles = c.value(.styles, default: styles)
    }
}
