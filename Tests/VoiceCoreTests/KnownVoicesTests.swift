import Foundation
import Testing
@testable import VoiceCore

struct KnownVoicesTests {
    @Test func olderFilesDecodeWithoutKnownVoiceFields() throws {
        let meeting = recorded()
        let data = try JSONEncoder().encode(meeting)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "declinedVoices")
        json["speakers"] = [["id": "s1", "colorIndex": 1]]
        let decoded = try JSONDecoder().decode(MeetingManifest.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.declinedVoices == [])
        #expect(decoded.speakers.first?.suggestion == nil)
        let settings = try JSONDecoder().decode(MeetingSettings.self, from: Data("{}".utf8))
        #expect(settings.suggestKnownVoices)
    }

    @Test func knownVoiceFieldsRoundTrip() throws {
        var meeting = recorded()
        meeting.declinedVoices = ["Mariel"]
        meeting.speakers[1].suggestion = SpeakerSuggestion(name: "Dani", distance: 0.12)
        let decoded = try JSONDecoder().decode(MeetingManifest.self, from: JSONEncoder().encode(meeting))
        #expect(decoded == meeting)
    }

    @Test func voiceprintIsTheMeanOfContributions() {
        let voice = KnownVoice(name: "Dani", contributions: [
            .init(meetingID: MeetingID(rawValue: "a"), centroid: [1, 0]),
            .init(meetingID: MeetingID(rawValue: "b"), centroid: [0, 1]),
        ], updatedAt: .distantPast)
        #expect(voice.voiceprint == [0.5, 0.5])
    }

    @Test func closestPairWinsWhenTwoSpeakersAreNearOneVoice() {
        // s1 at 0.05 from Dani, s2 at 0.15 from Dani: only s1 gets Dani.
        let meeting = KnownVoices.suggest(in: recorded(s1: unit(0.05), s2: unit(0.15)), voices: [voice("Dani", unit(0))])
        #expect(meeting.speakers[1].suggestion?.name == "Dani")
        #expect(meeting.speakers[2].suggestion == nil)
    }

    @Test func thresholdIsInclusiveAtTwoTenths() {
        let at = KnownVoices.suggest(in: recorded(s1: unit(0.2)), voices: [voice("Dani", unit(0))])
        #expect(at.speakers[1].suggestion?.name == "Dani")
        #expect(abs((at.speakers[1].suggestion?.distance ?? 0) - 0.2) < 1e-6)
        let over = KnownVoices.suggest(in: recorded(s1: unit(0.21)), voices: [voice("Dani", unit(0))])
        #expect(over.speakers[1].suggestion == nil)
    }

    @Test func marginRefusesTwoVoicesThatAreTooClose() {
        // s1 is 0.05 from Dani. Mariel 5° the other way is about 0.08 from s1: under the 0.1 margin.
        let close = KnownVoices.suggest(in: recorded(s1: unit(0.05)), voices: [voice("Dani", unit(0)), voice("Mariel", angle(-5))])
        #expect(close.speakers[1].suggestion == nil)
        // Mariel 15° the other way is about 0.16 from s1: far enough.
        let apart = KnownVoices.suggest(in: recorded(s1: unit(0.05)), voices: [voice("Dani", unit(0)), voice("Mariel", angle(-15))])
        #expect(apart.speakers[1].suggestion?.name == "Dani")
    }

    @Test func namedAndDeclinedNamesAreSkipped() {
        var meeting = recorded(s1: unit(0.05), s2: unit(0.05))
        meeting.speakers[1].name = "dani"
        meeting.declinedVoices = ["Mariel"]
        let suggested = KnownVoices.suggest(in: meeting, voices: [voice("Dani", unit(0)), voice("Mariel", unit(0.6))])
        #expect(suggested.speakers[1].suggestion == nil)
        #expect(suggested.speakers[2].suggestion == nil)
    }

    @Test func suggestionIsNotAName() throws {
        let meeting = KnownVoices.suggest(in: recorded(s1: unit(0.05)), voices: [voice("Dani", unit(0))])
        #expect(meeting.segments[1].speaker == "Other 1")
        #expect(MeetingExporter.markdown(meeting).contains("| Other 1 |"))
    }

    @Test func acceptNamesTheSpeakerAndKeepsTheDistance() throws {
        var meeting = KnownVoices.suggest(in: recorded(s1: unit(0.05)), voices: [voice("Dani", unit(0))])
        meeting = try MeetingSpeakers.apply(.accept(speakerID: "s1"), to: meeting)
        #expect(meeting.speakers[1].name == "Dani")
        #expect(meeting.speakers[1].suggestion?.name == "Dani")
        #expect(meeting.segments[1].speaker == "Dani")
    }

    @Test func declineRemembersTheNameAndClears() throws {
        var meeting = KnownVoices.suggest(in: recorded(s1: unit(0.05)), voices: [voice("Dani", unit(0))])
        meeting = try MeetingSpeakers.apply(.decline(speakerID: "s1"), to: meeting)
        #expect(meeting.speakers[1].suggestion == nil)
        #expect(meeting.declinedVoices == ["Dani"])
        #expect(KnownVoices.suggest(in: meeting, voices: [voice("Dani", unit(0))]).speakers[1].suggestion == nil)
    }

    @Test func renameClearsTheSuggestion() throws {
        var meeting = KnownVoices.suggest(in: recorded(s1: unit(0.05)), voices: [voice("Dani", unit(0))])
        meeting = try MeetingSpeakers.apply(.rename(speakerID: "s1", name: "David"), to: meeting)
        #expect(meeting.speakers[1].suggestion == nil)
    }

    @Test func renameMovesTheContributionAndClearRemovesIt() throws {
        let id = MeetingID(rawValue: "m1")
        let before = recorded(id: id, s1: unit(0))
        let dani = try MeetingSpeakers.apply(.rename(speakerID: "s1", name: "Dani"), to: before)
        var file = KnownVoices.record(.edit(speakerID: "s1"), before: before, after: dani, in: KnownVoiceFile(), now: .distantPast)
        #expect(file.voices.map(\.name) == ["Dani"])
        let david = try MeetingSpeakers.apply(.rename(speakerID: "s1", name: "David"), to: dani)
        file = KnownVoices.record(.edit(speakerID: "s1"), before: dani, after: david, in: file, now: .distantPast)
        #expect(file.voices.map(\.name) == ["David"])
        let cleared = try MeetingSpeakers.apply(.rename(speakerID: "s1", name: ""), to: david)
        file = KnownVoices.record(.edit(speakerID: "s1"), before: david, after: cleared, in: file, now: .distantPast)
        #expect(file.voices.isEmpty)
    }

    @Test func typedNameJoinsTheSavedVoiceAndReplacesThisMeeting() throws {
        let id = MeetingID(rawValue: "m2")
        let before = recorded(id: id, s1: unit(0.3))
        let after = try MeetingSpeakers.apply(.rename(speakerID: "s1", name: "dani"), to: before)
        let saved = KnownVoiceFile(voices: [voice("Dani", unit(0), meeting: "m1")])
        var file = KnownVoices.record(.edit(speakerID: "s1"), before: before, after: after, in: saved, now: .distantPast)
        #expect(file.voices.count == 1)
        #expect(file.voices[0].contributions.map(\.meetingID) == [MeetingID(rawValue: "m1"), id])
        file = KnownVoices.record(.edit(speakerID: "s1"), before: before, after: after, in: file, now: .distantPast)
        #expect(file.voices[0].contributions.count == 2)
    }

    @Test func splitReplacesExistingContributionsAndAddsNone() {
        let id = MeetingID(rawValue: "m1")
        var before = recorded(id: id, s1: unit(0), s2: unit(0.5))
        before.speakers[1].name = "Dani"; before.speakers[2].name = "Mariel"
        var after = before
        after.speakers[1].centroid = unit(0.01)
        // Dani was saved from this meeting; Mariel was deleted in Settings.
        let file = KnownVoices.record(.split, before: before, after: after,
            in: KnownVoiceFile(voices: [voice("Dani", unit(0), meeting: "m1")]), now: .distantPast)
        #expect(file.voices.map(\.name) == ["Dani"])
        #expect(file.voices[0].contributions == [.init(meetingID: id, centroid: unit(0.01))])
    }

    @Test func splitDropsNamesTheMeetingNoLongerHas() {
        let id = MeetingID(rawValue: "m1")
        var before = recorded(id: id, s1: unit(0))
        before.speakers[1].name = "Dani"
        var after = before
        after.speakers[1].name = nil
        let file = KnownVoices.record(.split, before: before, after: after,
            in: KnownVoiceFile(voices: [voice("Dani", unit(0), meeting: "m1")]), now: .distantPast)
        #expect(file.voices.isEmpty)
    }

    @Test func pruneAndDelete() {
        let file = KnownVoiceFile(voices: [voice("Dani", unit(0), meeting: "m1"), voice("Mariel", unit(0.5), meeting: "m2")])
        #expect(KnownVoices.prune(file, keeping: [MeetingID(rawValue: "m2")]).voices.map(\.name) == ["Mariel"])
        #expect(KnownVoices.delete(name: "mariel", from: file).voices.map(\.name) == ["Dani"])
    }

    @Test func storeWritesOwnerOnlyFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kv-\(UUID().uuidString)/BugVoice")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let store = KnownVoiceStore(url: dir.appendingPathComponent("voices.json"))
        #expect(try await store.load() == KnownVoiceFile())
        let saved = KnownVoiceFile(voices: [voice("Dani", unit(0))])
        _ = try await store.update { _ in saved }
        #expect(try await store.load() == saved)
        let file = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("voices.json").path)
        let folder = try FileManager.default.attributesOfItem(atPath: dir.path)
        #expect((file[.posixPermissions] as? Int) == 0o600)
        #expect((folder[.posixPermissions] as? Int) == 0o700)
    }

    // MARK: helpers

    /// A unit vector whose cosine distance from `unit(0)` is `distance`.
    private func unit(_ distance: Double) -> [Float] {
        let cos = 1 - distance
        return [Float(cos), Float((1 - cos * cos).squareRoot())]
    }
    private func angle(_ degrees: Double) -> [Float] {
        [Float(cos(degrees * .pi / 180)), Float(sin(degrees * .pi / 180))]
    }
    private func voice(_ name: String, _ centroid: [Float], meeting: String = "old") -> KnownVoice {
        KnownVoice(name: name, contributions: [.init(meetingID: MeetingID(rawValue: meeting), centroid: centroid)], updatedAt: .distantPast)
    }
    private func recorded(id: MeetingID = MeetingID(rawValue: "m0"), s1: [Float] = [1, 0], s2: [Float]? = nil) -> MeetingManifest {
        var lines = [MeetingSegment(id: "m", start: 0, end: 1, text: "m", track: .mic),
                     MeetingSegment(id: "a", start: 2, end: 3, text: "a", track: .system)]
        var turns = [MeetingSpeakers.Turn(voice: 0, start: 2, end: 3)]
        var centroids = [0: s1]
        if let s2 {
            lines.append(MeetingSegment(id: "b", start: 4, end: 5, text: "b", track: .system))
            turns.append(.init(voice: 1, start: 4, end: 5)); centroids[1] = s2
        }
        var meeting = MeetingManifest(startedAt: Date(timeIntervalSince1970: 0), segments: lines)
        meeting.id = id
        return MeetingSpeakers.applySplit(.init(turns: turns, centroids: centroids), to: meeting, tracks: [.system])
    }
}

