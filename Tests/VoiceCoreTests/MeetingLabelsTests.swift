import Foundation
import Testing
@testable import VoiceCore

struct MeetingLabelsTests {
    @Test func oldManifestDecodesWithoutLabels() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(JSONSerialization.jsonObject(
            with: encoder.encode(MeetingManifest(startedAt: Date(timeIntervalSince1970: 0)))
        ) as? [String: Any])
        object.removeValue(forKey: "folderID")
        object.removeValue(forKey: "tags")
        object.removeValue(forKey: "suggestedTags")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meeting = try decoder.decode(MeetingManifest.self, from: data)
        #expect(meeting.folderID == nil)
        #expect(meeting.tags.isEmpty)
        #expect(meeting.suggestedTags.isEmpty)
    }

    @Test func labelsRoundTrip() throws {
        var meeting = MeetingManifest(startedAt: Date(timeIntervalSince1970: 0))
        meeting.folderID = FolderID(rawValue: "f1")
        meeting.tags = ["acme"]
        meeting.suggestedTags = ["todo"]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeetingManifest.self, from: encoder.encode(meeting))
        #expect(decoded == meeting)
    }

    @Test func searchMatchesTags() {
        var meeting = MeetingManifest(startedAt: Date())
        meeting.tags = ["acme"]
        #expect(MeetingListProjection.matches(meeting, query: "#acme"))
        #expect(!MeetingListProjection.matches(meeting, query: "#zzz"))
    }
}
