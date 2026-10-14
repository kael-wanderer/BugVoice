import Foundation

public enum MeetingRecorderState: Sendable {
    case idle
    case recording
    case paused
    case transcribing
}

public enum MeetingRecorderAction: Sendable {
    case start
    case pause
    case resume
    case mark
    case stop
}

/// The recorder's visible controls and latest valid transcript line.
/// Kept in VoiceCore so button availability and filtered-chunk behavior are testable.
public enum MeetingRecorderPresentation {
    public static func actions(for state: MeetingRecorderState) -> [MeetingRecorderAction] {
        switch state {
        case .idle: [.start]
        case .recording: [.pause, .mark, .stop]
        case .paused: [.resume, .mark, .stop]
        case .transcribing: []
        }
    }

    public static func latestLine(after result: MeetingChunkProcessingResult?, previous: String) -> String {
        guard let text = result?.segments.last?.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return previous
        }
        return text
    }
}
