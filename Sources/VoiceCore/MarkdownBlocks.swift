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

        for (index, line) in text.components(separatedBy: "\n").enumerated() {
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
    ]

    public static func convert(_ text: String) -> String {
        var inFence = false
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            if MarkdownLine.isFence(line) {
                inFence.toggle()
                continue
            }
            if inFence {
                lines.append(line)
                continue
            }
            let parsed = MarkdownLine.parse(line)
            var content = parsed.content
            for (pattern, template) in replacements {
                content = pattern.stringByReplacingMatches(
                    in: content, range: NSRange(location: 0, length: (content as NSString).length), withTemplate: template)
            }
            switch parsed.kind {
            case .heading, .quote: lines.append(parsed.indent + content)
            default: lines.append(parsed.indent + parsed.prefix + content)
            }
        }
        return lines.joined(separator: "\n")
    }
}
