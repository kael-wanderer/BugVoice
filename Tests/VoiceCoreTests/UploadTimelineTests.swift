import Foundation
import Testing
@testable import VoiceCore

struct UploadTimelineTests {
    @Test func tiedTracksHaveOneStableOrder() {
        let segments = [MeetingTrack.file, .system, .mic].map { track in
            MeetingSegment(id: track.rawValue, start: 0, end: 1, text: track.rawValue, track: track)
        }
        let chunks = segments.map { segment in
            MeetingChunkProcessingResult(
                record: MeetingChunkRecord(id: segment.id, track: segment.track, offset: 0, duration: 1, requestedLanguage: .auto, state: .complete),
                segments: [segment]
            )
        }
        #expect(MeetingTranscriptMerger.merge(chunks).map(\.track) == [.mic, .system, .file])
        let manifest = MeetingManifest(startedAt: Date(), segments: segments)
        let exported = MeetingExporter.srt(manifest)
        #expect(exported.range(of: "You:")!.lowerBound < exported.range(of: "Others:")!.lowerBound)
        #expect(exported.range(of: "Others:")!.lowerBound < exported.range(of: "Speaker:")!.lowerBound)
        #expect(MeetingTrack.recordingTracks == [.mic, .system])
    }

    @Test func threeHoursKeepLastPartialRange() {
        let count = 10_803 * 16_000
        let ranges = MeetingChunkPlanner.plan(sampleCount: count)
        #expect(ranges.first?.lowerBound == 0)
        #expect(ranges.last?.upperBound == count)
        #expect(ranges.allSatisfy { $0.count <= 480_000 })
        #expect(zip(ranges, ranges.dropFirst()).allSatisfy { $0.upperBound - $1.lowerBound == 16_000 })
        let segment = MeetingSegment(start: 10_800, end: 10_803, text: "Last words", track: .file)
        let manifest = MeetingManifest(startedAt: Date(), segments: [segment])
        #expect(MeetingExporter.srt(manifest).contains("03:00:00,000 --> 03:00:03,000"))
    }
}
