import Foundation
import Testing
@testable import VoiceCore

struct MeetingListProjectionTests {
    @Test func groupsNewestFirstByLocalDayAndLabelsTodayAndYesterday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date("2026-10-14T12:00:00Z")
        let meetings = [
            meeting("old", "2026-10-12T15:00:00Z"),
            meeting("today-old", "2026-10-14T08:00:00Z"),
            meeting("yesterday", "2026-10-13T19:00:00Z"),
            meeting("today-new", "2026-10-14T10:00:00Z")
        ]

        let groups = MeetingListProjection.groups(meetings: meetings, now: now, calendar: calendar)
        #expect(groups.map(\.label) == ["Today", "Yesterday", "Oct 12, 2026"])
        #expect(groups[0].meetings.map { $0.id.rawValue } == ["today-new", "today-old"])
        #expect(groups[1].meetings.map { $0.id.rawValue } == ["yesterday"])
    }

    @Test func searchMatchesTitleAndTranscriptCaseInsensitively() {
        var item = meeting("one", "2026-10-14T08:00:00Z", title: "Design review")
        item.segments = [MeetingSegment(start: 4, end: 5, text: "Ship the violet build", track: .system)]
        #expect(MeetingListProjection.matches(item, query: "DESIGN"))
        #expect(MeetingListProjection.matches(item, query: "VIOLET BUILD"))
        #expect(!MeetingListProjection.matches(item, query: "roadmap"))
        #expect(MeetingListProjection.matches(item, query: "   "))
    }

    @Test func deletedMeetingIsAbsentFromStoreListingAndSearch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(root: root)
        let kept = meeting("kept", "2026-10-14T08:00:00Z", title: "Keep")
        let deleted = meeting("deleted", "2026-10-14T09:00:00Z", title: "Delete me")
        try await store.save(kept)
        try await store.save(deleted)
        try await store.delete(id: deleted.id)
        let listed = try await store.list()
        #expect(listed.map(\.id) == [kept.id])
        #expect(!listed.contains { MeetingListProjection.matches($0, query: "delete me") })
    }

    private func meeting(_ id: String, _ timestamp: String, title: String = "Meeting") -> MeetingManifest {
        MeetingManifest(id: MeetingID(rawValue: id), title: title, startedAt: date(timestamp), state: .ready)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
