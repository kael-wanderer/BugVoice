import Foundation

public enum AskText {
    /// Lowercased, diacritics removed, "đ" becomes "d".
    public static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "đ", with: "d")
    }

    /// Folded words: split on anything that is not a letter or digit, empties dropped.
    public static func tokens(_ s: String) -> [String] {
        fold(s).split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }
}
