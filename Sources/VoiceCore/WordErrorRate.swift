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

    public static func compute(reference: String, hypothesis: String) -> Double {
        let ref = words(reference)
        let hyp = words(hypothesis)
        if ref.isEmpty { return hyp.isEmpty ? 0 : 1 }
        var previous = Array(0...hyp.count)
        for i in 1...ref.count {
            var current = [i] + Array(repeating: 0, count: hyp.count)
            for j in 1...max(hyp.count, 1) where j <= hyp.count {
                let cost = ref[i - 1] == hyp[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return Double(previous[hyp.count]) / Double(ref.count)
    }
}
