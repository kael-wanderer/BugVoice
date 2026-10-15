import Foundation

/// Word-level Levenshtein distance divided by reference length. Case and
/// punctuation are ignored; Vietnamese diacritics are not.
public enum WordErrorRate {
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    /// Word-level Levenshtein distance. Case and punctuation are ignored.
    public static func editDistance(reference: String, hypothesis: String) -> Int {
        let ref = words(reference)
        let hyp = words(hypothesis)
        if ref.isEmpty { return hyp.count }
        if hyp.isEmpty { return ref.count }
        var previous = Array(0...hyp.count)
        for i in 1...ref.count {
            var current = [i] + Array(repeating: 0, count: hyp.count)
            for j in 1...hyp.count {
                let cost = ref[i - 1] == hyp[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[hyp.count]
    }

    public static func compute(reference: String, hypothesis: String) -> Double {
        let referenceCount = words(reference).count
        if referenceCount == 0 { return words(hypothesis).isEmpty ? 0 : 1 }
        return Double(editDistance(reference: reference, hypothesis: hypothesis)) / Double(referenceCount)
    }
}
