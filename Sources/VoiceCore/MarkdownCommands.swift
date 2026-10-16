import Foundation

/// One replacement in UTF-16 offsets, plus the selection to show after it.
/// The app applies it as a single text-view change, so it is one undo step.
public struct MarkdownEdit: Equatable, Sendable {
    public let range: NotesTextRange
    public let replacement: String
    public let selection: NotesTextRange

    public init(range: NotesTextRange, replacement: String, selection: NotesTextRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// The text after the edit.
    public func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(
            in: NSRange(location: range.location, length: range.length), with: replacement)
    }
}

public enum InlineMarker: String, Sendable, CaseIterable {
    case bold = "**"
    case italic = "_"
    case strike = "~~"
    case code = "`"
}

public enum LineFormat: Equatable, Sendable {
    case heading(Int)
    case bullet
    case numbered
    case task
    case quote

    func matches(_ kind: MarkdownLineKind) -> Bool {
        switch (self, kind) {
        case (.heading(let a), .heading(let b)): a == b
        case (.bullet, .bullet), (.numbered, .numbered), (.quote, .quote): true
        case (.task, .task): true
        default: false
        }
    }

    func prefix(number: Int) -> String {
        switch self {
        case .heading(let level): String(repeating: "#", count: level) + " "
        case .bullet: "- "
        case .numbered: "\(number). "
        case .task: "- [ ] "
        case .quote: "> "
        }
    }
}

public enum MarkdownCommands {
    public static func toggleInline(_ marker: InlineMarker, in text: String, selection: NotesTextRange) -> MarkdownEdit {
        let ns = text as NSString
        let selected = ns.substring(with: NSRange(location: selection.location, length: selection.length))
        if marker == .code, selected.contains("\n") {
            return toggleCodeBlock(in: text, selection: selection)
        }
        let mark = marker.rawValue
        let markLength = (mark as NSString).length
        let location = selection.location, length = selection.length

        if length == 0 {
            return MarkdownEdit(
                range: selection, replacement: mark + mark,
                selection: NotesTextRange(location: location + markLength, length: 0))
        }
        if length >= 2 * markLength, selected.hasPrefix(mark), selected.hasSuffix(mark) {
            let inner = (selected as NSString).substring(
                with: NSRange(location: markLength, length: length - 2 * markLength))
            return MarkdownEdit(
                range: selection, replacement: inner,
                selection: NotesTextRange(location: location, length: (inner as NSString).length))
        }
        if location >= markLength, location + length + markLength <= ns.length,
           ns.substring(with: NSRange(location: location - markLength, length: markLength)) == mark,
           ns.substring(with: NSRange(location: location + length, length: markLength)) == mark {
            return MarkdownEdit(
                range: NotesTextRange(location: location - markLength, length: length + 2 * markLength),
                replacement: selected,
                selection: NotesTextRange(location: location - markLength, length: length))
        }
        return MarkdownEdit(
            range: selection, replacement: mark + selected + mark,
            selection: NotesTextRange(location: location + markLength, length: length))
    }

    /// Wraps the selection in `<u>`…`</u>`, or removes the tags when they sit
    /// at the ends of the selection or just outside it.
    public static func toggleUnderline(in text: String, selection: NotesTextRange) -> MarkdownEdit {
        let ns = text as NSString
        let open = "<u>", close = "</u>"
        let location = selection.location, length = selection.length
        let selected = ns.substring(with: NSRange(location: location, length: length))
        if length == 0 {
            return MarkdownEdit(
                range: selection, replacement: open + close,
                selection: NotesTextRange(location: location + 3, length: 0))
        }
        if length >= 7, selected.hasPrefix(open), selected.hasSuffix(close) {
            let inner = (selected as NSString).substring(with: NSRange(location: 3, length: length - 7))
            return MarkdownEdit(
                range: selection, replacement: inner,
                selection: NotesTextRange(location: location, length: (inner as NSString).length))
        }
        if location >= 3, location + length + 4 <= ns.length,
           ns.substring(with: NSRange(location: location - 3, length: 3)) == open,
           ns.substring(with: NSRange(location: location + length, length: 4)) == close {
            return MarkdownEdit(
                range: NotesTextRange(location: location - 3, length: length + 7), replacement: selected,
                selection: NotesTextRange(location: location - 3, length: length))
        }
        return MarkdownEdit(
            range: selection, replacement: open + selected + close,
            selection: NotesTextRange(location: location + 3, length: length))
    }

