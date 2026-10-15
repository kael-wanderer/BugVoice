import AVFoundation
import Foundation
import Testing
@testable import BugVoiceMac
import VoiceCore

struct UploadAudioTests {
    @Test func fileAACPreservesLevel() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = MeetingPCMJournalWriter(directory: root.appendingPathComponent(".capture"))
        try writer.start(track: .file)
        for second in 0..<3 {
            let tone = (0..<16_000).map { Float(sin(Double($0) * 2 * .pi * 440 / 16_000) * 0.4) }
            writer.append(tone, track: .file, offset: Double(second))
        }
        _ = try writer.checkpoint()
        writer.close()
        let manifest = MeetingManifest(startedAt: Date(), duration: 3, state: .transcribing, source: .upload)
        let control = UploadAudioSourceControl(writer: writer)
        try await control.start(track: .file)
        try await control.pause()
        try await control.resume()
        try await control.stop()
        #expect(try await control.recover(id: manifest.id, manifest: manifest).tracks.map(\.track) == [.file])
        let finalizer = UploadAudioFinalizer(meetingDirectory: root)
        _ = try await finalizer.finalize(manifest)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("mic.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("system.m4a").path))
        let file = try AVAudioFile(forReading: root.appendingPathComponent("audio.m4a"))
        #expect(file.processingFormat.channelCount == 1)
        #expect(file.processingFormat.sampleRate == 16_000)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_000))
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: try #require(buffer.floatChannelData?[0]), count: Int(buffer.frameLength)))
        #expect(AudioClip(samples: samples).rms > 0.24)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".capture").path))
        try await finalizer.cleanupCapture()
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".capture").path))
    }

    @Test func missingJournalCannotProduceEmptyReadyAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let writer = MeetingPCMJournalWriter(directory: root.appendingPathComponent(".capture"))
        let manifest = MeetingManifest(startedAt: Date(), duration: 3, state: .transcribing, source: .upload)
        await #expect(throws: UploadFailure.missingJournal) {
            try await UploadAudioSourceControl(writer: writer).recover(id: manifest.id, manifest: manifest)
        }
        await #expect(throws: UploadFailure.missingJournal) {
            try await UploadAudioFinalizer(meetingDirectory: root).finalize(manifest)
        }
    }
}
