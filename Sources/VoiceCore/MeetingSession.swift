import Foundation

public protocol MeetingClock: Sendable {
    func now() -> Date
}

public struct SystemMeetingClock: MeetingClock {
    public init() {}
    public func now() -> Date { Date() }
}

public protocol MeetingSessionStore: Sendable {
    func save(_ manifest: MeetingManifest) async throws
    func load(id: MeetingID) async throws -> MeetingManifest
}

public protocol MeetingAudioSourceControl: Sendable {
    func start(track: MeetingTrack) async throws
    func pause() async throws
    func resume() async throws
    func checkpoint() async throws -> MeetingCheckpoint
    func stop() async throws
    func recover(id: MeetingID, manifest: MeetingManifest) async throws -> MeetingCheckpoint
}

public protocol MeetingTranscriptionScheduler: Sendable {
    func cancelQueued(meetingID: MeetingID) async
    func transcribeFinal(_ manifest: MeetingManifest, chunkSeconds: TimeInterval) async throws -> [MeetingChunkProcessingResult]
    func waitForInFlight(meetingID: MeetingID) async
}

public protocol MeetingAudioFinalizerProtocol: Sendable {
    func finalize(_ manifest: MeetingManifest) async throws -> MeetingManifest
}

public actor MeetingSession {
    private let clock: any MeetingClock
    private let store: any MeetingSessionStore
    private let audio: any MeetingAudioSourceControl
    private let scheduler: any MeetingTranscriptionScheduler
    private let finalizer: any MeetingAudioFinalizerProtocol
    private let meetingID: MeetingID
    private var manifest: MeetingManifest?
    private var activeStartedAt: Date?
    private var accumulatedActiveTime: TimeInterval = 0
    private var cancelRequested = false

    public init(
        clock: any MeetingClock = SystemMeetingClock(),
        store: any MeetingSessionStore,
        audio: any MeetingAudioSourceControl,
        scheduler: any MeetingTranscriptionScheduler,
        finalizer: any MeetingAudioFinalizerProtocol,
        meetingID: MeetingID = .new()
    ) {
        self.clock = clock
        self.store = store
        self.audio = audio
        self.scheduler = scheduler
        self.finalizer = finalizer
        self.meetingID = meetingID
    }

    public func snapshot() -> MeetingManifest? { manifest }

    @discardableResult
    public func start() async throws -> MeetingManifest {
        guard manifest == nil else { throw MeetingSessionError.invalidState }
        let now = clock.now()
        var meeting = MeetingManifest(id: meetingID, startedAt: now, state: .recording)
        try await store.save(meeting)
        manifest = meeting
        do {
            try await audio.start(track: .mic)
            try await audio.start(track: .system)
            activeStartedAt = now
            return meeting
        } catch {
            try? await audio.stop()
            meeting.state = .failed
            meeting.transcriptionError = String(describing: error)
            manifest = meeting
            try? await store.save(meeting)
            throw error
        }
    }

    @discardableResult
    public func pause() async throws -> MeetingManifest {
        guard var meeting = manifest, meeting.state == .recording else { throw MeetingSessionError.invalidState }
        try await audio.pause()
        _ = try await audio.checkpoint()
        accumulatedActiveTime = elapsed(at: clock.now())
        activeStartedAt = nil
        meeting.duration = accumulatedActiveTime
        meeting.state = .paused
        manifest = meeting
        try await store.save(meeting)
        return meeting
    }

    @discardableResult
    public func resume() async throws -> MeetingManifest {
        guard var meeting = manifest, meeting.state == .paused else { throw MeetingSessionError.invalidState }
        try await audio.resume()
        activeStartedAt = clock.now()
        meeting.state = .recording
        manifest = meeting
        try await store.save(meeting)
        return meeting
    }

    @discardableResult
    public func mark(label: String? = nil) async throws -> MeetingMark {
        guard var meeting = manifest, meeting.state == .recording || meeting.state == .paused else {
            throw MeetingSessionError.invalidState
        }
        let mark = MeetingMark(offset: elapsed(at: clock.now()), label: label)
        meeting.marks.append(mark)
        manifest = meeting
        try await store.save(meeting)
        return mark
    }

    @discardableResult
    public func stop() async throws -> MeetingManifest {
        guard var meeting = manifest, meeting.state == .recording || meeting.state == .paused else {
            throw MeetingSessionError.invalidState
        }
        accumulatedActiveTime = elapsed(at: clock.now())
        activeStartedAt = nil
        try await audio.stop()
        _ = try await audio.checkpoint()
        meeting.duration = accumulatedActiveTime
        meeting.endedAt = clock.now()
        await scheduler.cancelQueued(meetingID: meeting.id)
        await scheduler.waitForInFlight(meetingID: meeting.id)
        meeting.state = .transcribing
        meeting.transcriptProgress = 0
        manifest = meeting
        try await store.save(meeting)
        return try await finishTranscription(meeting)
    }

    @discardableResult
    public func recover(id: MeetingID) async throws -> MeetingManifest {
        var recovered = try await store.load(id: id)
        let checkpoint = try await audio.recover(id: id, manifest: recovered)
        if recovered.state == .recording || recovered.state == .paused {
            recovered.duration = checkpoint.tracks.map(\.endOffset).max() ?? recovered.duration
            recovered.state = .interrupted
            recovered.endedAt = recovered.endedAt ?? clock.now()
            manifest = recovered
            try await store.save(recovered)
            return recovered
        }
        manifest = recovered
        if recovered.state == .transcribing {
            return try await finishTranscription(recovered)
        }
        return recovered
    }

    @discardableResult
    public func cancel() async throws -> MeetingManifest {
        guard var meeting = manifest, meeting.state.isRecoverable else { throw MeetingSessionError.invalidState }
        cancelRequested = true
        accumulatedActiveTime = elapsed(at: clock.now())
        await scheduler.cancelQueued(meetingID: meeting.id)
        await scheduler.waitForInFlight(meetingID: meeting.id)
        try await audio.stop()
        _ = try await audio.checkpoint()
        activeStartedAt = nil
        meeting.duration = accumulatedActiveTime
        meeting.endedAt = meeting.endedAt ?? clock.now()
        meeting.state = .interrupted
        manifest = meeting
        try await store.save(meeting)
        return meeting
    }

    private func finishTranscription(_ initial: MeetingManifest) async throws -> MeetingManifest {
        var meeting = initial
        do {
            let chunks = try await scheduler.transcribeFinal(meeting, chunkSeconds: 30)
            guard !cancelRequested else { return manifest ?? meeting }
            meeting.chunks = chunks.map(\.record)
            meeting.segments = MeetingTranscriptMerger.merge(chunks)
            meeting.transcriptProgress = 1
            meeting.transcriptionError = nil
            meeting = try await finalizer.finalize(meeting)
            meeting.state = .ready
            manifest = meeting
            try await store.save(meeting)
            return meeting
        } catch {
            if cancelRequested { return manifest ?? meeting }
            meeting.state = .transcribing
            meeting.transcriptionError = String(describing: error)
            manifest = meeting
            try? await store.save(meeting)
            throw error
        }
    }

    private func elapsed(at now: Date) -> TimeInterval {
        accumulatedActiveTime + (activeStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
}

public enum MeetingSessionError: Error, Equatable, Sendable {
    case invalidState
}


extension MeetingStore: MeetingSessionStore {}