    /// Adds two spaces before every selected list line (bullet, numbered,
    /// task), or removes up to two (or one tab) with `outdent`. Nil when no
    /// line changes, so Tab can fall back to typing a tab.
    public static func indent(in text: String, selection: NotesTextRange, outdent: Bool) -> MarkdownEdit? {
        let ns = text as NSString
        let block = lineBlock(in: ns, selection: selection)
        var lines = block.lines
        var changed = false
        var firstDelta = 0
        for index in lines.indices {
            let parsed = MarkdownLine.parse(lines[index])
            switch parsed.kind {
            case .bullet, .numbered, .task: break
            default: continue
            }
            let before = lines[index]
            if outdent {
                if lines[index].hasPrefix("\t") {
                    lines[index].removeFirst()
                } else {
                    var removed = 0
                    while removed < 2, lines[index].hasPrefix(" ") {
                        lines[index].removeFirst()
                        removed += 1
                    }
                }
            } else {
                lines[index] = "  " + lines[index]
            }
            if lines[index] != before {
                changed = true
                if index == 0 { firstDelta = (lines[index] as NSString).length - (before as NSString).length }
            }
        }
        guard changed else { return nil }
        let joined = lines.joined(separator: "\n")
        let joinedLength = (joined as NSString).length
        let newSelection = selection.length == 0 && lines.count == 1
            ? NotesTextRange(location: max(block.range.location, selection.location + firstDelta), length: 0)
            : NotesTextRange(location: block.range.location, length: joinedLength)
        return MarkdownEdit(
            range: block.range, replacement: joined + (block.trailingNewline ? "\n" : ""), selection: newSelection)
    }

