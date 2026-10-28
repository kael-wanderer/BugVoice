import Foundation
import Testing
@testable import VoiceCore

struct TranscriptEditTests {
    @Test func editRevertAndExport() throws {
        var meeting = MeetingManifest(startedAt: Date(), state: .ready, segments: [MeetingSegment(id: "a", start: 0, end: 1, text: "Original", track: .mic)])
        try meeting.editSegment(id: "a", text: "Corrected", at: Date(timeIntervalSince1970: 1))
        #expect(meeting.segments[0].text == "Original")
        #expect(meeting.segments[0].displayText == "Corrected")
        #expect(MeetingExporter.markdown(meeting).contains("Corrected"))
        #expect(MeetingExporter.srt(meeting).contains("Corrected"))
        #expect(AskPassageBuilder.passages(meeting: meeting).first?.searchText.contains("Corrected") == true)
        #expect(MCPFormat.meeting(meeting, folder: nil, parts: [.transcript], fromLine: 1).contains("Corrected"))
        #expect(MeetingTranscriptPart.split(transcript: meeting.segments, budget: .init()).first?.promptText.contains("Corrected") == true)
        #expect(MeetingListProjection.matches(meeting, query: "Corrected"))
        let decoded = try JSONDecoder().decode(MeetingManifest.self, from: JSONEncoder().encode(meeting))
        #expect(decoded.segments[0].displayText == "Corrected")
        #expect(throws: TranscriptEditError.self) { try meeting.editSegment(id: "a", text: "  ", at: Date()) }
        try meeting.revertSegment(id: "a")
        #expect(meeting.segments[0].displayText == "Original")
    }
    @Test func generationSaveKeepsInterveningEdit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(root: root)
        let meeting = MeetingManifest(startedAt: Date(), state: .ready, segments: [MeetingSegment(id: "a", start: 0, end: 1, text: "Original", track: .mic)])
        try await store.save(meeting)
        let directory = root.appendingPathComponent(meeting.id.rawValue)
        let file = directory.appendingPathComponent("meeting.json")
        #expect(try (FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(try (FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try await store.editSegment(meeting: meeting.id, segment: "a", text: "Corrected", at: Date())
        try await store.saveGeneratedText(meeting: meeting.id, text: "Summary", kind: .summary, names: [:])
        let saved = try await store.load(id: meeting.id)
        #expect(saved.summary == "Summary")
        #expect(saved.segments[0].displayText == "Corrected")
    }

    @Test func generationSaveRecordsTemplateAndTime() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(root: root)
        let meeting = MeetingManifest(startedAt: Date(), state: .ready)
        try await store.save(meeting)
        let at = Date(timeIntervalSince1970: 2_000_000_000)
        try await store.saveGeneratedText(meeting: meeting.id, text: "Summary", kind: .summary, names: [:], template: .standUp, generatedAt: at)
        let saved = try await store.load(id: meeting.id)
        #expect(saved.summaryTemplate == .standUp)
        #expect(saved.summaryTemplateVersion == 1)
        #expect(saved.summaryGeneratedAt == at)
    }

}
