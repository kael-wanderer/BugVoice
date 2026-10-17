import Foundation
import Testing
@testable import VoiceCore

struct UploadManifestTests {
    @Test func legacyDefaultsAndBothSourcesRoundTrip() throws {
        let old = MeetingManifest(startedAt: Date(timeIntervalSince1970: 10))
        let data = try JSONEncoder().encode(old)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "source")
        object.removeValue(forKey: "sourceFileName")
        object.removeValue(forKey: "importedAt")
        let legacy = try JSONDecoder().decode(
            MeetingManifest.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(legacy.source == .recording)
        #expect(legacy.sourceFileName == nil)
        #expect(legacy.importedAt == nil)
        for source in [MeetingSource.recording, .upload] {
            var meeting = legacy
            meeting.source = source
            meeting.sourceFileName = source == .upload ? "review.MOV" : nil
            meeting.importedAt = source == .upload ? Date(timeIntervalSince1970: 100) : nil
            let decoded = try JSONDecoder().decode(MeetingManifest.self, from: JSONEncoder().encode(meeting))
            #expect(decoded == meeting)
            #expect(decoded.schemaVersion == 1)
        }
        object.removeValue(forKey: "duration")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MeetingManifest.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test func speakerAndExportsRetainRecordedLabels() throws {
        let tracks: [MeetingTrack] = [.mic, .system, .file]
        let segments = tracks.enumerated().map { index, track in
            MeetingSegment(id: "s\(index)", start: Double(index), end: Double(index + 1), text: "Words", track: track)
        }
        #expect(segments.map(\.speaker) == ["You", "Others", "Speaker"])
        let meeting = MeetingManifest(startedAt: Date(), state: .ready, segments: segments)
        #expect(MeetingExporter.markdown(meeting).contains("0:02 | Speaker | Words"))
        #expect(MeetingExporter.srt(meeting).contains("Speaker: Words"))
        #expect(try JSONDecoder().decode(MeetingTrack.self, from: Data(#""file""#.utf8)) == .file)
    }

    @Test func retentionUsesImportDateAndExcludesActiveStates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var meeting = MeetingManifest(startedAt: .distantPast, endedAt: .distantPast, state: .ready)
        meeting.source = .upload
        meeting.importedAt = now
        #expect(!MeetingRetention.expired(meeting, policy: .days30, now: now))
        meeting.importedAt = now.addingTimeInterval(-30 * 86_400)
        #expect(MeetingRetention.expired(meeting, policy: .days30, now: now))
        for state in [MeetingState.interrupted, .transcribing, .recording, .paused] {
            meeting.state = state
            #expect(!MeetingRetention.expired(meeting, policy: .days30, now: now))
        }
        meeting.state = .ready
        meeting.source = .recording
        meeting.importedAt = now
        #expect(MeetingRetention.expired(meeting, policy: .days30, now: now))
    }

    @Test func manifestKeepsUploadJobFields() throws {
        var meeting = MeetingManifest(startedAt: Date(timeIntervalSince1970: 10), source: .upload)
        meeting.uploadJobID = UUID()
        meeting.addedBy = "claude-code"
        let decoded = try JSONDecoder().decode(MeetingManifest.self, from: JSONEncoder().encode(meeting))
        #expect(decoded == meeting)

        let old = MeetingManifest(startedAt: Date(timeIntervalSince1970: 10))
        let data = try JSONEncoder().encode(old)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["uploadJobID"] == nil && object["addedBy"] == nil)
        let legacy = try JSONDecoder().decode(MeetingManifest.self, from: data)
        #expect(legacy.uploadJobID == nil && legacy.addedBy == nil)
    }
}
