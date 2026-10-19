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
