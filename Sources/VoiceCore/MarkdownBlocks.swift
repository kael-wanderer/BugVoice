import Foundation

/// One block of the Doc view. Inline text is still Markdown; the app renders it.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(indent: Int, text: String)
    case numbered(indent: Int, number: String, text: String)
    /// `line` is the 0-based line in the body, for ticking the box.
    case task(indent: Int, checked: Bool, text: String, line: Int)
    case quote(String)
    case code(String)
    case rule
    /// Every row has as many cells as the header.
    case table(header: [String], rows: [[String]])
}

public enum MarkdownBlocks {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var code: [String]?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))) }
            paragraph = []
            quote = []
        }

        let lines = text.components(separatedBy: "\n")
        let tables = MarkdownTable.find(in: lines)
        var skipUntil = -1
        for (index, line) in lines.enumerated() {
            if index <= skipUntil { continue }
            if let table = tables.first(where: { $0.lowerBound == index }) {
                flush()
                let header = MarkdownTable.cells(lines[index])
                let rows = lines[(index + 2)...table.upperBound].map { line in
                    let cells = MarkdownTable.cells(line)
                    return Array((cells + Array(repeating: "", count: max(0, header.count - cells.count))).prefix(header.count))
                }
                blocks.append(.table(header: header, rows: Array(rows)))
                skipUntil = table.upperBound
                continue
            }
            if MarkdownLine.isFence(line) {
                if let open = code {
                    blocks.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(line)
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
                continue
            }
            if MarkdownLine.isRule(line) {
                flush()
                blocks.append(.rule)
                continue
            }
            let parsed = MarkdownLine.parse(line)
            let indent = level(parsed.indent)
            switch parsed.kind {
            case .plain:
                if !quote.isEmpty { flush() }
                paragraph.append(parsed.content.trimmingCharacters(in: .whitespaces))
            case .quote:
                if !paragraph.isEmpty { flush() }
                quote.append(parsed.content)
            case .heading(let level):
                flush()
                blocks.append(.heading(level: level, text: parsed.content))
            case .bullet:
                flush()
                blocks.append(.bullet(indent: indent, text: parsed.content))
            case .numbered:
                flush()
                let number = String(parsed.prefix.dropLast()).trimmingCharacters(in: .whitespaces)
                blocks.append(.numbered(indent: indent, number: number, text: parsed.content))
            case .task(let checked):
                flush()
                blocks.append(.task(indent: indent, checked: checked, text: parsed.content, line: index))
            }
        }
        if let open = code { blocks.append(.code(open.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    /// Two spaces or one tab per level.
    static func level(_ indent: String) -> Int {
        indent.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
    }
}

/// Copy as → Plain text.
public enum MarkdownPlainText {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static let replacements: [(NSRegularExpression, String)] = [
        (regex(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#), "$1 ($2)"),
        (regex(#"`([^`\n]+)`"#), "$1"),
        (regex(#"\*\*(?=\S)(.+?)(?<=\S)\*\*"#), "$1"),
        (regex(#"__(?=\S)(.+?)(?<=\S)__"#), "$1"),
        (regex(#"~~(?=\S)(.+?)(?<=\S)~~"#), "$1"),
        (regex(#"(?<![*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![*\w])"#), "$1"),
        (regex(#"(?<![_\w])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![_\w])"#), "$1"),
        (regex(#"</?u>"#), ""),
    ]

    public static func convert(_ text: String) -> String {
        var inFence = false
        var lines: [String] = []
        let source = text.components(separatedBy: "\n")
        let tables = MarkdownTable.find(in: source)
        for (index, line) in source.enumerated() {
            if let table = tables.first(where: { $0.contains(index) }) {
                if index == table.lowerBound + 1 { continue }
                lines.append(MarkdownTable.cells(line).map(inline).joined(separator: " | "))
                continue
            }
            if MarkdownLine.isFence(line) {
                inFence.toggle()
                continue
            }
            if inFence {
                lines.append(line)
                continue
            }
            let parsed = MarkdownLine.parse(line)
            let content = inline(parsed.content)
            switch parsed.kind {
            case .heading, .quote: lines.append(parsed.indent + content)
            default: lines.append(parsed.indent + parsed.prefix + content)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Inline marks removed from one line's content.
    static func inline(_ text: String) -> String {
        var content = text
        for (pattern, template) in replacements {
            content = pattern.stringByReplacingMatches(
                in: content, range: NSRange(location: 0, length: (content as NSString).length), withTemplate: template)
        }
        return content
    }
}
