import Foundation
import VoiceCore

public struct UploadAudioSourceControl: MeetingAudioSourceControl {
    private let writer: MeetingPCMJournalWriter

    public init(writer: MeetingPCMJournalWriter) {
        self.writer = writer
    }

    public func start(track: MeetingTrack) async throws {
    }

    public func pause() async throws {
    }

    public func resume() async throws {
    }

    public func stop() async throws {
    }

    public func checkpoint() async throws -> MeetingCheckpoint {
        try writer.storedCheckpoint()
    }

    public func recover(id: MeetingID, manifest: MeetingManifest) async throws -> MeetingCheckpoint {
        guard manifest.source == .upload else { throw MeetingSessionError.invalidState }
        do {
            let checkpoint = try writer.recover()
            let file = try requireFile(checkpoint, duration: manifest.duration)
            guard file.sampleCount > 0 else { throw UploadFailure.missingJournal }
            return checkpoint
        } catch {
            if UploadFailure.isDiskFull(error) { throw error }
            throw UploadFailure.missingJournal
        }
    }
}

func requireFile(_ checkpoint: MeetingCheckpoint, duration: TimeInterval) throws -> MeetingTrackCheckpoint {
    guard checkpoint.tracks.count == 1,
          let file = checkpoint.track(.file), duration.isFinite, duration > 0,
          file.sampleCount == Int((duration * 16_000).rounded()),
          file.committedByteCount == file.sampleCount * 2,
          file.startOffset == 0 else { throw UploadFailure.missingJournal }
    return file
}
