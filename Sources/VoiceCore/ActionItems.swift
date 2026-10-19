import Foundation

public struct ActionItem: Equatable, Sendable, Identifiable {
    public var meetingID: MeetingID
    public var text: String
    public var owner: String?
    public var key: String
    public var id: String { meetingID.rawValue + "|" + key }
}

public struct ParsedActionItems: Equatable, Sendable {
    public var items: [ActionItem]
    public var otherLines: [String]
}

public enum ActionItemParser {
    private static let marker = #"^\s*(?:[-*•]|\d+[.)])\s+"#
    private static let name = #"\p{Lu}\p{L}*(?: \p{Lu}\p{L}*){0,2}"#
    private static let excluded: Set<String> = ["note", "follow up", "next step", "next steps", "todo", "action", "decision", "owner"]

    private static func cleaned(_ line: String) -> String {
        line.replacingOccurrences(of: marker, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\[[ xX]\]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    public static func key(_ line: String) -> String { cleaned(line).lowercased() }

    public static func parse(_ markdown: String?, meetingID: MeetingID) -> ParsedActionItems {
        var result = ParsedActionItems(items: [], otherLines: [])
        for raw in (markdown ?? "").components(separatedBy: .newlines) {
            guard raw.range(of: marker, options: .regularExpression) != nil else {
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty && !["no action items", "none"].contains(line.lowercased()) { result.otherLines.append(line) }
                continue
            }
            let full = cleaned(raw)
            guard !full.isEmpty else { continue }
            var text = full
            var owner: String?
            let patterns = ["^(\(name))\\s*(?::| — | - )\\s*(.+)$", "^(.+?)\\s*\\((?:owner: )?(\(name))\\)$", "^(.+?) — (\(name))$"]
            for (index, pattern) in patterns.enumerated() {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: full, range: NSRange(full.startIndex..., in: full)),
                      let first = Range(match.range(at: 1), in: full), let second = Range(match.range(at: 2), in: full) else { continue }
                let candidate = String(full[index == 0 ? first : second])
                guard !excluded.contains(candidate.lowercased()) else { continue }
                owner = candidate
                text = String(full[index == 0 ? second : first]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
            result.items.append(ActionItem(meetingID: meetingID, text: text, owner: owner, key: key(full)))
        }
        return result
    }
}


public struct DoneActionItem: Codable, Equatable, Sendable {
    public var meetingID: MeetingID
    public var key: String
    public var doneAt: Date

    public init(meetingID: MeetingID, key: String, doneAt: Date) {
        self.meetingID = meetingID; self.key = key; self.doneAt = doneAt
    }

    private enum CodingKeys: String, CodingKey { case meetingID, key, doneAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meetingID = MeetingID(rawValue: try c.decode(String.self, forKey: .meetingID))
        key = try c.decode(String.self, forKey: .key)
        doneAt = try c.decode(Date.self, forKey: .doneAt)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(meetingID.rawValue, forKey: .meetingID)
        try c.encode(key, forKey: .key)
        try c.encode(doneAt, forKey: .doneAt)
    }
}

public struct ActionItemFile: Codable, Equatable, Sendable {
    public static let supportedSchemaVersion = 1
    public static let maxEntries = 5_000
    public var schemaVersion: Int
    public var done: [DoneActionItem]

    public init(schemaVersion: Int = supportedSchemaVersion, done: [DoneActionItem] = []) {
        self.schemaVersion = schemaVersion; self.done = done
        cap()
    }
    public func doneAt(_ item: ActionItem) -> Date? {
        done.first { $0.meetingID == item.meetingID && $0.key == item.key }?.doneAt
    }
    public mutating func setDone(_ item: ActionItem, _ done: Bool, at: Date) {
        if done {
            guard doneAt(item) == nil else { return }
            self.done.append(DoneActionItem(meetingID: item.meetingID, key: item.key, doneAt: at))
            cap()
        } else { self.done.removeAll { $0.meetingID == item.meetingID && $0.key == item.key } }
    }
    public mutating func prune(keeping meetings: Set<MeetingID>) {
        done.removeAll { !meetings.contains($0.meetingID) }
        cap()
    }
    private mutating func cap() {
        if done.count > Self.maxEntries { done = Array(done.sorted { $0.doneAt > $1.doneAt }.prefix(Self.maxEntries)) }
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, done }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.value(.schemaVersion, default: Self.supportedSchemaVersion)
        done = c.value(.done, default: [DoneActionItem]())
        cap()
    }
}

public actor ActionItemStore {
    public let url: URL
    private var lastRevision = Int.min
    public init(url: URL) { self.url = url }
    public func load() -> ActionItemFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return ActionItemFile() }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url), let file = try? decoder.decode(ActionItemFile.self, from: data) else {
            let backup = url.deletingLastPathComponent().appendingPathComponent("action-items.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return ActionItemFile()
        }
        return file
    }
    public func save(_ file: ActionItemFile, revision: Int? = nil) throws {
        if let revision, revision <= lastRevision { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
        if let revision { lastRevision = revision }
    }
}
