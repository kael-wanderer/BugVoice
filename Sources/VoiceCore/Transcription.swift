import Foundation

public enum SpeechLanguage: String, Codable, Sendable, CaseIterable {
    case auto, vi, en
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

    public init(text: String, segments: [TranscriptSegment] = [], language: String? = nil) {
        self.text = text
        self.segments = segments
        self.language = language
    }
}

public struct TranscriptionOptions: Sendable, Equatable {
    public var language: SpeechLanguage
    /// Vocabulary hint passed to Whisper as its initial prompt. Empty = none.
    public var prompt: String

    public init(language: SpeechLanguage = .auto, prompt: String = "") {
        self.language = language
        self.prompt = prompt
    }
}

public protocol Transcriber: Sendable {
    func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript
}
