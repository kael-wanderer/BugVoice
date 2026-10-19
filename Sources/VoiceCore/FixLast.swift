import Foundation

public enum FixKind: String, Codable, Sendable { case raw, otherLanguage }

public enum FixLast {
    public static let syntheticEventMarker: Int64 = 0x4256_5043

    public static func otherLanguage(of detected: String?) -> SpeechLanguage {
        detected?.lowercased() == "en" ? .vi : .en
    }

    public static func countsAsTyping(keyCode: Int64, flags: UInt64, userData: Int64, shortcutKeyCodes: Set<Int64>) -> Bool {
        guard userData != syntheticEventMarker else { return false }
        let control: UInt64 = 0x0004_0000
        let option: UInt64 = 0x0008_0000
        if flags & (control | option) == (control | option), shortcutKeyCodes.contains(keyCode) { return false }
        return true
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
