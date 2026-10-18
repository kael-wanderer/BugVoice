import Foundation

public enum ShortcutAction: String, CaseIterable, Codable, Sendable {
    case pasteLast, toggleMeeting, openApp, newNote

    public var title: String {
        switch self {
        case .pasteLast: "Paste last dictation"
        case .toggleMeeting: "Start or stop a meeting"
        case .openApp: "Open BugVoice"
        case .newNote: "Floating scratchpad"
        }
    }
}

public struct ShortcutSettings: Codable, Equatable, Sendable {
    private var pasteLast = "V"
    private var toggleMeeting = "M"
    private var openApp = "B"
    private var newNote = "N"

    public init() {}

    public func letter(for action: ShortcutAction) -> String {
        switch action {
        case .pasteLast: pasteLast
        case .toggleMeeting: toggleMeeting
        case .openApp: openApp
        case .newNote: newNote
        }
    }

    @discardableResult
    public mutating func setLetter(_ letter: String, for action: ShortcutAction) -> Bool {
        let normalized = letter.uppercased()
        guard Self.isValid(normalized),
              !ShortcutAction.allCases.contains(where: { $0 != action && self.letter(for: $0) == normalized })
        else { return false }

        switch action {
        case .pasteLast: pasteLast = normalized
        case .toggleMeeting: toggleMeeting = normalized
        case .openApp: openApp = normalized
        case .newNote: newNote = normalized
        }
        return true
    }

    private static func isValid(_ letter: String) -> Bool {
        letter.count == 1 && letter.unicodeScalars.first.map { (65...90).contains(Int($0.value)) } == true
    }

    private static func defaultLetter(for action: ShortcutAction) -> String {
        switch action {
        case .pasteLast: "V"
        case .toggleMeeting: "M"
        case .openApp: "B"
        case .newNote: "N"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case pasteLast, toggleMeeting, openApp, newNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var values: [ShortcutAction: String] = [:]
        for action in ShortcutAction.allCases {
            if let raw = try? container.decode(String.self, forKey: CodingKeys(rawValue: action.rawValue)!) {
                let normalized = raw.uppercased()
                if Self.isValid(normalized) { values[action] = normalized }
            }
        }

        // Defaults take priority over an explicitly stored duplicate.
        var used = Set(ShortcutAction.allCases.filter { values[$0] == nil || values[$0] == Self.defaultLetter(for: $0) }
            .map { Self.defaultLetter(for: $0) })
        for action in ShortcutAction.allCases where values[action] != nil && values[action] != Self.defaultLetter(for: action) {
            let candidate = values[action]!
            if !used.insert(candidate).inserted { values[action] = Self.defaultLetter(for: action) }
        }

        pasteLast = values[.pasteLast] ?? Self.defaultLetter(for: .pasteLast)
        toggleMeeting = values[.toggleMeeting] ?? Self.defaultLetter(for: .toggleMeeting)
        openApp = values[.openApp] ?? Self.defaultLetter(for: .openApp)
        newNote = values[.newNote] ?? Self.defaultLetter(for: .newNote)
    }
}

public enum ShortcutKeys {
    public static func keyCode(forLetter letter: String) -> Int? {
        switch letter.uppercased() {
        case "A": 0
        case "B": 11
        case "C": 8
        case "D": 2
        case "E": 14
        case "F": 3
        case "G": 5
        case "H": 4
        case "I": 34
        case "J": 38
        case "K": 40
        case "L": 37
        case "M": 46
        case "N": 45
        case "O": 31
        case "P": 35
        case "Q": 12
        case "R": 15
        case "S": 1
        case "T": 17
        case "U": 32
        case "V": 9
        case "W": 13
        case "X": 7
        case "Y": 16
        case "Z": 6
        default: nil
        }
    }
}
