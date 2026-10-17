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

extension MeetingSpeakersTests {
@Test func mostOverlapWinsAndNearTurnWithinOneSecond() {
    let lines = [line("a", 0, 4, .system), line("b", 10, 11, .system), line("c", 20, 21, .system), line("m", 0, 4, .mic)]
    let turns = [turn(0, 0, 1), turn(1, 1, 4), turn(1, 11.8, 15)]
    let placed = MeetingSpeakers.place(lines, turns: turns, tracks: [.system])
    #expect(placed == ["a": 1, "b": 1])   // b: gap 0.8 s; c: gap > 1 s; m: other track
}

@Test func tiesGoToTheEarlierTurn() {
    let placed = MeetingSpeakers.place([line("a", 0, 2, .system)], turns: [turn(3, 0, 1), turn(4, 1, 2)], tracks: [.system])
    #expect(placed == ["a": 3])
}

@Test func recordedSplitNumbersVoicesByFirstLineAndKeepsMicAsYou() {
    var meeting = recorded([line("m", 0, 2, .mic), line("a", 3, 5, .system), line("b", 6, 8, .system)])
    meeting = MeetingSpeakers.applySplit(.init(turns: [turn(7, 6, 8), turn(2, 3, 5), turn(9, 20, 21)], centroids: [:]), to: meeting, tracks: [.system])
    #expect(meeting.speakers.map(\.id) == ["you", "s1", "s2"])     // voice 9 had no line: dropped
    #expect(meeting.segments.map(\.speakerName) == ["You", "Other 1", "Other 2"])
    #expect(meeting.speakers.map(\.colorIndex) == [0, 1, 2])
    #expect(meeting.speakerSplit == .done)
    #expect(MeetingSpeakers.people(in: meeting) == 3)
    #expect(MeetingSpeakers.peopleRange(in: meeting) == 2...10)
    #expect(MeetingSpeakers.voices(forPeople: 3, in: meeting) == 2)
}

@Test func uploadSplitPlacesAllLinesWithoutYou() {
    var meeting = upload([line("a", 0, 2, .file), line("b", 3, 5, .file)])
    meeting = MeetingSpeakers.applySplit(.init(turns: [turn(0, 0, 2), turn(1, 3, 5)], centroids: [:]), to: meeting, tracks: [.file])
    #expect(meeting.speakers.map(\.id) == ["s1", "s2"])
    #expect(MeetingSpeakers.peopleRange(in: meeting) == 1...10)
    #expect(MeetingSpeakers.voices(forPeople: 2, in: meeting) == 2)
}

@Test func splitWithNoTurnsLeavesCallLinesAsOthers() {
    var meeting = recorded([line("m", 0, 2, .mic), line("a", 3, 5, .system)])
    meeting = MeetingSpeakers.applySplit(.init(turns: [], centroids: [:]), to: meeting, tracks: [.system])
    #expect(meeting.speakers.map(\.id) == ["you"])
    #expect(meeting.segments[1].speaker == "Others")
    #expect(meeting.speakerSplit == .done)
}

@Test func splitAgainCarriesNamesToClosestVoicesAndClearsLineFixes() throws {
    var meeting = recorded([line("a", 0, 2, .system), line("b", 3, 5, .system), line("c", 6, 8, .system)])
    meeting = MeetingSpeakers.applySplit(.init(turns: [turn(0, 0, 2), turn(1, 3, 8)], centroids: [0: [1, 0], 1: [0, 1]]), to: meeting, tracks: [.system])
    meeting = try MeetingSpeakers.apply(.rename(speakerID: "s1", name: "Dani"), to: meeting)
    meeting = try MeetingSpeakers.apply(.rename(speakerID: "s2", name: "Mariel"), to: meeting)
    meeting = try MeetingSpeakers.apply(.newPerson(segmentID: "c", name: "David"), to: meeting)
    // New split: voice 5 sounds like Mariel, voice 6 like Dani, voice 7 is new.
    meeting = MeetingSpeakers.applySplit(.init(turns: [turn(5, 0, 2), turn(6, 3, 5), turn(7, 6, 8)],
                                               centroids: [5: [0.1, 1], 6: [1, 0.1], 7: [0.7, 0.7]]), to: meeting, tracks: [.system])
    #expect(meeting.segments.map(\.speakerName) == ["Mariel", "Dani", "Other 3"])
    #expect(!meeting.speakers.contains { $0.id.hasPrefix("p") })
}

@Test func renameTrimsAndRefusesCaseInsensitiveDuplicates() throws {
    var meeting = split3()   // you, s1, s2 with one line each
    meeting = try MeetingSpeakers.apply(.rename(speakerID: "s1", name: "  Dani "), to: meeting)
    #expect(meeting.speakers[1].name == "Dani")
    #expect(throws: MeetingSpeakers.EditError.duplicateName("dani")) {
        try MeetingSpeakers.apply(.rename(speakerID: "s2", name: "dani"), to: meeting)
    }
    meeting = try MeetingSpeakers.apply(.rename(speakerID: "s1", name: " "), to: meeting)
    #expect(meeting.segments[1].speakerName == "Other 1")
}

