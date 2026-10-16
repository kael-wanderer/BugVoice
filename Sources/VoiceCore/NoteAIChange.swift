import Foundation

/// What produced an AI change: a chip or a message in the AI box.
public enum NoteAIChangeKind: Equatable, Sendable {
    case transform(NoteTransform)
    case instruction(String)

    /// History row title, e.g. "Before Polish" or "Before “shorter, add a greeting”".
    public var historyTitle: String {
        switch self {
        case .transform(let transform):
            return "Before \(transform.title)"
        case .instruction(let message):
            let flat = message.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return "Before “\(flat.count > 40 ? String(flat.prefix(40)) + "…" : flat)”"
        }
    }

    /// Notice after the change, e.g. "Polished · 28 words".
    /// "1 word", "2 words".
    public static func wordsLabel(_ count: Int) -> String {
        count == 1 ? "1 word" : "\(count) words"
    }

    public func notice(words: Int) -> String {
        switch self {
        case .transform(let transform): "\(transform.doneTitle) · \(Self.wordsLabel(words))"
        case .instruction: "Changed · \(Self.wordsLabel(words))"
        }
    }
}

/// The last AI change in a note, kept so Run again can redo it.
public struct NoteAIChange: Equatable, Sendable {
    public let noteID: NoteID
    public let kind: NoteAIChangeKind
    /// The input text before the change.
    public let original: String
    /// Where the result sits in the body now.
    public let range: NotesTextRange
    /// The note's revision right after the change.
    public let revision: UInt64

    public init(noteID: NoteID, kind: NoteAIChangeKind, original: String, range: NotesTextRange, revision: UInt64) {
        self.noteID = noteID
        self.kind = kind
        self.original = original
        self.range = range
        self.revision = revision
    }

    /// Only while the same note is unchanged since.
    public func canRunAgain(noteID: NoteID, revision: UInt64) -> Bool {
        self.noteID == noteID && self.revision == revision
    }
}

/// One version kept before an AI change.
public struct NoteAIHistoryEntry: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let body: String
    public let date: Date

    public init(id: UUID = UUID(), title: String, body: String, date: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.date = date
    }

    public var words: Int { NoteTransformPrompt.wordCount(body) }
    public var wordsLabel: String { NoteAIChangeKind.wordsLabel(words) }
}

/// Versions before AI changes, per note, newest first. Memory only.
public struct NoteAIHistory: Equatable, Sendable {
    public static let limit = 20
    private var entries: [NoteID: [NoteAIHistoryEntry]] = [:]

    public init() {}

    public mutating func add(_ entry: NoteAIHistoryEntry, to noteID: NoteID) {
        var list = entries[noteID] ?? []
        list.insert(entry, at: 0)
        entries[noteID] = Array(list.prefix(Self.limit))
    }

    public func entries(for noteID: NoteID) -> [NoteAIHistoryEntry] {
        entries[noteID] ?? []
    }
}
