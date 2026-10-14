import AVFoundation
import Foundation
import Testing
@testable import BugVoiceMac
import VoiceCore

struct MeetingAudioFinalizerTests {
    @Test func finalizerWritesSeparateAACTracksAndSilencePaddedMix() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = root.appendingPathComponent(".capture", isDirectory: true)
        let writer = MeetingPCMJournalWriter(directory: capture)
        try writer.start(track: .mic)
        try writer.start(track: .system)
        writer.append(tone(seconds: 1), track: .mic, offset: 0)
        writer.append(Array(repeating: 0, count: 8_000), track: .system, offset: 0)
        _ = try writer.checkpoint()
        writer.close()
        let store = MeetingStore(root: root)
        let meeting = MeetingManifest(id: MeetingID(rawValue: "finalize"), startedAt: Date(), duration: 1, state: .transcribing)

        let result = try await MeetingAudioFinalizer(meetingDirectory: root, store: store).finalize(meeting)

        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("audio.m4a").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("mic.m4a").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("system.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: capture.path))
        #expect(result.audioFormat.finalEncoding == "aac")
        #expect(abs(try duration(root.appendingPathComponent("audio.m4a")) - 1) < 0.1)
    }

    @Test func failedFinalizationLeavesPCMJournalsForRetry() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = root.appendingPathComponent(".capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: capture.appendingPathComponent("mic.pcm"))
        let meeting = MeetingManifest(id: MeetingID(rawValue: "failure"), startedAt: Date(), state: .transcribing)

        do {
            _ = try await MeetingAudioFinalizer(meetingDirectory: root, store: MeetingStore(root: root)).finalize(meeting)
            Issue.record("Expected finalization to fail without a committed checkpoint")
        } catch {}

        #expect(FileManager.default.fileExists(atPath: capture.appendingPathComponent("mic.pcm").path))
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BugVoiceAudioFinalizer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func tone(seconds: Double) -> [Float] {
        (0..<Int(seconds * 16_000)).map { index in Float(sin(2 * Double.pi * 440 * Double(index) / 16_000) * 0.4) }
    }

    private func duration(_ url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