@Test func assignMovesOneLineAndRemovesEmptySpeakers() throws {
    var meeting = split3()
    meeting = try MeetingSpeakers.apply(.assign(segmentID: meeting.segments[2].id, speakerID: "s1"), to: meeting)
    #expect(meeting.speakers.map(\.id) == ["you", "s1"])
    #expect(meeting.segments[2].speakerName == "Other 1")
    #expect(throws: MeetingSpeakers.EditError.unknownSpeaker) {
        try MeetingSpeakers.apply(.assign(segmentID: meeting.segments[0].id, speakerID: "s9"), to: meeting)
    }
}

@Test func newPersonGetsNextIdAndColour() throws {
    var meeting = split3()
    meeting = try MeetingSpeakers.apply(.newPerson(segmentID: meeting.segments[1].id, name: "David"), to: meeting)
    #expect(meeting.speakers.last == MeetingSpeaker(id: "p1", name: "David", colorIndex: 3, centroid: nil))
    #expect(meeting.segments[1].speaker == "David")
}

@Test func namesChangedNoticeFollowsTheSummaryStamp() throws {
    var meeting = split3()
    meeting.summary = "- Release on Friday"
    #expect(MeetingSpeakers.namesChangedSinceSummary(meeting))
    meeting.speakerNamesAtSummary = MeetingSpeakers.names(in: meeting)
    #expect(!MeetingSpeakers.namesChangedSinceSummary(meeting))
    meeting = try MeetingSpeakers.apply(.rename(speakerID: "s1", name: "Dani"), to: meeting)
    #expect(MeetingSpeakers.namesChangedSinceSummary(meeting))
    meeting.summary = nil
    #expect(!MeetingSpeakers.namesChangedSinceSummary(meeting))
}

@Test func exportAndSearchUseNames() throws {
    let meeting = try MeetingSpeakers.apply(.rename(speakerID: "s1", name: "Dani"), to: split3())
    #expect(MeetingExporter.markdown(meeting).contains("| Dani |"))
    #expect(MeetingListProjection.matches(meeting, query: "dani"))
}

    private func line(_ id: String, _ start: Double, _ end: Double, _ track: MeetingTrack) -> MeetingSegment {
        MeetingSegment(id: id, start: start, end: end, text: id, track: track)
    }
    private func turn(_ voice: Int, _ start: Double, _ end: Double) -> MeetingSpeakers.Turn {
        .init(voice: voice, start: start, end: end)
    }
    private func recorded(_ lines: [MeetingSegment]) -> MeetingManifest {
        MeetingManifest(startedAt: Date(timeIntervalSince1970: 0), segments: lines)
    }
    private func upload(_ lines: [MeetingSegment]) -> MeetingManifest {
        MeetingManifest(startedAt: Date(timeIntervalSince1970: 0), segments: lines, source: .upload)
    }
    private func split3() -> MeetingManifest {
        MeetingSpeakers.applySplit(.init(turns: [turn(0, 3, 5), turn(1, 6, 8)], centroids: [:]),
            to: recorded([line("m", 0, 2, .mic), line("a", 3, 5, .system), line("b", 6, 8, .system)]), tracks: [.system])
    }
}
