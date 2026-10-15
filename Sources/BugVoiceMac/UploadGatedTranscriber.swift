import Foundation
import VoiceCore

public struct UploadGatedTranscriber: Transcriber {
    private let base: any Transcriber
    private let wait: @Sendable () async throws -> Void

    public init(base: any Transcriber, wait: @escaping @Sendable () async throws -> Void) {
        self.base = base
        self.wait = wait
    }

    public func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript {
        try Task.checkCancellation()
        try await wait()
        try Task.checkCancellation()
        return try await base.transcribe(clip, options: options)
    }
}
