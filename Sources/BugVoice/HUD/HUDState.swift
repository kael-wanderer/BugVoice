import Foundation
import VoiceCore

enum HUDState: Equatable {
    case listening(handsFree: Bool, app: String?, startedAt: Date, limit: TimeInterval?)
    case transcribing(language: String)
    case cleaning(model: String?, app: String?)
    case done(style: String, words: Int, seconds: Double)
    case warning(title: String, detail: String)
    case failure(title: String, detail: String)
    case nothingHeard

    /// What the user sees after a run; nil means hide immediately.
    static func from(_ r: DictationResult) -> HUDState? {
        switch r.outcome {
        case .discardedTooShort:
            return nil
        case .nothingHeard:
            return .nothingHeard
        case .transcriptionFailed:
            return .failure(title: "Transcription failed", detail: "Retry last from the menu")
        case .copiedSecureField:
            return .failure(title: "Secure field — copied", detail: "text copied, not pasted")
        case .copiedNotConsumed:
            return .warning(title: "Copied — press ⌘V", detail: "paste not picked up")
        case .inserted:
            switch r.rawReason {
            case .modelError, .modelTimeout:
                return .warning(title: "Raw — model unavailable", detail: "raw text pasted")
            case .emptyOutput, .tooLong:
                return .warning(title: "Raw — model unavailable", detail: "model output rejected")
            case .cleanupOff, .none:
                let words = r.finalText.split(whereSeparator: \.isWhitespace).count
                return .done(
                    style: r.style.rawValue.capitalized,
                    words: words,
                    seconds: (r.timings.releaseToText * 10).rounded() / 10
                )
            }
        }
    }

    /// Seconds until the pill hides on its own; nil stays until the next state.
    var autoHideAfter: TimeInterval? {
        switch self {
        case .listening, .transcribing, .cleaning: nil
        case .done, .nothingHeard: 1.2
        case .warning, .failure: 4
        }
    }
}
