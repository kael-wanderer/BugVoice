import Foundation
import VoiceCore

enum HUDState: Equatable {
    case listening(handsFree: Bool, app: String?, startedAt: Date, limit: TimeInterval?, language: String, languageChanged: Bool)
    case commandListening(selectionCharacters: Int?, app: String?, startedAt: Date, language: String, languageChanged: Bool)
    case rewriting(model: String?, app: String?)
    case transcribing(language: String)
    case cleaning(model: String?, app: String?)
    case done(style: String, words: Int, seconds: Double)
    case warning(title: String, detail: String)
    case failure(title: String, detail: String)
    case message(title: String, detail: String?)
    case nothingHeard

    static let secureFieldCopied = HUDState.failure(title: "Secure field — copied", detail: "text copied, not pasted")

    /// What the user sees after a run; nil means hide immediately.
    static func from(_ r: DictationResult) -> HUDState? {
        switch r.outcome {
        case .discardedTooShort, .cancelled:
            return nil
        case .nothingHeard:
            return .nothingHeard
        case .transcriptionFailed:
            return .failure(title: "Transcription failed", detail: "Retry last from the menu")
        case .copiedSecureField:
            return .secureFieldCopied
        case .copiedNotConsumed:
            return .warning(title: "Copied — press ⌘V", detail: "paste not picked up")
        case .noteDeleted:
            return .warning(title: "Note deleted — dictation was not added", detail: "The note was deleted before insertion")
        case .noteSaveFailed:
            return .warning(title: "Could not save dictation", detail: "Open Notes to copy the text")
        case .insertedInNote:
            return .done(
                style: Style.document.title,
                words: r.finalText.split(whereSeparator: \.isWhitespace).count,
                seconds: (r.timings.releaseToText * 10).rounded() / 10
            )
        case .inserted:
            switch r.rawReason {
            case .detailChanged:
                return .warning(title: FidelityCheck.hudTitle(r.fidelityIssues, pastedRaw: true), detail: "raw text pasted")
            case .modelError, .modelTimeout:
                return .warning(title: "Raw — model unavailable", detail: "raw text pasted")
            case .emptyOutput, .tooLong, .placeholderLost:
                return .warning(title: "Raw — model unavailable", detail: "model output rejected")
            case .cleanupOff, .none:
                let words = r.finalText.split(whereSeparator: \.isWhitespace).count
                return .done(
                    style: r.style.title,
                    words: words,
                    seconds: (r.timings.releaseToText * 10).rounded() / 10
                )
            }
        }
    }

    /// Seconds until the pill hides on its own; nil stays until the next state.
    var autoHideAfter: TimeInterval? {
        switch self {
        case .listening, .commandListening, .rewriting, .transcribing, .cleaning: nil
        case .done, .nothingHeard, .message: 1.2
        case .warning, .failure: 4
        }
    }
}
