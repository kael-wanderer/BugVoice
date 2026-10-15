import Foundation

/// The block prefix at the start of one Markdown line.
public enum MarkdownLineKind: Equatable, Sendable {
    case plain
    case heading(Int)
    case bullet
    case numbered
    case task(checked: Bool)
    case quote
}

/// One line split into indentation, block prefix and content. All three
/// joined give the line back unchanged.
public struct MarkdownLine: Equatable, Sendable {
    public let indent: String
    public let prefix: String
    public let kind: MarkdownLineKind
    public let content: String

    // Order matters: a task item also looks like a bullet.
    private static let pattern = try! NSRegularExpression(
        pattern: #"^([ \t]*)(#{1,6} |[-*+] \[[ xX]\] |[-*+] |\d{1,9}[.)] |> ?)?"#
    )

    public static func parse(_ line: String) -> MarkdownLine {
        let ns = line as NSString
        guard let match = pattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return MarkdownLine(indent: "", prefix: "", kind: .plain, content: line)
        }
        let indent = ns.substring(with: match.range(at: 1))
        let prefixRange = match.range(at: 2)
        guard prefixRange.location != NSNotFound else {
            return MarkdownLine(indent: indent, prefix: "", kind: .plain, content: ns.substring(from: match.range.length))
        }
        let prefix = ns.substring(with: prefixRange)
        let content = ns.substring(from: prefixRange.location + prefixRange.length)
        let kind: MarkdownLineKind
        if prefix.hasPrefix("#") {
            // Headings only count at the left margin.
            guard indent.isEmpty else {
                return MarkdownLine(indent: indent, prefix: "", kind: .plain, content: prefix + content)
            }
            kind = .heading(prefix.count - 1)
        } else if prefix.hasPrefix(">") {
            kind = .quote
        } else if prefix.contains("[") {
            kind = .task(checked: !prefix.contains("[ ]"))
        } else if prefix.first?.isNumber == true {
            kind = .numbered
        } else {
            kind = .bullet
        }
        return MarkdownLine(indent: indent, prefix: prefix, kind: kind, content: content)
    }

    /// Fence lines open or close a code block.
    public static func isFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    public static func isRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, let first = trimmed.first, "-*_".contains(first) else { return false }
        return trimmed.allSatisfy { $0 == first }
    }
}
