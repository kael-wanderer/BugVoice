import Testing
@testable import VoiceCore

struct MeetingRecorderPresentationTests {
    @Test func controlsMatchRecordingState() {
        #expect(MeetingRecorderPresentation.actions(for: .idle) == [.start])
        #expect(MeetingRecorderPresentation.actions(for: .recording) == [.pause, .mark, .stop])
        #expect(MeetingRecorderPresentation.actions(for: .paused) == [.resume, .mark, .stop])
        #expect(MeetingRecorderPresentation.actions(for: .transcribing).isEmpty)
    }

    @Test func emptyOrFilteredChunksDoNotReplaceLatestValidLine() {
        let valid = MeetingSegment(start: 0, end: 1, text: "Let's begin.", track: .mic)
        let first = MeetingChunkProcessingResult(record: MeetingChunkRecord(id: "a", track: .mic, offset: 0, duration: 2, requestedLanguage: .auto, state: .complete), segments: [valid])
        let empty = MeetingChunkProcessingResult(record: MeetingChunkRecord(id: "b", track: .system, offset: 2, duration: 2, requestedLanguage: .auto, state: .empty), segments: [])
        #expect(MeetingRecorderPresentation.latestLine(after: first, previous: "") == "Let's begin.")
        #expect(MeetingRecorderPresentation.latestLine(after: empty, previous: "Let's begin.") == "Let's begin.")
        #expect(MeetingRecorderPresentation.latestLine(after: nil, previous: "") == "")
    }
}
