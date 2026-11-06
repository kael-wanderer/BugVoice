import Foundation

/// The first-run onboarding window's steps, in order.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, hotkey, permissions, speech, cleanup, tryIt, finish

    /// 1-based position.
    public var number: Int { rawValue + 1 }
    public var next: OnboardingStep? { Self(rawValue: rawValue + 1) }
    public var previous: OnboardingStep? { Self(rawValue: rawValue - 1) }
    public var showsSkip: Bool {
        switch self {
        case .welcome, .speech, .finish: false
        default: true
        }
    }
    public var probesHotkey: Bool { self == .hotkey }
}

/// What the person picked for text cleanup.
public enum CleanupChoice: Equatable, Sendable {
    case builtIn(modelID: String)
    case appleIntelligence
    case connection(ModelConnection, local: Bool)
    case none
}

/// The kinds of cleanup the cleanup step can offer.
public enum CleanupChoiceKind: Sendable {
    case builtIn, appleIntelligence, localApp, cloud, none
}

public enum OnboardingSetup {
    /// Writes the choice into `models`. Connections are replaced by id, never duplicated.
    public static func apply(_ choice: CleanupChoice, to models: inout ModelSettings) {
        switch choice {
        case .builtIn:
            break // Task 10 wires the built-in engine.
        case .appleIntelligence:
            models.dictation = ModelUse(engine: .appleIntelligence)
        case .connection(let connection, let local):
            if let i = models.connections.firstIndex(where: { $0.id == connection.id }) {
                models.connections[i] = connection
            } else {
                models.connections.append(connection)
            }
            models.dictation = ModelUse(engine: .connection(connection.id), disableThinking: local)
            models.meetings = ModelUse(engine: .connection(connection.id))
            models.notes = nil
        case .none:
            models.dictation = ModelUse(engine: .none)
        }
    }

    /// The choices to show, in display order.
    public static func choices(appleIntelligence: Bool, builtInEnabled: Bool) -> [CleanupChoiceKind] {
        var kinds: [CleanupChoiceKind] = []
        if builtInEnabled { kinds.append(.builtIn) }
        if appleIntelligence { kinds.append(.appleIntelligence) }
        return kinds + [.localApp, .cloud, .none]
    }
}
