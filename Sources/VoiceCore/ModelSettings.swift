import Foundation

public enum ConnectionKind: String, Codable, Sendable, CaseIterable {
    case openAICompatible, anthropicCompatible, openAI, anthropic, openRouter

    public var title: String {
        switch self {
        case .openAICompatible: "OpenAI-compatible"
        case .anthropicCompatible: "Anthropic-compatible"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .openRouter: "OpenRouter"
        }
    }

    public var usesAnthropicAPI: Bool { self == .anthropic || self == .anthropicCompatible }
    public var isCloud: Bool { self == .openAI || self == .anthropic || self == .openRouter }

    var idPrefix: String {
        switch self {
        case .openAICompatible: "server"
        case .anthropicCompatible: "anthropic-server"
        case .openAI: "openai"
        case .anthropic: "anthropic"
        case .openRouter: "openrouter"
        }
    }
}

/// Coding CLIs that can write meeting notes. Gemini is out of scope.
public enum CLITool: String, Codable, Sendable, CaseIterable {
    case claude, codex, pi

    public var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .pi: "Pi"
        }
    }
}

/// A model server. Its API key is in Keychain under `keychainAccount`.
public struct ModelConnection: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: ConnectionKind
    /// As typed. Ignored for kinds with a fixed address.
    public var baseURL: String
    /// Default model id; a feature may override it.
    public var model: String

    public init(id: String, name: String, kind: ConnectionKind, baseURL: String, model: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
    }

    public var keychainAccount: String { "connection-\(id)" }

    /// Lowercase ASCII letters, digits and `-`; never `cli-…`.
    public static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && !id.hasPrefix("cli-")
            && id.allSatisfy { $0 == "-" || ($0.isASCII && ($0.isLowercase || $0.isNumber)) }
    }

    public static func newID(for kind: ConnectionKind) -> String {
        kind.idPrefix + "-" + UUID().uuidString.prefix(6).lowercased()
    }
}

extension ModelConnection {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(ConnectionKind.self, forKey: .kind)
        name = c.value(.name, default: kind.title)
        baseURL = c.value(.baseURL, default: "")
        model = c.value(.model, default: "")
    }
}

/// How a feature reaches a model.
public enum ModelEngine: Codable, Equatable, Sendable, Hashable {
    case connection(String)
    case cli(CLITool)
    case appleIntelligence
    case none

    private enum Keys: String, CodingKey { case connection, cli }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            switch single {
            case "appleIntelligence": self = .appleIntelligence
            case "none": self = .none
            default:
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown engine \(single)"))
            }
            return
        }
        let c = try decoder.container(keyedBy: Keys.self)
        if let id = try c.decodeIfPresent(String.self, forKey: .connection) {
            self = .connection(id)
        } else {
            self = .cli(try c.decode(CLITool.self, forKey: .cli))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .connection(let id):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(id, forKey: .connection)
        case .cli(let tool):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(tool, forKey: .cli)
        case .appleIntelligence:
            var c = encoder.singleValueContainer()
            try c.encode("appleIntelligence")
        case .none:
            var c = encoder.singleValueContainer()
            try c.encode("none")
        }
    }
}

/// One feature's choice. An empty model means the connection's default; an
/// empty effort means the CLI's default.
public struct ModelUse: Codable, Equatable, Sendable {
    public var engine: ModelEngine
    public var model: String
    /// API engines: ask the server to skip reasoning.
    public var disableThinking: Bool
    /// CLI engines only.
    public var effort: String

    public init(engine: ModelEngine = .none, model: String = "", disableThinking: Bool = false, effort: String = "") {
        self.engine = engine
        self.model = model
        self.disableThinking = disableThinking
        self.effort = effort
    }
}

extension ModelUse {
    enum CodingKeys: String, CodingKey { case engine, model, disableThinking, effort }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        engine = (try? c.decodeIfPresent(ModelEngine.self, forKey: .engine)) ?? engine
        model = c.value(.model, default: model)
        disableThinking = c.value(.disableThinking, default: disableThinking)
        effort = c.value(.effort, default: effort)
    }

    /// CLIs are too slow for dictation.
    func withoutCLI() -> ModelUse {
        guard case .cli = engine else { return self }
        var copy = self
        copy.engine = .none
        return copy
    }
}

/// A Keychain item to copy once from the old single-key layout.
public struct KeyMove: Equatable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

public struct ModelSettings: Codable, Equatable, Sendable {
    public static let maxConnections = 20
    public static let defaultConnection = ModelConnection(
        id: "lmstudio", name: "LM Studio", kind: .openAICompatible,
        baseURL: "http://localhost:1234", model: "qwen3.8-27b-mlx"
    )

    public var connections: [ModelConnection] = [defaultConnection]
    public var dictation = ModelUse(engine: .connection("lmstudio"), disableThinking: true)
    /// Nil: same as Dictation.
    public var notes: ModelUse?
    public var meetings = ModelUse(engine: .connection("lmstudio"))
    /// Dictation and Notes: after this, raw text is pasted.
    public var dictationTimeoutSeconds: Double = 3
    /// Set by migration, done by the app at launch, never saved.
    public var pendingKeyMoves: [KeyMove] = []

