import Foundation

public struct LanguageKeyCycler: Sendable, Equatable {
    public private(set) var current: SpeechLanguage
    public private(set) var changed = false

    public init(start: SpeechLanguage) {
        current = start == .en || start == .vi ? start : .auto
    }

    public mutating func tap() {
        current = switch current {
        case .auto: .en
        case .en: .vi
        case .vi, .es: .auto
        }
        changed = true
    }
}
