import Foundation
import VoiceCore

public struct UploadAudioFinalizer: MeetingAudioFinalizerProtocol {
    private let meetingDirectory: URL

    public init(meetingDirectory: URL) {
        self.meetingDirectory = meetingDirectory
    }

    public func finalize(_ manifest: MeetingManifest) async throws -> MeetingManifest {
        guard manifest.source == .upload else { throw MeetingSessionError.invalidState }
        let writer = MeetingPCMJournalWriter(directory: meetingDirectory.appendingPathComponent(".capture"))
        do {
            _ = try requireFile(writer.storedCheckpoint(), duration: manifest.duration)
        } catch {
            if UploadFailure.isDiskFull(error) { throw error }
            throw UploadFailure.missingJournal
        }
        let reader = try writer.makeReader(for: .file)
        try Task.checkCancellation()
        try MeetingAACWriter.write(sampleCount: reader.totalSampleCount, readBlock: { _, count in
            try Task.checkCancellation()
            return try reader.readSamples(maxCount: count)
        }, to: meetingDirectory.appendingPathComponent("audio.m4a"))
        var result = manifest
        result.audioFormat.finalEncoding = "aac"
        return result
    }

    public func cleanupCapture() async throws {
        let capture = meetingDirectory.appendingPathComponent(".capture")
        if FileManager.default.fileExists(atPath: capture.path) {
            try FileManager.default.removeItem(at: capture)
            try MeetingAACWriter.syncDirectory(meetingDirectory)
        }
    }
}
