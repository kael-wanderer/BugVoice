import Foundation

/// What Meetings → Send to Scratchpad copies into a new note.
public enum ScratchpadSendKind: String, CaseIterable, Sendable {
    case summary, actionItems, transcript

    public var title: String {
        switch self {
        case .summary: "Summary"
        case .actionItems: "Action items"
        case .transcript: "Transcript"
        }
    }

    public func noteTitle(meetingTitle: String) -> String {
        "\(meetingTitle) · \(title)"
    }

    /// Nil when the meeting has nothing of this kind yet.
    public func text(of meeting: MeetingManifest) -> String? {
        let text: String = switch self {
        case .summary: meeting.summary ?? ""
        case .actionItems: meeting.actionItems ?? ""
        case .transcript: MeetingExporter.transcriptText(meeting)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
