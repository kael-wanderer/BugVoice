import Foundation

public enum FixKind: String, Codable, Sendable { case raw, otherLanguage }

public enum FixLast {
    public static let syntheticEventMarker: Int64 = 0x4256_5043

    public static func countsAsTyping(keyCode: Int64, flags: UInt64, userData: Int64, shortcutKeyCodes: Set<Int64>) -> Bool {
        guard userData != syntheticEventMarker else { return false }
        let control: UInt64 = 0x0004_0000
        let option: UInt64 = 0x0008_0000
        if flags & (control | option) == (control | option), shortcutKeyCodes.contains(keyCode) { return false }
        return true
    }
}

/// The languages "Redo in another language" goes through for one dictation.
/// English and Vietnamese swap first; once every dictation language has
/// been tried, the next press returns to the language it first came out in.
public struct RedoChain: Sendable, Equatable {
    /// Whisper's language code for the first result; any language, or nil.
    public let original: String?
    public private(set) var tried: [SpeechLanguage] = []

    public init(original: String?) { self.original = original }

    public mutating func next(languages: [SpeechLanguage]) -> SpeechLanguage {
        let order = DictationLanguages.normalized(languages)
        let code = original?.lowercased()
        if let pick = order.first(where: { $0.rawValue != code && !tried.contains($0) }) {
            tried.append(pick)
            return pick
        }
        tried = []
        if let back = SpeechLanguage(rawValue: code ?? ""), back != .auto, order.contains(back) { return back }
        tried = [order[0]]
        return order[0]
    }

    public func peek(languages: [SpeechLanguage]) -> SpeechLanguage {
        var copy = self
        return copy.next(languages: languages)
    }
}

public struct LastInsertion: Sendable, Equatable {
    public var text: String
    public var processID: Int32
    public var at: Date

    public init(text: String, processID: Int32, at: Date) {
        self.text = text
        self.processID = processID
        self.at = at
    }
}

public enum ReplacementDecision: Sendable, Equatable {
    case replace(backspaces: Int)
    case copyOnly
}

public struct ReplacementGuard: Sendable {
    public static let maxAge: TimeInterval = 120
    public static let maxCharacters = 500

    public private(set) var last: LastInsertion?
    public private(set) var typedSince = false

    public init() {}

    public mutating func recordInsertion(_ insertion: LastInsertion) {
        last = insertion
        typedSince = false
    }

    public mutating func keyTyped() { typedSince = true }

    public mutating func clear() {
        last = nil
        typedSince = false
    }

    public func decide(now: Date, frontProcessID: Int32, sameFocus: Bool) -> ReplacementDecision? {
        guard let last else { return nil }
        guard sameFocus, frontProcessID == last.processID, !typedSince,
              now.timeIntervalSince(last.at) < Self.maxAge,
              !last.text.contains("\n"), !last.text.contains("\r"),
              last.text.count <= Self.maxCharacters else { return .copyOnly }
        return .replace(backspaces: last.text.count)
    }
}

extension ReplacementGuard {
    public static let maxSelectBackCharacters = 2_000
    public enum SelectBackDecision: Equatable, Sendable { case selectBack(characters: Int), copyOnly }
    public func decideSelectBack(now: Date, frontProcessID: Int32, sameFocus: Bool) -> SelectBackDecision? {
        guard let last else { return nil }
        guard sameFocus, frontProcessID == last.processID, !typedSince,
              now.timeIntervalSince(last.at) < Self.maxAge,
              last.text.count <= Self.maxSelectBackCharacters else { return .copyOnly }
        return .selectBack(characters: last.text.count)
    }
}
