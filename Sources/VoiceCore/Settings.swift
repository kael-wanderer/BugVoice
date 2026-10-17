import Foundation

public enum Style: String, Codable, Sendable, CaseIterable {
    case personal, work, email, document, terminal, other

    public var title: String {
        switch self {
        case .personal: "Personal messages"
        case .work: "Work messages"
        case .email: "Email"
        case .document: "Document"
        case .terminal: "Terminal"
        case .other: "Other"
        }
    }
}

extension Style {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "chat" {
            self = .personal
        } else if let style = Style(rawValue: raw) {
            self = style
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown style \(raw)"))
        }
    }
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

public enum MeetingRetentionPolicy: String, Codable, Sendable, CaseIterable {
    case never, days30, days90, year

    public var maxAge: TimeInterval? {
        switch self {
        case .never: nil
        case .days30: 30 * 86_400
        case .days90: 90 * 86_400
        case .year: 365 * 86_400
        }
    }
}

public struct MeetingSettings: Codable, Equatable, Sendable {
    public var deleteAfter: MeetingRetentionPolicy = .never
    public var generationContextTokens = 8_192
    public var generationOutputTokens = 2_048
    /// Languages spoken in meetings and uploads. Always normalized and never empty.
    public var languages: [SpeechLanguage] = MeetingLanguages.defaults {
        didSet { if languages != MeetingLanguages.normalized(languages) { languages = MeetingLanguages.normalized(languages) } }
    }
    /// Offer to record when a meeting app starts using the microphone.
    public var detectMeetings = true
    /// Bundle IDs chosen with "Don't ask for this app".
    public var mutedMeetingApps: [String] = []
    /// The meeting window shows only its top bar.
    public var windowCollapsed = false
    /// Seconds of meeting time between live summary refreshes; one of `LiveSummaryPlanner.intervalChoices`.
    public var liveSummaryInterval = LiveSummaryPlanner.defaultInterval {
        didSet {
            let normalized = LiveSummaryPlanner.normalizedInterval(liveSummaryInterval)
            if liveSummaryInterval != normalized { liveSummaryInterval = normalized }
        }
    }

    /// Suggest names for call speakers from voices named in earlier meetings, and save them.
    public var suggestKnownVoices = true

    public init() {}
}

extension MeetingSettings {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deleteAfter = c.value(.deleteAfter, default: deleteAfter)
        generationContextTokens = c.value(.generationContextTokens, default: generationContextTokens)
        generationOutputTokens = c.value(.generationOutputTokens, default: generationOutputTokens)
        languages = MeetingLanguages.normalized(c.value(.languages, default: languages))
        detectMeetings = c.value(.detectMeetings, default: detectMeetings)
        mutedMeetingApps = c.value(.mutedMeetingApps, default: mutedMeetingApps)
        windowCollapsed = c.value(.windowCollapsed, default: windowCollapsed)
        liveSummaryInterval = LiveSummaryPlanner.normalizedInterval(c.value(.liveSummaryInterval, default: liveSummaryInterval))
        suggestKnownVoices = c.value(.suggestKnownVoices, default: suggestKnownVoices)
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

/// The selected provider settings and credential version that determine the
/// live speech transcriber. Inactive provider settings, language, vocabulary
/// hints, and microphone selection do not change the provider instance.
public struct SpeechTranscriberConfiguration: Equatable, Sendable {
    public let engine: SpeechEngine
    public let whisperModel: String
    public let serverBaseURL: String
    public let serverModel: String
    public let speechAPIKeyGeneration: UInt64

    public init(settings: SpeechSettings, speechAPIKeyGeneration: UInt64) {
        engine = settings.engine
        let usesWhisperKit = settings.engine == .whisperKit
        let usesOpenAICompatible = settings.engine == .openAICompatible
        whisperModel = usesWhisperKit ? settings.whisperModel : ""
        serverBaseURL = usesOpenAICompatible ? settings.serverBaseURL : ""
        serverModel = usesOpenAICompatible ? settings.serverModel : ""
        self.speechAPIKeyGeneration = usesOpenAICompatible ? speechAPIKeyGeneration : 0
    }
}

/// The old single text-model setting. Read once to migrate into `ModelSettings`.
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

/// Which folder each page shows. "all", "unfiled" or a folder id.
public struct LibrarySettings: Codable, Equatable, Sendable {
    public var meetingsFolderFilter = "all"
    public var notesFolderFilter = "all"

