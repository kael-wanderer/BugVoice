import Foundation

public enum AskRanking {
    public static let maxPassages = 40

    /// BM25 (k1 1.2, b 0.75) per passage id over `searchText`. A multi-word term counts each
    /// consecutive run of its folded words as one occurrence. Zero scores are omitted. A passage
    /// with a line speaker matching a `people` entry scores 20 % higher.
    public static func wordScores(
        _ passages: [AskPassage], terms: [String], people: [String]
    ) -> [String: Double] {
        var seen = Set<[String]>()
        var termTokens: [[String]] = []
        for term in terms {
            let t = AskText.tokens(term)
            if !t.isEmpty, seen.insert(t).inserted { termTokens.append(t) }
        }
        guard !termTokens.isEmpty, !passages.isEmpty else { return [:] }

        let docs = passages.map { AskText.tokens($0.searchText) }
        let n = Double(passages.count)
        let avgLen = max(Double(docs.reduce(0) { $0 + $1.count }) / n, 1)
        let k1 = 1.2, b = 0.75

        let counts: [[Int]] = termTokens.map { term in docs.map { occurrences(of: term, in: $0) } }
        let idf: [Double] = counts.map { row in
            let df = Double(row.filter { $0 > 0 }.count)
            return log((n - df + 0.5) / (df + 0.5) + 1)
        }
        let peopleFolded = Set(people.map { AskText.fold($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })

        var result: [String: Double] = [:]
        for (i, p) in passages.enumerated() {
            let len = Double(docs[i].count)
            var score = 0.0
            for t in termTokens.indices {
                let tf = Double(counts[t][i])
                if tf == 0 { continue }
                score += idf[t] * tf * (k1 + 1) / (tf + k1 * (1 - b + b * len / avgLen))
            }
            guard score > 0 else { continue }
            let hit = p.lines.contains {
                guard let s = $0.speaker else { return false }
                return peopleFolded.contains(AskText.fold(s).trimmingCharacters(in: .whitespaces))
            }
            result[p.id] = hit ? score * 1.2 : score
        }
        return result
    }

    private static func occurrences(of term: [String], in doc: [String]) -> Int {
        guard !term.isEmpty, doc.count >= term.count else { return 0 }
        var count = 0
        var i = 0
        while i <= doc.count - term.count {
            if doc[i] == term[0], Array(doc[i..<(i + term.count)]) == term {
                count += 1
                i += term.count
            } else {
                i += 1
            }
        }
        return count
    }

    /// Dot product; inputs are expected to be normalised. Mismatched lengths give 0.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var sum: Float = 0
        for i in a.indices { sum += a[i] * b[i] }
        return sum
    }

    /// Reciprocal rank fusion, best first. Ties keep first-seen order across the rankings.
    public static func fuse(_ rankings: [[String]], k: Double = 60) -> [String] {
        var score: [String: Double] = [:]
        var order: [String] = []
        for ranking in rankings {
            for (i, id) in ranking.enumerated() {
                if score[id] == nil { order.append(id) }
                score[id, default: 0] += 1 / (k + Double(i + 1))
            }
        }
        let pos = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return order.sorted {
            let a = score[$0]!, b = score[$1]!
            return a != b ? a > b : pos[$0]! < pos[$1]!
        }
    }
}
