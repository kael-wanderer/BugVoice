import AppKit

public enum RealWords {
    @MainActor public static func isRealWord(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let checker = NSSpellChecker.shared
        let languages = checker.availableLanguages.filter {
            $0 == "en" || $0.hasPrefix("en_") || $0.hasPrefix("en-")
                || $0 == "vi" || $0.hasPrefix("vi_") || $0.hasPrefix("vi-")
        }
        return languages.contains {
            checker.checkSpelling(of: text.lowercased(), startingAt: 0, language: $0, wrap: false,
                                  inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
        }
    }
}
