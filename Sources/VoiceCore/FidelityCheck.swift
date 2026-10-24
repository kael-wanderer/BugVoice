import Foundation

public struct FidelityIssue: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case number, negation, path, identifier }
    public enum Direction: String, Codable, Sendable { case lost, invented }
    public var kind: Kind
    public var direction: Direction
    public var token: String

    public init(kind: Kind, direction: Direction, token: String) {
        self.kind = kind; self.direction = direction; self.token = token
    }
}

public enum FidelityCheck {
    private static let placeholders = try! NSRegularExpression(pattern: "⟦[^⟧]*⟧")
    private static let lists = try! NSRegularExpression(pattern: #"(?m)^\s*(?:\d+[.)]|[-*•])\s+"#)
    private static let digits = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_])\d+(?:[.,:]\d+)*(?:st|nd|rd|th|\.?º|\.?ª|%)?(?![\p{L}\p{N}_])"#)
    private static let sentences = try! NSRegularExpression(pattern: #"[^\n]*?(?:[.!?](?=\s|$)|\n|$)"#)
    private static let corrections = try! NSRegularExpression(pattern: #"(?i)(?<!\p{L})(?:no\s*,?\s*I mean|I mean|sorry|actually|à không|à nhầm|ý là|no\s*,?\s*perdón|quiero decir)(?!\p{L})"#)

    private static func replacing(_ regex: NSRegularExpression, in text: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
    }

    /// Only details in the corrected portion of each sentence can be lost.
    private static func afterCorrections(_ text: String) -> String {
        guard corrections.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else { return text }
        return sentences.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let sentence = String(text[range])
            guard let marker = corrections.matches(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)).last,
                  let markerRange = Range(marker.range, in: sentence) else { return sentence }
            return String(sentence[markerRange.upperBound...])
        }.joined(separator: " ")
    }

    private struct NumberToken {
        var token: String
        var values: Set<Decimal>
    }

    private static func numbers(_ text: String) -> [NumberToken] {
        digits.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let token = String(text[range])
            let numeric = token.prefix { $0.isNumber || ".,:".contains($0) }
            let parts = numeric.split(separator: ":")
            var values = Set<Decimal>()
            for part in parts {
                let s = String(part)
                if let n = Decimal(string: s.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) { values.insert(n) }
                if s.contains(",") || (s.contains(".") && s.split(separator: ".").last?.count == 3) {
                    if let n = Decimal(string: s.filter(\.isNumber)) { values.insert(n) }
                }
            }
            // A clock's :00 suffix does not introduce a new number.
            if parts.count > 1 { values.remove(0) }
            return NumberToken(token: token, values: values)
        }
    }

    public static func issues(raw: String, cleaned: String) -> [FidelityIssue] {
        let raw = replacing(placeholders, in: raw)
        let cleaned = replacing(lists, in: replacing(placeholders, in: cleaned))
        let rawNumbers = numbers(raw)
        let cleanedNumbers = numbers(cleaned)
        let rawValues = rawNumbers.reduce(into: NumberWords.values(in: raw)) { $0.formUnion($1.values) }
        let cleanedValues = cleanedNumbers.reduce(into: NumberWords.values(in: cleaned)) { $0.formUnion($1.values) }
        var issues: [FidelityIssue] = []
        let eligibleRaw = afterCorrections(raw)
        for n in numbers(eligibleRaw) where n.values.isDisjoint(with: cleanedValues) {
            issues.append(.init(kind: .number, direction: .lost, token: n.token))
        }
        for n in cleanedNumbers where n.values.isDisjoint(with: rawValues) {
            let parts = n.token.split(separator: ".")
            if parts.count == 2, parts.allSatisfy({ part in
                guard let value = Decimal(string: String(part)) else { return false }
                return rawValues.contains(value)
            }) { continue }
            issues.append(.init(kind: .number, direction: .invented, token: n.token))
        }
        let rawNegations = negations.matches(in: eligibleRaw, range: NSRange(eligibleRaw.startIndex..., in: eligibleRaw))
        let cleanedNegationCount = negations.numberOfMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
        for match in rawNegations.dropFirst(cleanedNegationCount) {
            if let range = Range(match.range, in: eligibleRaw) {
                issues.append(.init(kind: .negation, direction: .lost, token: String(eligibleRaw[range])))
            }
        }
        let originalTokens = tokens(eligibleRaw)
        let outputTokens = tokens(cleaned)
        for kind in [FidelityIssue.Kind.path, .identifier] {
            for token in originalTokens where token.kind == kind {
                let kept = outputTokens.contains { candidate in
                    candidate.text == token.text || (candidate.sentenceStart &&
                        candidate.text == token.text.prefix(1).uppercased() + token.text.dropFirst())
                }
                if !kept { issues.append(.init(kind: kind, direction: .lost, token: token.text)) }
            }
        }
        return issues
    }

    private static let negations = try! NSRegularExpression(pattern: #"(?i)(?<![\p{L}\p{N}_])(?:not|no|never|cannot|none|nothing|nobody|neither|nor|without|không|chưa|chẳng|đừng|chả|nunca|nada|nadie|ni|sin|tampoco)(?![\p{L}\p{N}_])|n['’]t(?!\p{L})"#)
    private static let whitespaceToken = try! NSRegularExpression(pattern: #"\S+"#)
    private static let pathPattern = try! NSRegularExpression(pattern: #"(?:[\p{L}\p{N}_][/\\][\p{L}\p{N}_]|^(?:~/|\./)|^[\p{L}\p{N}_-]{2,}\.[\p{L}]{1,5}$)"#)
    private static let identifierPattern = try! NSRegularExpression(pattern: #"(?:[\p{Ll}\p{N}]\p{Lu}|\p{Lu}{2,}\p{Ll}|_|^--\p{L}[\p{L}\p{N}-]*$|^-\p{L}$)"#)
    private static let leadingDecoration = CharacterSet(charactersIn: "`*\"'“”‘’([{<")
    private static let trailingDecoration = CharacterSet(charactersIn: "`*\"'“”‘’.,;:!?)]}>" )

    private static let leadingContent = leadingDecoration.inverted
    private static let trailingContent = trailingDecoration.inverted

    private struct DetailToken {
        var text: String
        var kind: FidelityIssue.Kind?
        var sentenceStart: Bool
    }

    private static func tokens(_ text: String) -> [DetailToken] {
        var cache: [String: (String, FidelityIssue.Kind?)] = [:]
        return whitespaceToken.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let original = String(text[range])
            let token: String
            let kind: FidelityIssue.Kind?
            if let cached = cache[original] {
                (token, kind) = cached
            } else {
                let backticked = original.hasPrefix("`") && original.dropFirst().contains("`")
                guard let start = original.rangeOfCharacter(from: leadingContent)?.lowerBound,
                      let end = original.rangeOfCharacter(from: trailingContent, options: .backwards)?.upperBound,
                      start < end else { return nil }
                token = String(original[start..<end])
                let fullRange = NSRange(token.startIndex..., in: token)
                if pathPattern.firstMatch(in: token, range: fullRange) != nil { kind = .path }
                else if backticked || identifierPattern.firstMatch(in: token, range: fullRange) != nil { kind = .identifier }
                else { kind = nil }
                cache[original] = (token, kind)
            }
            // Only an uppercase candidate can preserve a detail by sentence
            // capitalization. Exact matches do not need sentence context.
            let preceding = token.first?.isUppercase == true ? text[..<range.lowerBound].last { !$0.isWhitespace } : nil
            let sentenceStart = token.first?.isUppercase == true && (preceding == nil || preceding.map { ".!?".contains($0) } == true)
            return DetailToken(text: token, kind: kind, sentenceStart: sentenceStart)
        }
    }
}
