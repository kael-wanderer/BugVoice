import Foundation

public enum SpeechLanguage: String, Codable, Sendable, CaseIterable {
    /// Spanish is offered for meetings and uploads only; dictation keeps Auto, Vietnamese and English.
    case auto, vi, en, es

    public var displayName: String {
        switch self {
        case .auto: "Auto"
        case .vi: "Vietnamese"
        case .en: "English"
        case .es: "Spanish"
        }
    }
}

/// The languages spoken in a meeting. Whisper's automatic detection is kept
/// to this set: a chunk it hears in any other language is redone in one of them.
public enum MeetingLanguages {
    public static let choices: [SpeechLanguage] = [.en, .vi, .es]
    public static let defaults: [SpeechLanguage] = [.en, .vi]

    /// Drops Auto and repeats, keeps order; an empty result falls back to the defaults.
    public static func normalized(_ languages: [SpeechLanguage]) -> [SpeechLanguage] {
        var seen = Set<SpeechLanguage>()
        let kept = languages.filter { $0 != .auto && seen.insert($0).inserted }
        return kept.isEmpty ? defaults : kept
    }
}

public enum TranscriptionPriority: Int, Codable, Sendable {
    case meeting = 0
    case dictation = 1
    case preview = 2
}

/// One timed piece of a transcript. Dictation ignores timing; Meetings
/// (sub-project 2) builds its timeline from it.
public struct TranscriptSegment: Sendable, Equatable, Codable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct Transcript: Sendable, Equatable {
    public var text: String
    public var segments: [TranscriptSegment]
    public var language: String?
    /// Whisper's language log probabilities, keyed by language code. Filled
    /// only when the detected language is not one of `expectedLanguages`.
    public var languageScores: [String: Float]

    public init(text: String, segments: [TranscriptSegment] = [], language: String? = nil, languageScores: [String: Float] = [:]) {
        self.text = text
        self.segments = segments
        self.language = language
        self.languageScores = languageScores
    }
}

public struct TranscriptionOptions: Sendable, Equatable {
    public var language: SpeechLanguage
    /// Vocabulary hint passed to Whisper as its initial prompt. Empty = none.
    public var prompt: String
    public var timestamps: Bool
    public var priority: TranscriptionPriority
    /// Languages the speaker uses. With automatic detection, a result in
    /// another language comes back with `Transcript.languageScores` so the
    /// caller can redo it. Empty = no expectation.
    public var expectedLanguages: [SpeechLanguage]

    public init(
        language: SpeechLanguage = .auto,
        prompt: String = "",
        timestamps: Bool = false,
        priority: TranscriptionPriority = .dictation,
        expectedLanguages: [SpeechLanguage] = []
    ) {
        self.language = language
        self.prompt = prompt
        self.timestamps = timestamps
        self.priority = priority
        self.expectedLanguages = expectedLanguages
    }
}

public protocol Transcriber: Sendable {
    func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript
}
