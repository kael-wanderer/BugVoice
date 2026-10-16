import Foundation

public enum MarkdownSpanKind: Equatable, Sendable {
    /// Markdown syntax characters, drawn grey.
    case mark
    case heading(Int)
    case bold
    case italic
    case strike
    case code
    case codeBlock
    case quote
    case link
    case doneTask
    case underline
    /// A whole table line, drawn monospaced.
    case table
}

/// A styled range in UTF-16 offsets of the whole text.
public struct MarkdownSpan: Equatable, Sendable {
    public let kind: MarkdownSpanKind
    public let location: Int
    public let length: Int

    public init(_ kind: MarkdownSpanKind, _ location: Int, _ length: Int) {
        self.kind = kind
        self.location = location
        self.length = length
    }
}

/// Where the Markdown view draws headings, emphasis and grey marks. The text
/// itself is never changed.
public enum MarkdownStyler {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static let code = regex(#"(`)([^`\n]+)(`)"#)
    private static let link = regex(#"(\[)([^\]\n]+)(\]\([^)\s]+\))"#)
    private static let inline: [(NSRegularExpression, MarkdownSpanKind)] = [
        (regex(#"(\*\*)(?=\S)(.+?)(?<=\S)(\*\*)"#), .bold),
        (regex(#"(__)(?=\S)(.+?)(?<=\S)(__)"#), .bold),
        (regex(#"(~~)(?=\S)(.+?)(?<=\S)(~~)"#), .strike),
        (regex(#"(?<![*\w])(\*)(?=[^\s*])(.+?)(?<=[^\s*])(\*)(?![*\w])"#), .italic),
        (regex(#"(?<![_\w])(_)(?=[^\s_])(.+?)(?<=[^\s_])(_)(?![_\w])"#), .italic),
        (regex(#"(<u>)(.+?)(</u>)"#), .underline),
    ]

    public static func spans(in text: String) -> [MarkdownSpan] {
        var spans: [MarkdownSpan] = []
        var lineStart = 0
        var inFence = false
        let lines = text.components(separatedBy: "\n")
        let tables = MarkdownTable.find(in: lines)
        for (index, line) in lines.enumerated() {
            let length = (line as NSString).length
            defer { lineStart += length + 1 }
            if let table = tables.first(where: { $0.contains(index) }) {
                spans.append(MarkdownSpan(.table, lineStart, length))
                if index == table.lowerBound + 1 {
                    spans.append(MarkdownSpan(.mark, lineStart, length))
                    continue
                }
                let ns = line as NSString
                for offset in 0..<ns.length where ns.character(at: offset) == 0x7C {
                    spans.append(MarkdownSpan(.mark, lineStart + offset, 1))
                }
                spans.append(contentsOf: inlineSpans(in: line, offset: lineStart))
                continue
            }
            if MarkdownLine.isFence(line) {
                spans.append(MarkdownSpan(.codeBlock, lineStart, length))
                spans.append(MarkdownSpan(.mark, lineStart, length))
                inFence.toggle()
                continue
            }
            if inFence {
                if length > 0 { spans.append(MarkdownSpan(.codeBlock, lineStart, length)) }
                continue
            }
            let parsed = MarkdownLine.parse(line)
            let prefixStart = lineStart + (parsed.indent as NSString).length
            let prefixLength = (parsed.prefix as NSString).length
            let contentStart = prefixStart + prefixLength
            let contentLength = (parsed.content as NSString).length
            if prefixLength > 0 { spans.append(MarkdownSpan(.mark, prefixStart, prefixLength)) }
            switch parsed.kind {
            case .heading(let level):
                spans.append(MarkdownSpan(.heading(level), contentStart, contentLength))
            case .task(checked: true):
                spans.append(MarkdownSpan(.doneTask, contentStart, contentLength))
            case .quote:
                spans.append(MarkdownSpan(.quote, contentStart, contentLength))
            case .plain, .bullet, .numbered, .task(checked: false):
                break
            }
            spans.append(contentsOf: inlineSpans(in: parsed.content, offset: contentStart))
        }
        return spans
    }

    static func inlineSpans(in content: String, offset: Int) -> [MarkdownSpan] {
        let ns = content as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var spans: [MarkdownSpan] = []
        var taken: [NSRange] = []

        func add(_ match: NSTextCheckingResult, _ kind: MarkdownSpanKind) {
            let open = match.range(at: 1), inner = match.range(at: 2), close = match.range(at: 3)
            spans.append(MarkdownSpan(.mark, offset + open.location, open.length))
            spans.append(MarkdownSpan(kind, offset + inner.location, inner.length))
            spans.append(MarkdownSpan(.mark, offset + close.location, close.length))
        }

        // Code first: nothing inside a code span is styled.
        for match in code.matches(in: content, range: whole) {
            add(match, .code)
            taken.append(match.range)
        }
        for match in link.matches(in: content, range: whole)
        where !taken.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
            add(match, .link)
        }
        for (pattern, kind) in inline {
            for match in pattern.matches(in: content, range: whole)
            where !taken.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                add(match, kind)
            }
        }
        return spans
    }
}
