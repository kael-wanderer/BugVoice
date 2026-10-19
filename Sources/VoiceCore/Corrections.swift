import Foundation

public struct CorrectionCandidate: Equatable, Sendable {
    public var heard: String
    public var written: String
    var totalChanged: Int?
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.heard == rhs.heard && lhs.written == rhs.written }
    public init(heard: String, written: String) { self.heard = heard; self.written = written }
}

public enum CorrectionRegion {
    public static let anchorLength = 40
    public static let maxValueLength = 100_000
    public static func find(value: String, before: String, after: String) -> String? {
        guard value.count <= maxValueLength else { return nil }
        let before = String(before.suffix(anchorLength)), after = String(after.prefix(anchorLength))
        let start: String.Index
        if before.isEmpty { start = value.startIndex }
        else if let range = value.range(of: before, options: .backwards) { start = range.upperBound }
        else { return nil }
        let end: String.Index
        if after.isEmpty { end = value.endIndex }
        else if let range = value.range(of: after, range: start..<value.endIndex) { end = range.lowerBound }
        else { return nil }
        return String(value[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum CorrectionDiff {
    public static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map {
            String($0).trimmingCharacters(in: .punctuationCharacters.union(.symbols))
        }.filter { !$0.isEmpty }
    }
    // Hirschberg alignment keeps memory linear even for a large readable field.
    private static func lengths(_ a: [String], _ b: [String]) -> [Int] {
        var row = Array(repeating: 0, count: b.count + 1)
        for word in a {
            var previous = 0
            for j in b.indices {
                let old = row[j + 1]
                row[j + 1] = word == b[j] ? previous + 1 : max(row[j], old)
                previous = old
            }
        }
        return row
    }
    private static func matches(_ a: [String], _ b: [String], _ ai: Int = 0, _ bi: Int = 0) -> [(Int, Int)] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        if a.count == 1 { return b.firstIndex(of: a[0]).map { [(ai, bi + $0)] } ?? [] }
        let mid = a.count / 2
        let left = lengths(Array(a[..<mid]), b)
        let right = lengths(Array(a[mid...].reversed()), Array(b.reversed()))
        let split = (0...b.count).max { left[$0] + right[b.count - $0] < left[$1] + right[b.count - $1] }!
        return matches(Array(a[..<mid]), Array(b[..<split]), ai, bi)
            + matches(Array(a[mid...]), Array(b[split...]), ai + mid, bi + split)
    }
    public static func changedCount(pasted: String, edited: String) -> Int {
        let a = words(pasted), b = words(edited)
        return a.count - matches(a, b).count
    }
    public static func candidates(pasted: String, edited: String) -> [CorrectionCandidate] {
        let a = words(pasted), b = words(edited)
        var result: [CorrectionCandidate] = [], i = 0, j = 0
        let aligned = matches(a, b)
        for (x, y) in aligned + [(a.count, b.count)] {
            if (1...3).contains(x - i), (1...3).contains(y - j) {
                result.append(.init(heard: a[i..<x].joined(separator: " "), written: b[j..<y].joined(separator: " ")))
            }
            i = x + 1; j = y + 1
        }
        for index in result.indices { result[index].totalChanged = a.count - aligned.count }
        return result
    }
}

public enum CorrectionFilter {
    public static let minSimilarity = 0.5
    public static let maxWrittenLength = 40
    public static let maxCandidates = 3
    public static let maxChangedFraction = 0.4
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased().replacingOccurrences(of: "đ", with: "d")
    }
    public static func similarity(_ a: String, _ b: String) -> Double {
        let a = Array(fold(a)), b = Array(fold(b))
        guard max(a.count, b.count) > 0 else { return 1 }
        var row = Array(0...b.count)
        for i in a.indices {
            var next = [i + 1] + Array(repeating: 0, count: b.count)
            for j in b.indices { next[j + 1] = min(next[j] + 1, row[j + 1] + 1, row[j] + (a[i] == b[j] ? 0 : 1)) }
            row = next
        }
        return 1 - Double(row[b.count]) / Double(max(a.count, b.count))
    }
    public static func keep(_ candidates: [CorrectionCandidate], pasted: String) -> [CorrectionCandidate] {
        let words = CorrectionDiff.words(pasted)
        // Diff metadata includes skipped runs for the whole-paste rewrite limit.
        let changed = candidates.first?.totalChanged ?? candidates.reduce(0) { $0 + CorrectionDiff.words($1.heard).count }
        guard !words.isEmpty, candidates.count <= maxCandidates,
              Double(changed) / Double(words.count) <= maxChangedFraction else { return [] }
        return candidates.filter {
            $0.heard != $0.written && !$0.heard.isEmpty && !$0.written.isEmpty
                && $0.written.count <= maxWrittenLength
                && !($0.heard == words.first && $0.heard.lowercased() == $0.written.lowercased())
                && similarity($0.heard, $0.written) >= minSimilarity
        }
    }
}
