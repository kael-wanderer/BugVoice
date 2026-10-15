import Foundation

public struct ProtectedText: Equatable, Sendable {
    public var text: String
    public var fills: [String: String]

    public init(text: String, fills: [String: String]) {
        self.text = text
        self.fills = fills
    }

    public func isIntact(_ cleaned: String) -> Bool {
        SnippetExpander.placeholders(in: cleaned).sorted() == fills.keys.sorted()
    }

    /// Each placeholder is expanded once; snippet contents are never rescanned.
    public func fill(_ text: String) -> String {
        guard !fills.isEmpty else { return text }
        var output = ""
        var cursor = text.startIndex
        for match in text.matches(of: /⟦S\d+⟧/) {
            output += text[cursor..<match.range.lowerBound]
            let token = String(text[match.range])
            output += fills[token] ?? token
            cursor = match.range.upperBound
        }
        output += text[cursor...]
        return output
    }
}

public enum SnippetExpander {
    public static func protect(_ text: String, snippets: [Snippet]) -> ProtectedText {
        let rules = snippets
            .filter { !$0.trigger.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.trigger.count > $1.trigger.count }
        guard !rules.isEmpty else { return ProtectedText(text: text, fills: [:]) }
        let text = text.precomposedStringWithCanonicalMapping
        let alternation = rules.map { "(" + pattern(for: $0.trigger) + ")" }.joined(separator: "|")
        let pattern = "(?<![\\p{L}\\p{N}])(?:" + alternation + ")(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return ProtectedText(text: text, fills: [:])
        }
        let source = text as NSString
        var output = ""
        var cursor = 0
        var fills: [String: String] = [:]
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            guard let rule = rules.indices.first(where: { match.range(at: $0 + 1).location != NSNotFound }) else {
                output += source.substring(with: match.range)
                cursor = match.range.location + match.range.length
                continue
            }
            let token = "⟦S\(fills.count + 1)⟧"
            fills[token] = rules[rule].text
            output += token
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)
        return ProtectedText(text: output, fills: fills)
    }

    public static func placeholders(in text: String) -> [String] {
        text.matches(of: /⟦S\d+⟧/).map { String(text[$0.range]) }
    }

    static func pattern(for trigger: String) -> String {
        trigger.precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: "[\\s\\-]+")
    }
}
