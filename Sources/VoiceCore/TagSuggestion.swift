import Foundation

/// After a meeting summary, the Meetings model may propose existing tags.
/// Nothing it says is added without the user's click.
public enum TagSuggestion {
    public static let maxSuggestions = 3
    public static let maxAllowed = 200
    public static let system = """
    You label meeting notes. From the allowed tags, pick at most 3 that fit the summary. \
    Answer with tag names only, one per line, or the word none. Never invent a tag.
    """

    /// `allowed` is the tag catalog, most-used first.
    public static func request(summary: String, allowed: [String]) -> CleanupRequest {
        let list = allowed.prefix(maxAllowed).joined(separator: "\n")
        return CleanupRequest(
            system: system,
            user: "Allowed tags:\n\(list)\n\nSummary:\n\(summary)",
            maxTokens: 64,
            temperature: 0,
            disableThinking: true
        )
    }

    public static func parse(_ answer: String, allowed: [String], existing: [String]) -> [String] {
        let withoutThinking = answer.replacingOccurrences(of: "(?s)<think>.*?</think>", with: "", options: .regularExpression)
        let allowedSet = Set(allowed)
        var result: [String] = []
        for rawLine in withoutThinking.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            line = line.replacingOccurrences(of: #"^(\d+[.)]|[-*•])\s*"#, with: "", options: .regularExpression)
            guard let tag = TagName.normalize(line),
                  allowedSet.contains(tag),
                  !existing.contains(tag),
                  !result.contains(tag) else { continue }
            result.append(tag)
            if result.count == maxSuggestions { break }
        }
        return result
    }
}
