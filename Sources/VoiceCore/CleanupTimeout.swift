import Foundation

/// How long dictation cleanup may take. A local model writes the cleaned text
/// word by word, so a long dictation needs longer than the base limit set in
/// Settings → Models; without this, anything over about 30 words timed out
/// and stayed raw (BV-0005).
public enum CleanupTimeout {
    static let secondsPerWord = 0.1
    static let cap = 15.0

    public static func limit(base: Double, raw: String) -> Double {
        let words = raw.split(whereSeparator: \.isWhitespace).count
        return max(base, min(cap, base + Double(words) * secondsPerWord))
    }
}
