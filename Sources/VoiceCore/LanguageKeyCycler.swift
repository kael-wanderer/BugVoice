import Foundation

public struct LanguageKeyCycler: Sendable, Equatable {
    public private(set) var current: SpeechLanguage
    public private(set) var changed = false
    private let languages: [SpeechLanguage]

    /// Cycles Auto, then each dictation language in order, then Auto again.
    /// A start language that is not in `languages` starts at Auto.
    public init(start: SpeechLanguage, languages: [SpeechLanguage] = DictationLanguages.defaults) {
        self.languages = DictationLanguages.normalized(languages)
        current = self.languages.contains(start) ? start : .auto
    }

    public mutating func tap() {
        let order = [SpeechLanguage.auto] + languages
        let index = order.firstIndex(of: current) ?? 0
        current = order[(index + 1) % order.count]
        changed = true
    }
}
