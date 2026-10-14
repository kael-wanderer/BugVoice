import Foundation
import Testing
@testable import VoiceCore

struct MeetingTests {
    @Test func manifestRoundTripsDetectedLanguagePerChunk() throws {
        let meeting = MeetingManifest.new(startedAt: Date(timeIntervalSince1970: 10))
        var saved = meeting
        saved.chunks = [.init(
            id: "mic-0", track: .mic, offset: 0, duration: 30,
            requestedLanguage: .auto, detectedLanguage: "vi", state: .complete
        )]

        let data = try JSONEncoder().encode(saved)
        let loaded = try JSONDecoder().decode(MeetingManifest.self, from: data)

        #expect(loaded.chunks[0].detectedLanguage == "vi")
        #expect(loaded.chunks[0].track == .mic)
    }

    @Test func recoveryStatesAreNotReady() {
        #expect(MeetingState.recording.isRecoverable)
        #expect(MeetingState.interrupted.isRecoverable)
        #expect(!MeetingState.ready.isRecoverable)
    }

    @Test func storeReplacesManifestAtomically() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(root: root)
        let meeting = MeetingManifest.new(startedAt: Date(timeIntervalSince1970: 10))

        try await store.save(meeting)
        var updated = meeting
        updated.title = "Planning"
        try await store.save(updated)

        #expect(try await store.load(id: meeting.id) == updated)
        let folder = root.appendingPathComponent(meeting.id.rawValue, isDirectory: true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains("meeting.json"))
    }

    @Test func unsupportedSchemaIsRecoverableAndPreservesManifest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let meeting = MeetingManifest(schemaVersion: 99, startedAt: Date(timeIntervalSince1970: 10))
        let folder = root.appendingPathComponent(meeting.id.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A future manifest may have fields this build cannot decode. Check
        // its schema version before attempting to decode the full model.
        try Data(#"{"schemaVersion":99}"#.utf8)
            .write(to: folder.appendingPathComponent("meeting.json"))

        do {
            _ = try await MeetingStore(root: root).load(id: meeting.id)
            Issue.record("Expected unsupported schema version")
        } catch {
            #expect(error as? MeetingStoreError == .unsupportedSchemaVersion(99))
        }
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("meeting.json").path))
    }
}
