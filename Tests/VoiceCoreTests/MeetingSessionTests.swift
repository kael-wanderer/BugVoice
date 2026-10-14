import Foundation
import Testing
@testable import VoiceCore

struct MeetingSessionTests {
    @Test func startRollsBackFirstSourceWhenSecondSourceFails() async throws {
        let rig = SessionRig(failStarting: .system)
        let session = rig.makeSession()
        do {
            try await session.start()
            Issue.record("Expected source start failure")
        } catch {}
        #expect(await rig.audio.started == [.mic, .system])
        #expect(await rig.audio.stopCount == 1)
        #expect(await rig.store.saved.last?.state == .failed)
    }

    @Test func pauseCheckpointsAndResumeExcludesPausedGap() async throws {
        let rig = SessionRig()
        let session = rig.makeSession()
        try await session.start()
        rig.clock.advance(10)
        try await session.pause()
        rig.clock.advance(100)
        try await session.resume()
        rig.clock.advance(5)
        let stopped = try await session.stop()

        #expect(stopped.duration == 15)
        #expect(stopped.state == .ready)
        #expect(await rig.audio.pauseCount == 1)
        #expect(await rig.audio.resumeCount == 1)
    }

    @Test func markUsesMeetingRelativeActiveTime() async throws {
        let rig = SessionRig()
        let session = rig.makeSession()
        try await session.start()
        rig.clock.advance(4.5)
        let mark = try await session.mark(label: "Decision")
        #expect(mark.offset == 4.5)
        #expect(mark.label == "Decision")
    }

    @Test func stopSchedulesFinalChunksAndPersistsMergedSegments() async throws {
        let speech = MeetingSegment(start: 1, end: 2, text: "hello", track: .mic)
        let rig = SessionRig(finalChunks: [chunk("mic-0", track: .mic, segments: [speech])])
        let session = rig.makeSession()
        try await session.start()
        let stopped = try await session.stop()

        #expect(stopped.state == .ready)
        #expect(stopped.segments.map(\.text) == ["hello"])
        #expect(await rig.scheduler.finalCallCount == 1)
        #expect(await rig.finalizer.callCount == 1)
    }

    @Test func recoverUsesAudioControllerCommittedCheckpoint() async throws {
        let meeting = MeetingManifest(id: MeetingID(rawValue: "recover"), startedAt: Date(), state: .recording)
        let rig = SessionRig()
        try await rig.store.save(meeting)
        let session = rig.makeSession()
        let recovered = try await session.recover(id: meeting.id)

        #expect(recovered.state == .interrupted)
        #expect(recovered.duration == 3)
        #expect(await rig.audio.recoveredID == meeting.id)
        #expect(await rig.store.saved.last?.state == .interrupted)
    }

    @Test func recoveryRetriesTranscribingMeetingsFromCommittedAudio() async throws {
        let meeting = MeetingManifest(id: MeetingID(rawValue: "retry"), startedAt: Date(), state: .transcribing)
        let expected = MeetingSegment(start: 0, end: 1, text: "recovered", track: .mic)
        let rig = SessionRig(finalChunks: [chunk("retry-mic-0", track: .mic, segments: [expected])])
        try await rig.store.save(meeting)
        let recovered = try await rig.makeSession().recover(id: meeting.id)
        #expect(recovered.state == .ready)
        #expect(recovered.segments.map(\.text) == ["recovered"])
        #expect(await rig.scheduler.finalCallCount == 1)
    }

    @Test func interruptedCaptureCanRetryTranscriptionFromCommittedAudio() async throws {
        let meeting = MeetingManifest(id: MeetingID(rawValue: "interrupted-retry"), startedAt: Date(), state: .interrupted)
        let expected = MeetingSegment(start: 0, end: 1, text: "saved audio", track: .mic)
        let rig = SessionRig(finalChunks: [chunk("retry-mic-0", track: .mic, segments: [expected])])
        try await rig.store.save(meeting)
        let session = rig.makeSession()

        _ = try await session.recover(id: meeting.id)
        let finished = try await session.retryTranscription()

        #expect(finished.state == .ready)
        #expect(finished.segments.map(\.text) == ["saved audio"])
        #expect(await rig.scheduler.finalCallCount == 1)
    }

    @Test func cancelRemovesQueuedWorkAndWaitsForInFlightChunk() async throws {
        let rig = SessionRig(blockTranscription: true)
        let session = rig.makeSession()
        let started = try await session.start()
        let inFlightChunk = Task {
            try await rig.scheduler.transcribeFinal(started, chunkSeconds: 30) { _ in }
        }
        await rig.scheduler.waitUntilStarted()
        let completion = CompletionProbe()
        let cancellation = Task {
            try await session.cancel()
            completion.finish()
        }
        #expect(!completion.isFinished)
        await rig.scheduler.waitUntilCancelled()
        let queuedCancellationCount = await rig.scheduler.cancelQueuedCount
        #expect(queuedCancellationCount == 1)
        await rig.scheduler.release()
        _ = try await inFlightChunk.value
        try await cancellation.value
        #expect(completion.isFinished)
    }

    @Test func stopWaitsForInFlightChunkBeforeFinalizing() async throws {
        let rig = SessionRig(blockTranscription: true)
        let session = rig.makeSession()
        try await session.start()
        let completion = CompletionProbe()
        let stopping = Task {
            _ = try await session.stop()
            completion.finish()
        }
        await rig.scheduler.waitUntilStarted()
        #expect(!completion.isFinished)
        #expect(await rig.finalizer.callCount == 0)
        await rig.scheduler.release()
        _ = try await stopping.value
        #expect(completion.isFinished)
        #expect(await rig.finalizer.callCount == 1)
    }

