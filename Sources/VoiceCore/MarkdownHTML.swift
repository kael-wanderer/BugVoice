import Foundation

/// The note as HTML for Copy: Slack, Gmail and Notion keep bold, lists and
/// tables when they paste it.
public enum MarkdownHTML {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static let code = regex(#"`([^`\n]+)`"#)
    private static let link = regex(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
    private static let inline: [(NSRegularExpression, String)] = [
        (regex(#"\*\*(?=\S)(.+?)(?<=\S)\*\*"#), "<strong>$1</strong>"),
        (regex(#"__(?=\S)(.+?)(?<=\S)__"#), "<strong>$1</strong>"),
        (regex(#"~~(?=\S)(.+?)(?<=\S)~~"#), "<s>$1</s>"),
        (regex(#"(?<![*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![*\w])"#), "<em>$1</em>"),
        (regex(#"(?<![_\w])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![_\w])"#), "<em>$1</em>"),
        (regex(#"&lt;u&gt;(.+?)&lt;/u&gt;"#), "<u>$1</u>"),
    ]

    /// A whole HTML document, UTF-8.
    public static func document(_ markdown: String) -> String {
        "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>" + render(markdown) + "</body></html>"
    }

    /// The blocks of `markdown` as an HTML fragment.
    public static func render(_ markdown: String) -> String {
        var html = ""
        var lists: [(tag: String, itemOpen: Bool)] = []

        func closeList() {
            guard let last = lists.popLast() else { return }
            if last.itemOpen { html += "</li>" }
            html += "</\(last.tag)>"
        }

        func item(indent: Int, tag: String, content: String) {
            let depth = min(indent, lists.count) + 1
            while lists.count > depth { closeList() }
            if lists.count == depth, lists[depth - 1].tag != tag { closeList() }
            if lists.count == depth {
                if lists[depth - 1].itemOpen { html += "</li>" }
            } else {
                html += "<\(tag)>"
                lists.append((tag, false))
            }
            html += "<li>" + content
            lists[depth - 1].itemOpen = true
        }

        for block in MarkdownBlocks.parse(markdown) {
            switch block {
            case .bullet(let indent, let text):
                item(indent: indent, tag: "ul", content: inlineHTML(text))
                continue
            case .numbered(let indent, _, let text):
                item(indent: indent, tag: "ol", content: inlineHTML(text))
                continue
            case .task(let indent, let checked, let text, _):
                item(indent: indent, tag: "ul", content: (checked ? "☑ " : "☐ ") + inlineHTML(text))
                continue
            default:
                while !lists.isEmpty { closeList() }
            }
            switch block {
            case .heading(let level, let text):
                html += "<h\(level)>\(inlineHTML(text))</h\(level)>"
            case .paragraph(let text):
                html += "<p>\(lines(text))</p>"
            case .quote(let text):
                html += "<blockquote><p>\(lines(text))</p></blockquote>"
            case .code(let text):
                html += "<pre><code>\(escape(text))</code></pre>"
            case .rule:
                html += "<hr>"
            case .table(let header, let rows):
                html += "<table><thead><tr>"
                html += header.map { "<th>\(inlineHTML($0))</th>" }.joined()
                html += "</tr></thead><tbody>"
                for row in rows {
                    html += "<tr>" + row.map { "<td>\(inlineHTML($0))</td>" }.joined() + "</tr>"
                }
                html += "</tbody></table>"
            case .bullet, .numbered, .task:
                break
            }
        }
        while !lists.isEmpty { closeList() }
        return html
    }

    static func lines(_ text: String) -> String {
        text.components(separatedBy: "\n").map(inlineHTML).joined(separator: "<br>")
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Inline marks of one line. Nothing inside a code span is formatted;
    /// links other than http, https and mailto become their text.
    static func inlineHTML(_ text: String) -> String {
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in code.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += formatted(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            result += "<code>\(escape(ns.substring(with: match.range(at: 1))))</code>"
            cursor = match.range.location + match.range.length
        }
        return result + formatted(ns.substring(from: cursor))
    }

    private static func formatted(_ text: String) -> String {
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in link.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += emphasis(escape(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            let label = emphasis(escape(ns.substring(with: match.range(at: 1))))
            let url = ns.substring(with: match.range(at: 2))
            let scheme = url.split(separator: ":").first.map { $0.lowercased() } ?? ""
            result += ["http", "https", "mailto"].contains(scheme) && url.contains(":")
                ? "<a href=\"\(escape(url))\">\(label)</a>"
                : label
            cursor = match.range.location + match.range.length
        }
        return result + emphasis(escape(ns.substring(from: cursor)))
    }

    private static func emphasis(_ escaped: String) -> String {
        var text = escaped
        for (pattern, template) in inline {
            text = pattern.stringByReplacingMatches(
                in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
        }
        return text
    }
}
