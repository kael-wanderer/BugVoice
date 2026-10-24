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
        sentences.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
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
        for n in numbers(afterCorrections(raw)) where n.values.isDisjoint(with: cleanedValues) {
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
        return issues
    }
}
