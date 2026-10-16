import Foundation

/// What Meetings → Send to Scratchpad copies into a new note.
public enum ScratchpadSendKind: String, CaseIterable, Sendable {
    case summary, actionItems, notes, transcript

    public var title: String {
        switch self {
        case .summary: "Summary"
        case .actionItems: "Action items"
        case .notes: "My notes"
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
        case .notes: meeting.notes
        case .transcript: MeetingExporter.transcriptText(meeting)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
