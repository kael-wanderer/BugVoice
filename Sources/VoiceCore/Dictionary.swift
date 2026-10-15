import Foundation

public struct DictionaryWord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var word: String
    public var heardAs: [String]

    public init(id: UUID = UUID(), word: String, heardAs: [String] = []) {
        self.id = id
        self.word = word
        self.heardAs = heardAs
    }
}

public struct Snippet: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var trigger: String
    public var text: String

    public init(id: UUID = UUID(), trigger: String, text: String) {
        self.id = id
        self.trigger = trigger
        self.text = text
    }
}

public enum DictionaryError: Error, Equatable, LocalizedError {
    case emptyTrigger, emptyText, duplicateTrigger

    public var errorDescription: String? {
        switch self {
        case .emptyTrigger: "Enter a trigger phrase."
        case .emptyText: "Enter the text to insert."
        case .duplicateTrigger: "A snippet with this trigger already exists."
        }
    }
}

/// Contents of `dictionary.json`. Both lists are newest first.
public struct DictionaryFile: Codable, Equatable, Sendable {
    public static let supportedSchemaVersion = 1

    public var schemaVersion = DictionaryFile.supportedSchemaVersion
    public var words: [DictionaryWord] = []
    public var snippets: [Snippet] = []

    public init(words: [DictionaryWord] = [], snippets: [Snippet] = []) {
        self.words = words
        self.snippets = snippets
    }

    /// From `vocabulary.txt`: terms become words, `spoken => written` lines become snippets.
    public init(migrating vocabulary: Vocabulary) {
        self.init()
        for term in vocabulary.terms { insertWord(term) }
        for replacement in vocabulary.replacements {
            _ = try? addSnippet(trigger: replacement.spoken, text: replacement.written)
        }
    }
}

extension DictionaryWord {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        word = try c.decode(String.self, forKey: .word)
        heardAs = c.value(.heardAs, default: [])
    }
}

extension Snippet {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        trigger = try c.decode(String.self, forKey: .trigger)
        text = try c.decode(String.self, forKey: .text)
    }
}

extension DictionaryFile {
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.value(.schemaVersion, default: schemaVersion)
        words = c.value(.words, default: [LossyDictionaryElement<DictionaryWord>]()).compactMap(\.value)
        snippets = c.value(.snippets, default: [LossyDictionaryElement<Snippet>]()).compactMap(\.value)
    }
}

struct LossyDictionaryElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) {
        value = try? Value(from: decoder)
    }
}

extension DictionaryFile {
    static func key(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parts(_ text: String) -> [String] {
        text.split(separator: ",").map { trimmed(String($0)) }.filter { !$0.isEmpty }
    }

    @discardableResult
    public mutating func addWords(_ text: String) -> Int {
        var seen = Set(words.map { Self.key($0.word) })
        let added = Self.parts(text)
            .filter { seen.insert(Self.key($0)).inserted }
            .map { DictionaryWord(word: $0) }
        words.insert(contentsOf: added, at: 0)
        return added.count
    }

    mutating func insertWord(_ text: String) {
        let word = Self.trimmed(text)
        guard !word.isEmpty, !words.contains(where: { Self.key($0.word) == Self.key(word) }) else { return }
        words.insert(DictionaryWord(word: word), at: 0)
    }

    public mutating func addHeardAs(_ text: String, to id: DictionaryWord.ID) {
        guard let i = words.firstIndex(where: { $0.id == id }) else { return }
        var seen = Set(words[i].heardAs.map(Self.key))
        seen.insert(Self.key(words[i].word))
        for form in Self.parts(text) where seen.insert(Self.key(form)).inserted {
            words[i].heardAs.append(form)
        }
    }

    public mutating func removeHeardAs(_ form: String, from id: DictionaryWord.ID) {
        guard let i = words.firstIndex(where: { $0.id == id }) else { return }
        words[i].heardAs.removeAll { Self.key($0) == Self.key(form) }
    }

    @discardableResult
    public mutating func renameWord(_ id: DictionaryWord.ID, to text: String) -> Bool {
        let word = Self.trimmed(text)
        guard !word.isEmpty,
              let i = words.firstIndex(where: { $0.id == id }),
              !words.contains(where: { $0.id != id && Self.key($0.word) == Self.key(word) })
        else { return false }
        words[i].word = word
        words[i].heardAs.removeAll { Self.key($0) == Self.key(word) }
        return true
    }

    public mutating func deleteWord(_ id: DictionaryWord.ID) {
        words.removeAll { $0.id == id }
    }

    @discardableResult
    public mutating func addSnippet(trigger: String, text: String) throws -> Snippet {
        let (trigger, text) = try validated(trigger: trigger, text: text, excluding: nil)
        let snippet = Snippet(trigger: trigger, text: text)
        snippets.insert(snippet, at: 0)
        return snippet
    }

    public mutating func updateSnippet(_ id: Snippet.ID, trigger: String, text: String) throws {
        guard let i = snippets.firstIndex(where: { $0.id == id }) else { return }
        let (trigger, text) = try validated(trigger: trigger, text: text, excluding: id)
        snippets[i].trigger = trigger
        snippets[i].text = text
    }

    public mutating func deleteSnippet(_ id: Snippet.ID) {
        snippets.removeAll { $0.id == id }
    }

    private func validated(trigger: String, text: String, excluding id: Snippet.ID?) throws -> (String, String) {
        let trigger = Self.trimmed(trigger)
        let text = Self.trimmed(text)
        guard !trigger.isEmpty else { throw DictionaryError.emptyTrigger }
        guard !text.isEmpty else { throw DictionaryError.emptyText }
        guard !snippets.contains(where: { $0.id != id && Self.key($0.trigger) == Self.key(trigger) }) else {
            throw DictionaryError.duplicateTrigger
        }
        return (trigger, text)
    }
}