extension KnownVoicesTests {
    @Test func voiceprintUsesTheMostCommonCentroidLength() {
        let voice = KnownVoice(name: "Dani", contributions: [
            .init(meetingID: MeetingID(rawValue: "a"), centroid: [1, 0, 0]),
            .init(meetingID: MeetingID(rawValue: "b"), centroid: [1, 0]),
            .init(meetingID: MeetingID(rawValue: "c"), centroid: [0, 1]),
        ], updatedAt: .distantPast)
        #expect(voice.voiceprint == [0.5, 0.5])
    }

    @Test func splitAgainKeepsTheConfirmedSuggestion() throws {
        var meeting = KnownVoices.suggest(in: recorded(s1: unit(0.05)), voices: [voice("Dani", unit(0))])
        meeting = try MeetingSpeakers.apply(.accept(speakerID: "s1"), to: meeting)
        let again = MeetingSpeakers.applySplit(.init(turns: [.init(voice: 4, start: 2, end: 3)], centroids: [4: unit(0.06)]),
                                               to: meeting, tracks: [.system])
        #expect(again.speakers[1].name == "Dani")
        #expect(again.speakers[1].suggestion == SpeakerSuggestion(name: "Dani", distance: meeting.speakers[1].suggestion!.distance))
    }

    @Test func storeWritesNothingWhenNothingChanges() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kv-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("voices.json")
        _ = try await KnownVoiceStore(url: url).update { $0 }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
