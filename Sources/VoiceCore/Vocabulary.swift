import Foundation

/// Words, heard-as replacements and snippets used by a dictation. Built from
/// the Dictionary; `parse` reads the old `vocabulary.txt` format.
public struct Vocabulary: Sendable, Equatable {
    public struct Replacement: Sendable, Equatable {
        public var spoken: String
        public var written: String

        public init(spoken: String, written: String) {
            self.spoken = spoken
            self.written = written
        }
    }

    public var terms: [String]
    public var replacements: [Replacement]
    public var snippets: [Snippet]

    public init(terms: [String] = [], replacements: [Replacement] = [], snippets: [Snippet] = []) {
        self.terms = terms
        self.replacements = replacements
        self.snippets = snippets
    }

    public init(dictionary: DictionaryFile) {
        self.init(
            terms: dictionary.words.reversed().map(\.word),
            replacements: dictionary.words.flatMap { word in
                word.heardAs.map { Replacement(spoken: $0, written: word.word) }
            },
            snippets: dictionary.snippets
        )
    }

    public static func parse(_ text: String) -> Vocabulary {
        var terms: [String] = []
        var replacements: [Replacement] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if let arrow = line.range(of: "=>") {
                let spoken = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
                let written = line[arrow.upperBound...]
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\\n", with: "\n")
                if !spoken.isEmpty {
                    replacements.append(Replacement(spoken: spoken, written: written))
                }
            } else if !terms.contains(line) {
                terms.append(line)
            }
        }
        return Vocabulary(terms: terms, replacements: replacements)
    }

    /// Whole-word, case-insensitive, single pass. All spoken phrases form one
    /// alternation, longest first, so "claude code" is not pre-empted by a rule
    /// for "code" and already-replaced text is never re-scanned. Text and rules
    /// are compared in NFC, so precomposed and decomposed Vietnamese match.
    public func applyReplacements(to text: String) -> String {
        let rules = replacements.sorted { $0.spoken.count > $1.spoken.count }
        guard !rules.isEmpty else { return text }
        let text = text.precomposedStringWithCanonicalMapping
        let alternation = rules
            .map { "(" + NSRegularExpression.escapedPattern(for: $0.spoken.precomposedStringWithCanonicalMapping) + ")" }
            .joined(separator: "|")
        let pattern = "(?<![\\p{L}\\p{N}])(?:" + alternation + ")(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let source = text as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let written = rules.indices
                .first { match.range(at: $0 + 1).location != NSNotFound }
                .map { rules[$0].written } ?? source.substring(with: match.range)
            output += written
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)
        return output
    }

    /// Terms for Whisper's initial prompt, most recently added first.
    public func whisperPrompt(maxCharacters: Int = 600) -> String {
        var parts: [String] = []
        var length = 0
        for term in terms.reversed() {
            let added = parts.isEmpty ? term.count : term.count + 2
            if length + added > maxCharacters { break }
            parts.append(term)
            length += added
        }
        return parts.joined(separator: ", ")
    }
}