    @Test func finalTranscriptionProgressIsSavedForTheMeetingList() async throws {
        let rig = SessionRig(blockTranscription: true)
        let session = rig.makeSession()
        try await session.start()
        let stopping = Task { try await session.stop() }
        await rig.scheduler.waitUntilProgressReported()
        let saved = await rig.store.saved
        #expect(saved.contains { $0.state == .transcribing && $0.transcriptProgress == 0.5 })
        await rig.scheduler.release()
        _ = try await stopping.value
    }

    private func chunk(_ id: String, track: MeetingTrack, segments: [MeetingSegment]) -> MeetingChunkProcessingResult {
        MeetingChunkProcessingResult(record: MeetingChunkRecord(
            id: id, track: track, offset: 0, duration: 30,
            requestedLanguage: .auto, state: .complete
        ), segments: segments)
    }
}

private final class ManualClock: MeetingClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ interval: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(interval) }
}

private actor SessionStoreProbe: MeetingSessionStore {
    var meetings: [MeetingID: MeetingManifest] = [:]
    private(set) var saved: [MeetingManifest] = []
    func save(_ manifest: MeetingManifest) async throws {
        meetings[manifest.id] = manifest
        saved.append(manifest)
    }
    func load(id: MeetingID) async throws -> MeetingManifest { meetings[id]! }
}

private actor AudioControlProbe: MeetingAudioSourceControl {
    let failStarting: MeetingTrack?
    private(set) var started: [MeetingTrack] = []
    private(set) var stopCount = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var recoveredID: MeetingID?
    init(failStarting: MeetingTrack?) { self.failStarting = failStarting }
    func start(track: MeetingTrack) async throws {
        started.append(track)
        if track == failStarting { throw TestFailure.startFailed }
    }
    func pause() async throws { pauseCount += 1 }
    func resume() async throws { resumeCount += 1 }
    func checkpoint() async throws -> MeetingCheckpoint { MeetingCheckpoint() }
    func stop() async throws { stopCount += 1 }
    func recover(id: MeetingID, manifest: MeetingManifest) async throws -> MeetingCheckpoint {
        recoveredID = id
        return MeetingCheckpoint(tracks: [MeetingTrackCheckpoint(track: .mic, committedByteCount: 64, sampleCount: 32, startOffset: 0, endOffset: 3)])
    }
}

private actor SchedulerProbe: MeetingTranscriptionScheduler {
    let block: Bool
    let chunks: [MeetingChunkProcessingResult]
    private(set) var finalCallCount = 0
    private(set) var cancelQueuedCount = 0
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var inFlight = false
    private var cancelContinuation: CheckedContinuation<Void, Never>?
    private var progressContinuation: CheckedContinuation<Void, Never>?
    private var didReportProgress = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(block: Bool, chunks: [MeetingChunkProcessingResult]) { self.block = block; self.chunks = chunks }
    func cancelQueued(meetingID: MeetingID) async {
        cancelQueuedCount += 1
        cancelContinuation?.resume()
        cancelContinuation = nil
    }
    func transcribeFinal(
        _ manifest: MeetingManifest,
        chunkSeconds: TimeInterval,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> [MeetingChunkProcessingResult] {
        finalCallCount += 1
        inFlight = true
        startedContinuation?.resume()
        startedContinuation = nil
        await progress(0.5)
        didReportProgress = true
        progressContinuation?.resume()
        progressContinuation = nil
        if block { await withCheckedContinuation { releaseContinuation = $0 } }
        inFlight = false
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        return chunks
    }
    func waitUntilCancelled() async {
        if cancelQueuedCount > 0 { return }
        await withCheckedContinuation { cancelContinuation = $0 }
    }
    func waitUntilStarted() async {
        if finalCallCount > 0 { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }
    func waitUntilProgressReported() async {
        if didReportProgress { return }
        await withCheckedContinuation { progressContinuation = $0 }
    }
    func waitForInFlight(meetingID: MeetingID) async {
        guard inFlight else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { releaseContinuation?.resume(); releaseContinuation = nil }
}

private actor FinalizerProbe: MeetingAudioFinalizerProtocol {
    private(set) var callCount = 0
    func finalize(_ manifest: MeetingManifest) async throws -> MeetingManifest { callCount += 1; return manifest }
}

private final class CompletionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func finish() { lock.lock(); defer { lock.unlock() }; value = true }
}

private struct SessionRig {
    let clock = ManualClock(Date(timeIntervalSince1970: 1_000))
    let store = SessionStoreProbe()
    let audio: AudioControlProbe
    let scheduler: SchedulerProbe
    let finalizer = FinalizerProbe()
    init(failStarting: MeetingTrack? = nil, finalChunks: [MeetingChunkProcessingResult] = [], blockTranscription: Bool = false) {
        audio = AudioControlProbe(failStarting: failStarting)
        scheduler = SchedulerProbe(block: blockTranscription, chunks: finalChunks)
    }
    func makeSession() -> MeetingSession {
        MeetingSession(clock: clock, store: store, audio: audio, scheduler: scheduler, finalizer: finalizer)
    }
}

private enum TestFailure: Error { case startFailed }
