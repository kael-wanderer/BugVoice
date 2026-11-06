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
        case .builtIn(let modelID):
            models.dictation = ModelUse(engine: .builtIn(modelID), disableThinking: true)
            models.notes = nil
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

/// What the Try it step shows after a dictation into its own text box.
public struct TryItResult: Equatable, Sendable {
    public var text: String
    public var speechSeconds: Double
    /// Nil when no cleanup model ran.
    public var cleanupSeconds: Double?
    public var cleanupName: String?
    /// Plain-English reason the run did not fully work, or nil when it did.
    public var problem: String?

    public init(text: String, speechSeconds: Double, cleanupSeconds: Double?, cleanupName: String?, problem: String?) {
        self.text = text
        self.speechSeconds = speechSeconds
        self.cleanupSeconds = cleanupSeconds
        self.cleanupName = cleanupName
        self.problem = problem
    }

    public init(_ result: DictationResult, cleanupName: String?) {
        let cleaned = result.cleaned != nil
        text = result.finalText
        speechSeconds = result.timings.transcribe
        cleanupSeconds = cleaned ? result.timings.clean : nil
        self.cleanupName = cleaned ? cleanupName : nil
        switch result.outcome {
        case .inserted:
            switch result.rawReason {
            case nil, .cleanupOff?: problem = nil
            case .detailChanged?: problem = "Cleanup changed your words, so the raw text was pasted."
            case .modelTimeout?: problem = "Cleanup failed: the model took too long, so the raw text was pasted."
            case .modelError?: problem = "Cleanup failed: \(result.errorMessage ?? "the model returned an error"). The raw text was pasted."
            case .emptyOutput?, .tooLong?, .placeholderLost?: problem = "Cleanup failed: the model's answer was not usable, so the raw text was pasted."
            }
        case .copiedNotConsumed, .copiedFocusChanged, .copiedFieldChanged, .copiedSecureField:
            problem = "The text was copied but not pasted. Click the box and try again."
        case .transcriptionFailed: problem = result.errorMessage ?? "Speech to text failed."
        case .nothingHeard: problem = "No speech was heard. Check the microphone and try again."
        case .discardedTooShort: problem = "That was too short. Hold the key while you speak."
        case .cancelled: problem = "Cancelled."
        case .insertedInNote, .noteDeleted, .noteSaveFailed: problem = "The text went to a note, not this box."
        }
    }
}
