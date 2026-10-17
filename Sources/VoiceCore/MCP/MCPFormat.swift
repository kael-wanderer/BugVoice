import Foundation

/// A tool error: one plain sentence for the agent.
public struct MCPFailure: Error, Equatable, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// Turns notes, meetings and Ask results into what tools return.
public enum MCPFormat {
    /// Transcript lines per `get_meeting` call.
    public static let transcriptPage = 1500

    /// ISO 8601 with the local offset.
    public static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f.string(from: date)
    }

    /// Pretty JSON with sorted keys.
    public static func json(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Notes

    public static func note(title: String, folder: String?, tags: [String], modified: Date, body: String, unsaved: Bool) -> String {
        var header = "Folder: \(folder ?? "Unfiled") · Tags: \(tags.isEmpty ? "none" : tags.joined(separator: ", ")) · Modified: \(iso(modified))"
        if unsaved { header += " · Unsaved changes included." }
        return "# \(title)\n\(header)\n\n\(body)"
    }

    // MARK: Meetings

    /// Speaker labels in the order they first speak.
    public static func people(_ m: MeetingManifest) -> [String] {
        var seen: Set<String> = []
        return ordered(m.segments).map(\.speaker).filter { seen.insert($0).inserted }
    }

    public static func meeting(_ m: MeetingManifest, folder: String?, parts: Set<MCPMeetingPart>, fromLine: Int) -> String {
        var header = "Date: \(iso(m.startedAt)) · Duration: \(clock(m.duration))"
        let names = people(m)
        if !names.isEmpty { header += " · People: \(names.joined(separator: ", "))" }
        header += " · Folder: \(folder ?? "Unfiled")"
        var out = ["# \(m.title)", header]

        let texts: [(MCPMeetingPart, String, String?, String)] = [
            (.summary, "Summary", m.summary, "No summary yet."),
            (.actionItems, "Action items", m.actionItems, "No action items yet."),
            (.myNotes, "My notes", m.notes, "No notes."),
        ]
        for (part, title, text, empty) in texts where parts.contains(part) {
            let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            out += ["", "## \(title)", "", trimmed.isEmpty ? empty : trimmed]
        }

        if parts.contains(.transcript) {
            out += ["", "## Transcript", ""]
            let segments = ordered(m.segments)
            let start = max(1, fromLine)
            let page = segments.dropFirst(start - 1).prefix(transcriptPage)
            if segments.isEmpty {
                out.append("No transcript yet.")
            } else if page.isEmpty {
                out.append("No lines from \(start). The transcript has \(segments.count) lines.")
            }
            for s in page {
                out.append("[\(clock(s.start))] \(s.speaker): \(s.text)")
                if let t = s.translation, !t.isEmpty { out.append("    English: \(t)") }
            }
            let next = start + page.count
            if next <= segments.count { out.append("More: call get_meeting with from_line \(next).") }
        }
        return out.joined(separator: "\n")
    }

    /// `m:ss` as in the app's transcript view; `h:mm:ss` from one hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        if whole >= 3_600 { return String(format: "%d:%02d:%02d", whole / 3_600, whole / 60 % 60, whole % 60) }
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    private static func ordered(_ segments: [MeetingSegment]) -> [MeetingSegment] {
        segments.enumerated().sorted {
            $0.element.start != $1.element.start ? $0.element.start < $1.element.start : $0.offset < $1.offset
        }.map(\.element)
    }

    // MARK: Search and Ask

    /// The id and kind an agent sees for one Ask source.
    public static func item(_ source: AskSource, info: AskItemInfo?) -> (id: String, kind: String) {
        switch source {
        case .meeting(let id): (id.rawValue, info?.kind == .uploaded ? "upload" : "meeting")
        case .note(let id): (id.rawValue, "note")
        case .dictations: ("dictations", "dictation")
        }
    }

    public static func searchResult(_ result: AskSearchResult, info: [AskSource: AskItemInfo]) -> JSONValue {
        let passages: [JSONValue] = result.passages.map { p in
            let item = item(p.source, info: info[p.source])
            var o: [String: JSONValue] = [
                "item_id": .string(item.id), "item_kind": .string(item.kind),
                "title": .string(info[p.source]?.title ?? ""), "date": .string(iso(p.date)),
                "text": .string(p.searchText),
            ]
            if let start = p.lines.first?.start { o["start"] = .number(start) }
            if let end = p.lines.last?.end { o["end"] = .number(end) }
            if p.part == .transcript, let speaker = p.lines.first?.speaker { o["speaker"] = .string(speaker) }
            return .object(o)
        }
        var out: [String: JSONValue] = ["passages": .array(passages)]
        if result.wordSearchOnly != nil { out["word_search_only"] = .bool(true) }
        return .object(out)
    }

    public static func askResult(_ outcome: AskOutcome, meetings: Int, notes: Int, dictations: Int) -> Result<JSONValue, MCPFailure> {
        switch outcome {
        case .failed(let failure):
            return .failure(MCPFailure(failure.message))
        case .nothingFound(let wordOnly):
            var out: [String: JSONValue] = ["nothing_found": .bool(true)]
            if wordOnly != nil { out["word_search_only"] = .bool(true) }
            return .success(.object(out))
        case .answered(let result, let wordOnly):
            let cards: [JSONValue] = result.cards.map { card in
                let item = item(card.source, info: card.info)
                let citations: [JSONValue] = card.citations.map { c in
                    var o: [String: JSONValue] = ["quote": .string(c.lines.map(\.text).joined(separator: "\n"))]
                    if let start = c.start { o["start"] = .number(start) }
                    if let end = c.end { o["end"] = .number(end) }
                    if c.part == .transcript, let speaker = c.lines.first?.speaker { o["speaker"] = .string(speaker) }
                    return .object(o)
                }
                return .object([
                    "item_id": .string(item.id), "item_kind": .string(item.kind),
                    "title": .string(card.info.title), "date": .string(iso(card.info.date)),
                    "people": .array(card.info.people.map { .string($0) }),
                    "citations": .array(citations),
                ])
            }
            var out: [String: JSONValue] = [
                "answer": .string(result.answer),
                "cards": .array(cards),
                "searched": .object([
                    "meetings": .number(Double(meetings)), "notes": .number(Double(notes)),
                    "dictations": .number(Double(dictations)),
                ]),
            ]
            if wordOnly != nil { out["word_search_only"] = .bool(true) }
            return .success(.object(out))
        }
    }
}
