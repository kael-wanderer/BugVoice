import Foundation
import Testing
@testable import VoiceCore

struct MeetingSpeakersTests {
    @Test func olderFilesDecodeWithoutSpeakers() throws {
        let old = MeetingManifest(startedAt: Date(timeIntervalSince1970: 10), segments: [MeetingSegment(start: 0, end: 1, text: "a", track: .system)])
        let data = try JSONEncoder().encode(old)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["speakers", "speakerSplit", "speakerNamesAtSummary"] { json.removeValue(forKey: key) }
        json["segments"] = [["id": "a", "start": 0, "end": 1, "text": "a", "track": "system"]]
        let meeting = try JSONDecoder().decode(MeetingManifest.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(meeting.speakers == [])
        #expect(meeting.speakerSplit == .none)
        #expect(meeting.speakerNamesAtSummary == nil)
        #expect(meeting.segments.allSatisfy { $0.speakerID == nil && $0.speakerName == nil })
    }

    @Test func speakerNameWinsOverTrackDefault() {
        #expect(MeetingSegment(start: 0, end: 1, text: "a", track: .system).speaker == "Others")
        #expect(MeetingSegment(start: 0, end: 1, text: "a", track: .system, speakerID: "s1", speakerName: "Dani").speaker == "Dani")
    }

    @Test func splitStateRoundTrips() throws {
        for state in [SpeakerSplitState.none, .running, .done, .failed("No call audio")] {
            let data = try JSONEncoder().encode(state)
            #expect(try JSONDecoder().decode(SpeakerSplitState.self, from: data) == state)
        }
    }
}