    public init() {}
}

extension LibrarySettings {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meetingsFolderFilter = c.value(.meetingsFolderFilter, default: meetingsFolderFilter)
        notesFolderFilter = c.value(.notesFolderFilter, default: notesFolderFilter)
    }
}

public enum NoteViewMode: String, Codable, Sendable, CaseIterable {
    case markdown, doc

    public var title: String {
        switch self {
        case .markdown: "Markdown"
        case .doc: "Doc"
        }
    }
}

/// The bar under the editor in the Scratchpad window.
public enum ScratchpadBottomBar: String, Codable, Sendable, CaseIterable {
    case ai, formatting
}

/// Order of the Scratchpad cards and the window's note list. Pinned notes come first.
public enum NotesSort: String, Codable, Sendable, CaseIterable {
    case editedNewest, editedOldest, title

    public var title: String {
        switch self {
        case .editedNewest: "Last edited, newest first"
        case .editedOldest: "Last edited, oldest first"
        case .title: "Title A–Z"
        }
    }
}

/// Open Scratchpad tabs by note slug, the view every note uses, and the
/// Scratchpad window's layout.
public struct ScratchpadSettings: Codable, Equatable, Sendable {
    public var openTabs: [String] = []
    public var activeTab: String?
    public var view: NoteViewMode = .markdown
    public var keepOnTop = true
    public var sideListHidden = false
    public var compact = false
    public var bottomBar: ScratchpadBottomBar = .ai
    public var sort: NotesSort = .editedNewest

    public init() {}
}

extension ScratchpadSettings {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        openTabs = c.value(.openTabs, default: openTabs)
        activeTab = c.value(.activeTab, default: activeTab)
        view = c.value(.view, default: view)
        keepOnTop = c.value(.keepOnTop, default: keepOnTop)
        sideListHidden = c.value(.sideListHidden, default: sideListHidden)
        compact = c.value(.compact, default: compact)
        bottomBar = c.value(.bottomBar, default: bottomBar)
        sort = c.value(.sort, default: sort)
    }
}

/// Settings › Agents: the MCP server and what connected agents may change.
public struct AgentSettings: Codable, Equatable, Sendable {
    public var mcpEnabled = false
    public var allowNoteEdits = true
    public var allowUploads = true

    public init(mcpEnabled: Bool = false, allowNoteEdits: Bool = true, allowUploads: Bool = true) {
        self.mcpEnabled = mcpEnabled
        self.allowNoteEdits = allowNoteEdits
        self.allowUploads = allowUploads
    }
}

extension AgentSettings {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mcpEnabled = c.value(.mcpEnabled, default: mcpEnabled)
        allowNoteEdits = c.value(.allowNoteEdits, default: allowNoteEdits)
        allowUploads = c.value(.allowUploads, default: allowUploads)
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
    public var meetings = MeetingSettings()
    public var speech = SpeechSettings()
    public var models = ModelSettings()
    public var styles = StyleSettings()
    public var library = LibrarySettings()
    public var scratchpad = ScratchpadSettings()
    public var agents = AgentSettings()

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
        // Decoded as strings so one unknown style drops only its own entry.
        let rawOverrides: [String: String] = c.value(.appOverrides, default: [:])
        appOverrides = rawOverrides.reduce(into: [:]) { result, entry in
            if entry.value == Self.legacyChat {
                result[entry.key] = StyleRouter.defaultApps[entry.key] == .work ? .work : .personal
            } else if let style = Style(rawValue: entry.value) {
                result[entry.key] = style
            }
        }
        customRules = c.value(.customRules, default: customRules)
        Self.splitLegacyChat(&cleanupEnabled)
        Self.splitLegacyChat(&customRules)
    }

    static let legacyChat = "chat"

    static func splitLegacyChat<Value>(_ values: inout [String: Value]) {
        guard let value = values.removeValue(forKey: legacyChat) else { return }
        for style in [Style.personal, .work] where values[style.rawValue] == nil {
            values[style.rawValue] = value
        }
    }
}

extension AppSettings {
    private enum LegacyKeys: String, CodingKey { case textModel }
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
        meetings = c.value(.meetings, default: meetings)
        speech = c.value(.speech, default: speech)
        if c.contains(.models) {
            models = c.value(.models, default: models)
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(TextModelSettings.self, forKey: .textModel) {
            models = LegacyTextModelMigration.migrate(legacy)
        }
        styles = c.value(.styles, default: styles)
        library = c.value(.library, default: library)
        scratchpad = c.value(.scratchpad, default: scratchpad)
        agents = c.value(.agents, default: agents)
    }
}
