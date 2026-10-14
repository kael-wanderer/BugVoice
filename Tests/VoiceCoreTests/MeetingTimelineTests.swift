import Testing
@testable import VoiceCore

struct MeetingTimelineTests {
    @Test func seekMapsToSegmentStart() {
        let row = MeetingSegment(start: 15.75, end: 18, text: "hello", track: .mic)
        #expect(MeetingTimeline.seekTime(for: row) == 15.75)
    }

    @Test func pausedPlaybackHasNoHighlightedRow() {
        let rows = [MeetingSegment(start: 0, end: 3, text: "hello", track: .mic)]
        #expect(MeetingTimeline.activeSegment(at: 1, segments: rows, isPlaying: false) == nil)
    }

    @Test func playingUsesStartInclusiveEndExclusiveBounds() {
        let rows = [MeetingSegment(start: 0, end: 3, text: "first", track: .mic)]
        #expect(MeetingTimeline.activeSegment(at: 0, segments: rows, isPlaying: true) == rows[0])
        #expect(MeetingTimeline.activeSegment(at: 2.999, segments: rows, isPlaying: true) == rows[0])
        #expect(MeetingTimeline.activeSegment(at: 3, segments: rows, isPlaying: true) == nil)
    }
}
