import Foundation

public enum AskSource: Hashable, Sendable {
    case meeting(MeetingID)
    case note(NoteID)
    case dictations

    var key: String {
        switch self {
        case .meeting(let id): "meeting-\(id.rawValue)"
        case .note(let id): "note-\(id.rawValue)"
        case .dictations: "dictations"
        }
    }
}

public enum AskPart: String, Codable, Sendable {
    case transcript, summary, actionItems, myNotes, note, title, dictation
}

public struct AskLine: Hashable, Sendable {
    public var id: String
    public var start: Double?
    public var end: Double?
    public var speaker: String?
    public var text: String
    public var translation: String?

    public init(
        id: String, start: Double? = nil, end: Double? = nil, speaker: String? = nil,
        text: String, translation: String? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.speaker = speaker
        self.text = text
        self.translation = translation
    }
}

public struct AskPassage: Hashable, Sendable, Identifiable {
    public var id: String
    public var source: AskSource
    public var part: AskPart
    public var date: Date
    public var lines: [AskLine]
    public var searchText: String
    public var contentHash: String

    public init(source: AskSource, part: AskPart, index: Int, date: Date, lines: [AskLine]) {
        self.id = "\(source.key)#\(part.rawValue)#\(index)"
        self.source = source
        self.part = part
        self.date = date
        self.lines = lines
        let text = lines.flatMap { line -> [String] in
            if let t = line.translation, !t.isEmpty { return [line.text, t] }
            return [line.text]
        }.joined(separator: "\n")
        self.searchText = text
        self.contentHash = AskPassageBuilder.fnv1a(text)
    }
}

public enum AskPassageBuilder {
    public static let maxSegments = 6, maxSeconds = 60.0, maxBlockCharacters = 800

    public static func passages(meeting: MeetingManifest) -> [AskPassage] {
        guard meeting.state == .ready else { return [] }
        let source = AskSource.meeting(meeting.id)
        let date = meeting.startedAt
        var out = transcriptPassages(meeting.segments, source: source, date: date)
        let texts: [(AskPart, String?)] = [
            (.summary, meeting.summary), (.actionItems, meeting.actionItems), (.myNotes, meeting.notes),
        ]
        for (part, text) in texts {
            out += textPassages(text ?? "", source: source, part: part, date: date)
        }
        return out
    }

    public static func passages(note: NoteDocument) -> [AskPassage] {
        let source = AskSource.note(note.id)
        var out: [AskPassage] = []
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            out.append(AskPassage(
                source: source, part: .title, index: 0, date: note.modifiedAt,
                lines: [AskLine(id: "b0.0", text: title)]))
        }
        return out + textPassages(note.body, source: source, part: .note, date: note.modifiedAt)
    }

    public static func passages(dictations: [HistoryEntry]) -> [AskPassage] {
        dictations.compactMap { entry in
            guard !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let line = AskLine(id: entry.id.uuidString, speaker: entry.appName, text: entry.text)
            return AskPassage(
                source: .dictations, part: .dictation, index: 0, date: entry.startedAt, lines: [line])
                .withIndexSuffix(entry.id.uuidString)
        }
    }

    /// FNV-1a 64-bit over UTF-8, lowercase 16-character hex.
    public static func fnv1a(_ s: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    // MARK: Transcript

    private static func transcriptPassages(_ segments: [MeetingSegment], source: AskSource, date: Date) -> [AskPassage] {
        let sorted = segments.enumerated().sorted {
            $0.element.start != $1.element.start ? $0.element.start < $1.element.start : $0.offset < $1.offset
        }.map(\.element)
        var out: [AskPassage] = []
        var begin = 0
        while begin < sorted.count {
            var end = begin + 1
            while end < sorted.count, end - begin < maxSegments,
                sorted[end].end - sorted[begin].start <= maxSeconds
            {
                end += 1
            }
            let lines = sorted[begin..<end].map {
                AskLine(
                    id: $0.id, start: $0.start, end: $0.end, speaker: $0.speaker,
                    text: $0.text, translation: $0.translation)
            }
            out.append(AskPassage(source: source, part: .transcript, index: out.count, date: date, lines: lines))
            if end >= sorted.count { break }
            begin = end - 1 > begin ? end - 1 : end
        }
        return out
    }

    // MARK: Text blocks

    private static func textPassages(_ text: String, source: AskSource, part: AskPart, date: Date) -> [AskPassage] {
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.split(separator: "\n", omittingEmptySubsequences: true).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        var out: [AskPassage] = []
        var current: [AskLine] = []
        var size = 0
        func flush() {
            guard !current.isEmpty else { return }
            out.append(AskPassage(source: source, part: part, index: out.count, date: date, lines: current))
            current = []
            size = 0
        }
        func add(_ line: AskLine) {
            let cost = line.text.count + (current.isEmpty ? 0 : 1)
            if size + cost > maxBlockCharacters { flush() }
            size += line.text.count + (current.isEmpty ? 0 : 1)
            current.append(line)
        }
        var blockIndex = 0
        for lines in blocks where !lines.isEmpty {
            var pieces: [String] = []
            for l in lines {
                var rest = Substring(l)
                while rest.count > maxBlockCharacters {
                    pieces.append(String(rest.prefix(maxBlockCharacters)))
                    rest = rest.dropFirst(maxBlockCharacters)
                }
                pieces.append(String(rest))
            }
            let blockSize = pieces.map(\.count).reduce(0, +) + pieces.count - 1
            if blockSize <= maxBlockCharacters, size + blockSize + (current.isEmpty ? 0 : 1) > maxBlockCharacters {
                flush()
            }
            for (i, p) in pieces.enumerated() { add(AskLine(id: "b\(blockIndex).\(i)", text: p)) }
            blockIndex += 1
        }
        flush()
        return out
    }
}

private extension AskPassage {
    /// Dictation ids carry the entry id so they stay unique and stable per entry.
    func withIndexSuffix(_ suffix: String) -> AskPassage {
        var copy = self
        copy.id = "\(source.key)#\(part.rawValue)#\(suffix)"
        return copy
    }
}
