import Foundation
import Testing
@testable import VoiceCore

struct ScratchpadSendTests {
    func meeting() -> MeetingManifest {
        var meeting = MeetingManifest(title: "Standup", startedAt: Date(timeIntervalSince1970: 0))
        meeting.segments = [
            MeetingSegment(id: "2", start: 65, end: 70, text: "Ship it\ntoday.", track: .system),
            MeetingSegment(id: "1", start: 5, end: 9, text: "Status?", track: .mic),
        ]
        meeting.summary = "  Shipped.  "
        return meeting
    }

    @Test func transcriptIsOneLinePerSegmentInOrder() {
        #expect(MeetingExporter.transcriptText(meeting()) == "0:05 You: Status?\n1:05 Others: Ship it today.")
    }

    @Test func titlesAndTexts() {
        #expect(ScratchpadSendKind.summary.noteTitle(meetingTitle: "Standup") == "Standup · Summary")
        #expect(ScratchpadSendKind.actionItems.noteTitle(meetingTitle: "Standup") == "Standup · Action items")
        #expect(ScratchpadSendKind.summary.text(of: meeting()) == "Shipped.")
        #expect(ScratchpadSendKind.actionItems.text(of: meeting()) == nil)
        #expect(ScratchpadSendKind.transcript.text(of: MeetingManifest(startedAt: Date())) == nil)
    }

    @Test func myNotesComeAfterActionItems() {
        var withNotes = meeting()
        withNotes.notes = "\n## Decisions\n- Ship Friday\n"
        #expect(ScratchpadSendKind.allCases == [.summary, .actionItems, .notes, .transcript])
        #expect(ScratchpadSendKind.notes.noteTitle(meetingTitle: "Standup") == "Standup · My notes")
        #expect(ScratchpadSendKind.notes.text(of: withNotes) == "## Decisions\n- Ship Friday")
        #expect(ScratchpadSendKind.notes.text(of: meeting()) == nil)
    }
}