    public init() {}

    enum CodingKeys: String, CodingKey {
        case connections, dictation, notes, meetings, dictationTimeoutSeconds
    }
}

extension ModelSettings {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.connections) {
            var seen = Set<String>()
            connections = Array(
                c.value(.connections, default: [LossyDictionaryElement<ModelConnection>]())
                    .compactMap(\.value)
                    .filter { ModelConnection.isValidID($0.id) && seen.insert($0.id).inserted }
                    .prefix(Self.maxConnections)
            )
        }
        // ModelUse falls back to `.none` for an engine it cannot read;
        // Dictation keeps its own default engine instead.
        let defaultDictationEngine = dictation.engine
        dictation = c.value(.dictation, default: dictation)
        if let use = try? c.nestedContainer(keyedBy: ModelUse.CodingKeys.self, forKey: .dictation),
           use.contains(.engine), (try? use.decode(ModelEngine.self, forKey: .engine)) == nil {
            dictation.engine = defaultDictationEngine
        }
        dictation = dictation.withoutCLI()
        notes = c.value(.notes, default: notes)?.withoutCLI()
        meetings = c.value(.meetings, default: meetings)
        dictationTimeoutSeconds = c.value(.dictationTimeoutSeconds, default: dictationTimeoutSeconds)
    }
}

public struct ConnectionPreset: Equatable, Sendable {
    public enum Group: Sendable { case local, cloud, custom }

    public var name: String
    public var kind: ConnectionKind
    public var baseURL: String
    public var needsKey: Bool
    public var group: Group

    public static let all: [ConnectionPreset] = [
        .init(name: "LM Studio", kind: .openAICompatible, baseURL: "http://localhost:1234", needsKey: false, group: .local),
        .init(name: "Ollama", kind: .openAICompatible, baseURL: "http://localhost:11434", needsKey: false, group: .local),
        .init(name: "MLX server", kind: .openAICompatible, baseURL: "http://localhost:8080", needsKey: false, group: .local),
        .init(name: "Anthropic", kind: .anthropic, baseURL: "https://api.anthropic.com", needsKey: true, group: .cloud),
        .init(name: "OpenAI", kind: .openAI, baseURL: "https://api.openai.com", needsKey: true, group: .cloud),
        .init(name: "OpenRouter", kind: .openRouter, baseURL: "https://openrouter.ai/api", needsKey: true, group: .cloud),
        .init(name: "OpenAI-compatible server", kind: .openAICompatible, baseURL: "https://", needsKey: true, group: .custom),
        .init(name: "Anthropic-compatible server", kind: .anthropicCompatible, baseURL: "https://", needsKey: true, group: .custom),
    ]
}

/// `textModel` (one provider, one key) → `ModelSettings`.
public enum LegacyTextModelMigration {
    public static func migrate(_ old: TextModelSettings) -> ModelSettings {
        var s = ModelSettings()
        s.dictationTimeoutSeconds = old.timeoutSeconds
        let engine: ModelEngine
        switch old.provider {
        case .none:
            s.connections = []
            engine = .none
        case .appleIntelligence:
            s.connections = []
            engine = .appleIntelligence
        case .openAICompatible:
            let name = ConnectionPreset.all
                .first { $0.group == .local && $0.baseURL == old.baseURL }?.name ?? "OpenAI-compatible server"
            s.connections = [ModelConnection(id: "migrated-1", name: name, kind: .openAICompatible, baseURL: old.baseURL, model: old.model)]
            s.pendingKeyMoves = [KeyMove(from: "openai", to: "connection-migrated-1")]
            engine = .connection("migrated-1")
        case .anthropicCompatible:
            let official = URL(string: old.baseURL)?.host?.lowercased() == "api.anthropic.com"
            s.connections = [ModelConnection(
                id: "migrated-1", name: official ? "Anthropic" : "Anthropic-compatible server",
                kind: official ? .anthropic : .anthropicCompatible, baseURL: old.baseURL, model: old.model
            )]
            s.pendingKeyMoves = [KeyMove(from: "anthropic", to: "connection-migrated-1")]
            engine = .connection("migrated-1")
        }
        s.dictation = ModelUse(engine: engine, disableThinking: old.disableThinking)
        s.meetings = ModelUse(engine: engine)
        s.notes = nil
        return s
    }
}

public enum ModelNames {
    /// A short label for the HUD, e.g. *Cleaning (Qwen)*: the model id's
    /// leading word, capitalized, without an organization prefix.
    public static func short(_ modelID: String) -> String? {
        let id = modelID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return nil }
        let base = id.split(separator: "/").last.map(String.init) ?? id
        let word = base.prefix { $0.isLetter }
        guard !word.isEmpty else { return id }
        return word.prefix(1).uppercased() + word.dropFirst()
    }
}
