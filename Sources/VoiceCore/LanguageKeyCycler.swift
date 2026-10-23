import Foundation

public struct LanguageKeyCycler: Sendable, Equatable {
    public private(set) var current: SpeechLanguage
    public private(set) var changed = false
    private let languages: [SpeechLanguage]

    /// Cycles Auto, then each dictation language in order, then Auto again.
    /// A start language outside `languages` (a per-app rule for a language
    /// no longer ticked) is shown as is; the first tap goes to Auto.
    public init(start: SpeechLanguage, languages: [SpeechLanguage]) {
        self.languages = DictationLanguages.normalized(languages)
        current = start
    }

    public mutating func tap() {
        let order = [SpeechLanguage.auto] + languages
        current = order.firstIndex(of: current).map { order[($0 + 1) % order.count] } ?? .auto
        changed = true
    }
}
