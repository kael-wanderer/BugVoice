import Foundation

public struct Suggestion: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var written: String
    public var heard: String
    public var app: String?
    public var count: Int
    public var lastSeen: Date
    public var replace: Bool

    public init(id: UUID = UUID(), written: String, heard: String, app: String? = nil,
                count: Int = 1, lastSeen: Date = Date(), replace: Bool = true) {
        self.id = id; self.written = written; self.heard = heard; self.app = app
        self.count = count; self.lastSeen = lastSeen; self.replace = replace
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        written = try c.decode(String.self, forKey: .written)
        heard = try c.decode(String.self, forKey: .heard)
        app = c.value(.app, default: nil)
        count = max(1, c.value(.count, default: 1))
        lastSeen = c.value(.lastSeen, default: Date())
        replace = c.value(.replace, default: true)
    }
}

public struct DismissedPair: Codable, Hashable, Sendable {
    public var written: String
    public var heard: String
    public init(written: String, heard: String) { self.written = written; self.heard = heard }
}

public struct SuggestionFile: Codable, Equatable, Sendable {
    public static let supportedSchemaVersion = 1
    public static let maxPending = 50
    public static let maxDismissed = 500
    public var schemaVersion = supportedSchemaVersion
    public var pending: [Suggestion] = []
    public var dismissed: [DismissedPair] = []
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.value(.schemaVersion, default: Self.supportedSchemaVersion)
        pending = Array(c.value(.pending, default: [LossyDictionaryElement<Suggestion>]()).compactMap(\.value)
            .sorted { $0.lastSeen > $1.lastSeen }.prefix(Self.maxPending))
        dismissed = Array(c.value(.dismissed, default: [LossyDictionaryElement<DismissedPair>]()).compactMap(\.value).suffix(Self.maxDismissed))
    }
    private func same(_ written: String, _ heard: String, _ w: String, _ h: String) -> Bool {
        written == w && DictionaryFile.key(heard) == DictionaryFile.key(h)
    }
    public mutating func record(_ candidate: CorrectionCandidate, app: String?, at: Date,
                                dictionary: DictionaryFile, isRealWord: (String) -> Bool) {
        let w = candidate.written, h = candidate.heard
        guard !dismissed.contains(where: { same(w, h, $0.written, $0.heard) }),
              !dictionary.words.contains(where: { word in
                  word.word == w && word.heardAs.contains { DictionaryFile.key($0) == DictionaryFile.key(h) }
              }) else { return }
        var suggestion: Suggestion
        if let i = pending.firstIndex(where: { same(w, h, $0.written, $0.heard) }) {
            suggestion = pending.remove(at: i)
            suggestion.count += 1; suggestion.lastSeen = at; suggestion.app = app
        } else {
            suggestion = Suggestion(written: w, heard: h, app: app, lastSeen: at,
                                    replace: !(isRealWord(h) && isRealWord(w)))
        }
        pending.insert(suggestion, at: 0)
        pending = Array(pending.prefix(Self.maxPending))
    }
    public mutating func dismiss(id: UUID) {
        guard let s = pending.first(where: { $0.id == id }) else { return }
        remove(id: id)
        if !dismissed.contains(where: { same(s.written, s.heard, $0.written, $0.heard) }) {
            dismissed.append(.init(written: s.written, heard: s.heard))
            dismissed = Array(dismissed.suffix(Self.maxDismissed))
        }
    }
    public mutating func setReplace(id: UUID, _ on: Bool) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[i].replace = on
    }
    public mutating func remove(id: UUID) { pending.removeAll { $0.id == id } }
}

extension DictionaryFile {
    public mutating func accept(_ suggestion: Suggestion) {
        insertWord(suggestion.written)
        guard suggestion.replace,
              let i = words.firstIndex(where: { Self.key($0.word) == Self.key(suggestion.written) }),
              !words[i].heardAs.contains(where: { Self.key($0) == Self.key(suggestion.heard) }),
              Self.key(words[i].word) != Self.key(suggestion.heard) else { return }
        words[i].heardAs.append(suggestion.heard)
    }
}

public actor SuggestionStore {
    public let url: URL
    private var lastRevision = Int.min

    public init(url: URL) { self.url = url }

    public func load() -> SuggestionFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return SuggestionFile() }
        guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(SuggestionFile.self, from: data) else {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("suggestions.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return SuggestionFile()
        }
        return file
    }

    /// Saves older than the last revision written are ignored.
    public func save(_ file: SuggestionFile, revision: Int? = nil) throws {
        if let revision {
            guard revision > lastRevision else { return }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
        if let revision { lastRevision = revision }
    }
}
