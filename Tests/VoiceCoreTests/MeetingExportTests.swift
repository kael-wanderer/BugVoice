import Foundation
import Testing
@testable import VoiceCore

struct MeetingExportTests {
    @Test func srtFormatsMillisecondCuesInTimelineOrderAndFlattensNewlines() {
        let meeting = manifest(segments: [
            segment(start: 61.25, end: 62.4, text: "Xin chào\nteam", track: .system),
            segment(start: 1.1, end: 2, text: "Let's begin", track: .mic)
        ])
        let output = MeetingExporter.srt(meeting)

        #expect(output == "1\n00:00:01,100 --> 00:00:02,000\nYou: Let's begin\n\n2\n00:01:01,250 --> 00:01:02,400\nOthers: Xin chào team")
    }

    @Test func markdownIncludesMeetingMetadataAndTranscriptRows() {
        var meeting = manifest(segments: [segment(start: 5, end: 6, text: "Xin chào", track: .system)])
        meeting.summary = "A short summary"
        meeting.actionItems = "- Alex: Send draft"
        let output = MeetingExporter.markdown(meeting)

        #expect(output.contains("# Planning\n"))
        #expect(output.contains("2026-10-14"))
        #expect(output.contains("## Summary\nA short summary"))
        #expect(output.contains("## Action items\n- Alex: Send draft"))
        #expect(output.contains("0:05 | Others | Xin chào"))
    }

    private func manifest(segments: [MeetingSegment]) -> MeetingManifest {
        MeetingManifest(
            id: MeetingID(rawValue: "meeting"), title: "Planning",
            startedAt: date("2026-10-14T01:02:03Z"), duration: 90,
            state: .ready, segments: segments
        )
    }

    private func segment(start: Double, end: Double, text: String, track: MeetingTrack) -> MeetingSegment {
        MeetingSegment(start: start, end: end, text: text, track: track)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