    /// An empty table: a header row, the separator row, then `rows - 1` rows.
    /// It goes on the caret's line when that line is blank, otherwise after
    /// it with a blank line between. The caret lands in the first header cell.
    public static func insertTable(columns: Int, rows: Int, in text: String, selection: NotesTextRange) -> MarkdownEdit {
        let columns = min(max(columns, 1), 8), rows = min(max(rows, 1), 8)
        let empty = "|" + String(repeating: "  |", count: columns)
        let separator = "|" + String(repeating: " --- |", count: columns)
        let table = ([empty, separator] + Array(repeating: empty, count: rows - 1)).joined(separator: "\n")
        let ns = text as NSString
        let caret = min(max(selection.location, 0), ns.length)
        var lineStart = 0, contentsEnd = 0
        ns.getLineStart(&lineStart, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
        let line = ns.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
        let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
        let range = blank
            ? NotesTextRange(location: lineStart, length: contentsEnd - lineStart)
            : NotesTextRange(location: contentsEnd, length: 0)
        let lead = blank ? "" : "\n\n"
        let replacement = lead + table + (contentsEnd < ns.length ? "\n" : "")
        return MarkdownEdit(
            range: range, replacement: replacement,
            selection: NotesTextRange(location: range.location + (lead as NSString).length + 2, length: 0))
    }

    public static func insertLink(in text: String, selection: NotesTextRange) -> MarkdownEdit {
        let ns = text as NSString
        let selected = ns.substring(with: NSRange(location: selection.location, length: selection.length))
        if selected.isEmpty {
            return MarkdownEdit(
                range: selection, replacement: "[text](https://)",
                selection: NotesTextRange(location: selection.location + 1, length: 4))
        }
        let replacement = "[\(selected)](https://)"
        let urlStart = selection.location + 1 + selection.length + 2
        return MarkdownEdit(
            range: selection, replacement: replacement,
            selection: NotesTextRange(location: urlStart, length: 8))
    }

    public static func toggleLineFormat(_ format: LineFormat, in text: String, selection: NotesTextRange) -> MarkdownEdit {
        let ns = text as NSString
        let block = lineBlock(in: ns, selection: selection)
        var lines = block.lines
        let parsed = lines.map(MarkdownLine.parse)
        var targets = lines.indices.filter { !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        if targets.isEmpty, lines.count == 1 { targets = [0] }
        let remove = targets.allSatisfy { format.matches(parsed[$0].kind) } && !targets.isEmpty
            && targets.contains { !parsed[$0].prefix.isEmpty }
        for (number, index) in targets.enumerated() {
            let line = parsed[index]
            lines[index] = remove
                ? line.indent + line.content
                : line.indent + format.prefix(number: number + 1) + line.content
        }
        let joined = lines.joined(separator: "\n")
        let replacement = joined + (block.trailingNewline ? "\n" : "")
        let joinedLength = (joined as NSString).length
        let newSelection = selection.length == 0 && lines.count == 1
            ? NotesTextRange(location: block.range.location + joinedLength, length: 0)
            : NotesTextRange(location: block.range.location, length: joinedLength)
        return MarkdownEdit(range: block.range, replacement: replacement, selection: newSelection)
    }

    /// Adds a blank line and `insert` after the line that holds `location`
    /// (the end of a transform's input). A location just after a newline
    /// counts as the line before it. The inserted text ends up selected.
    public static func insertBelow(_ insert: String, in text: String, after location: Int) -> MarkdownEdit {
        let ns = text as NSString
        let end = min(max(location, 0), ns.length)
        let probe = end > 0 && ns.character(at: end - 1) == 0x0A ? end - 1 : end
        var contentsEnd = 0
        ns.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: probe, length: 0))
        let lead = ns.length == 0 ? "" : "\n\n"
        let replacement = lead + insert + (contentsEnd < ns.length ? "\n" : "")
        return MarkdownEdit(
            range: NotesTextRange(location: contentsEnd, length: 0), replacement: replacement,
            selection: NotesTextRange(location: contentsEnd + (lead as NSString).length, length: (insert as NSString).length))
    }

    /// Ticks or unticks the task on `line` (0-based). Nil when that line is not a task.
    public static func toggleTask(in text: String, line: Int) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return nil }
        let parsed = MarkdownLine.parse(lines[line])
        guard case .task(let checked) = parsed.kind else { return nil }
        let prefix = checked
            ? parsed.prefix.replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]")
            : parsed.prefix.replacingOccurrences(of: "[ ]", with: "[x]")
        lines[line] = parsed.indent + prefix + parsed.content
        return lines.joined(separator: "\n")
    }

    static func toggleCodeBlock(in text: String, selection: NotesTextRange) -> MarkdownEdit {
        let ns = text as NSString
        let block = lineBlock(in: ns, selection: selection)
        var lines = block.lines
        if lines.count >= 2, MarkdownLine.isFence(lines[0]), MarkdownLine.isFence(lines[lines.count - 1]) {
            lines.removeFirst()
            lines.removeLast()
        } else {
            lines = ["```"] + lines + ["```"]
        }
        let joined = lines.joined(separator: "\n")
        return MarkdownEdit(
            range: block.range,
            replacement: joined + (block.trailingNewline ? "\n" : ""),
            selection: NotesTextRange(location: block.range.location, length: (joined as NSString).length))
    }

    /// The whole lines the selection touches. A selection ending just after a
    /// newline does not pull in the next line.
    static func lineBlock(in ns: NSString, selection: NotesTextRange) -> (range: NotesTextRange, lines: [String], trailingNewline: Bool) {
        var probe = NSRange(location: selection.location, length: selection.length)
        if probe.length > 0, ns.substring(with: NSRange(location: probe.location + probe.length - 1, length: 1)) == "\n" {
            probe.length -= 1
        }
        let range = ns.lineRange(for: probe)
        var block = ns.substring(with: range)
        let trailing = block.hasSuffix("\n")
        if trailing { block.removeLast() }
        return (NotesTextRange(location: range.location, length: range.length), block.components(separatedBy: "\n"), trailing)
    }
}
