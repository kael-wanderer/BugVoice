import Foundation
import VoiceCore
import BugVoiceMac

actor UploadTranscriptionScheduler: MeetingTranscriptionScheduler {
    private let writer: MeetingPCMJournalWriter
    private let transcriber: any Transcriber
    private let language: SpeechLanguage
    private let gate: @Sendable () async throws -> Void
    private weak var session: MeetingSession?
    private var cancelled = false
    private var running = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(writer: MeetingPCMJournalWriter, transcriber: any Transcriber, language: SpeechLanguage, gate: @escaping @Sendable () async throws -> Void) {
        self.writer = writer
        self.transcriber = transcriber
        self.language = language
        self.gate = gate
    }

    func bindSession(_ session: MeetingSession) {
        self.session = session
    }

    func cancelQueued(meetingID: MeetingID) async {
        cancelled = true
    }

    func waitForInFlight(meetingID: MeetingID) async {
        guard running else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func transcribeFinal(
        _ manifest: MeetingManifest,
        chunkSeconds: TimeInterval,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> [MeetingChunkProcessingResult] {
        guard manifest.source == .upload, !running, let session else { throw MeetingSessionError.invalidState }
        cancelled = false
        running = true
        defer {
            running = false
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
        let checkpoint = try writer.storedCheckpoint()
        let count = checkpoint.track(.file)?.sampleCount ?? 0
        guard count == Int((manifest.duration * 16_000).rounded()), count > 0 else { throw UploadFailure.missingJournal }
        let ranges = MeetingChunkPlanner.plan(sampleCount: count, chunkSeconds: chunkSeconds)
        let gated = UploadGatedTranscriber(base: transcriber, wait: gate)
        var results: [MeetingChunkProcessingResult] = []
        for range in ranges {
            try Task.checkCancellation()
            guard !cancelled else { throw CancellationError() }
            try await gate()
            let result: MeetingChunkProcessingResult
            if let record = UploadChunkPlan.reusable(manifest.chunks, range: range) {
                // Reconstruct from the chosen original attempt, not already merged text.
                // A merged boundary can have lost its prefix; replaying that would trim twice.
                let chosen = record.chosenAttempt.flatMap { index in
                    record.attempts.indices.contains(index) ? record.attempts[index] : nil
                }
                let segments = chosen?.segments.enumerated().map { index, segment in
                    MeetingSegment(
                        id: "\(record.id)-\(index)",
                        start: record.offset + segment.start,
                        end: record.offset + segment.end,
                        text: segment.text,
                        track: .file,
                        sourceChunkID: record.id
                    )
                } ?? manifest.segments.filter { $0.sourceChunkID == record.id }
                result = MeetingChunkProcessingResult(record: record, segments: segments)
            } else {
                let samples = try await writer.committedSamplesAsync(for: .file, range: range)
                guard samples.count == range.count else { throw UploadFailure.missingJournal }
                var processed = try await MeetingChunkProcessor().process(
                    id: UploadChunkPlan.id(for: range), track: .file,
                    offset: Double(range.lowerBound) / 16_000,
                    clip: AudioClip(samples: samples), configuredLanguage: language, transcriber: gated
                )
                for index in processed.segments.indices {
                    processed.segments[index].id = "\(processed.record.id)-\(index)"
                }
                result = processed
            }
            try Task.checkCancellation()
            guard !cancelled else { throw CancellationError() }
            try await session.persistFinal(result)
            results.append(result)
            await progress(Double(results.count) / Double(ranges.count))
            // A failed chunk does not stop the run: later chunks still get transcribed,
            // and MeetingSession.finishTranscription throws UploadFailure.transcript at the end,
            // so Retry only redoes the failed ranges.
        }
        return results
    }
}
