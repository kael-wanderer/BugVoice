import Foundation

/// Pipe tables: a header row, a separator row (`| --- | :-: |`), then body
/// rows. Every row starts with `|` after optional spaces.
public enum MarkdownTable {
    private static let separatorCell = try! NSRegularExpression(pattern: #"^:?-+:?$"#)

    public static func isRow(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("|")
    }

    public static func isSeparator(_ line: String) -> Bool {
        guard isRow(line) else { return false }
        let cells = self.cells(line)
        return !cells.isEmpty && cells.allSatisfy {
            separatorCell.firstMatch(in: $0, range: NSRange(location: 0, length: ($0 as NSString).length)) != nil
        }
    }

    /// The cells of one row, trimmed, without the outer pipes.
    public static func cells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Line indices of every table, outside code fences. Each range runs from
    /// the header to the last body row.
    public static func find(in lines: [String]) -> [ClosedRange<Int>] {
        var tables: [ClosedRange<Int>] = []
        var inFence = false
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if MarkdownLine.isFence(line) {
                inFence.toggle()
                index += 1
                continue
            }
            if !inFence, isRow(line), !isSeparator(line), index + 1 < lines.count, isSeparator(lines[index + 1]) {
                var end = index + 1
                while end + 1 < lines.count, isRow(lines[end + 1]), !MarkdownLine.isFence(lines[end + 1]) { end += 1 }
                tables.append(index...end)
                index = end + 1
                continue
            }
            index += 1
        }
        return tables
    }
}
