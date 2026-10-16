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
    func delete(id: MeetingID) async throws
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
    func transcribeFinal(
        _ manifest: MeetingManifest,
        chunkSeconds: TimeInterval,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> [MeetingChunkProcessingResult]
    func waitForInFlight(meetingID: MeetingID) async
}

public protocol MeetingAudioFinalizerProtocol: Sendable {
    func finalize(_ manifest: MeetingManifest) async throws -> MeetingManifest
    func cleanupCapture() async throws
}

public extension MeetingAudioFinalizerProtocol {
    func cleanupCapture() async throws {}
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
    private var uploadInvalidated = false
    private var finalProgressFailure: (any Error)?

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

    public func rename(title: String) async throws {
        guard var meeting = manifest else { throw MeetingSessionError.invalidState }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw MeetingSessionError.invalidState }
        meeting.title = cleaned
        manifest = meeting
        try await store.save(meeting)
    }

    /// Folder and tag changes while this session owns the manifest. Pass nil
    /// `suggestedTags` to leave the suggestions as they are.
    public func setLabels(folderID: FolderID?, tags: [String], suggestedTags: [String]?) async throws {
        guard var meeting = manifest else { throw MeetingSessionError.invalidState }
        meeting.folderID = folderID
        meeting.tags = tags
        if let suggestedTags { meeting.suggestedTags = suggestedTags }
        manifest = meeting
        try await store.save(meeting)
    }

    public func setLanguages(_ languages: [SpeechLanguage]) async throws {
        guard var meeting = manifest else { throw MeetingSessionError.invalidState }
        meeting.languages = MeetingLanguages.normalized(languages)
        manifest = meeting
        try await store.save(meeting)
    }

    public func saveGeneratedText(_ text: String, kind: MeetingTextKind) async throws {
        guard var meeting = manifest else { throw MeetingSessionError.invalidState }
        if kind == .summary { meeting.summary = text }
        else { meeting.actionItems = text }
        manifest = meeting
        try await store.save(meeting)
    }

    public func persistInterim(_ result: MeetingChunkProcessingResult) async throws {
        guard var meeting = manifest, meeting.state == .recording || meeting.state == .paused else {
            throw MeetingSessionError.invalidState
        }
        meeting.chunks.removeAll { $0.id == result.record.id }
        meeting.chunks.append(result.record)
        var chunks = meeting.chunks.map { record in
            MeetingChunkProcessingResult(
                record: record,
                segments: meeting.segments.filter { $0.sourceChunkID == record.id }
            )
        }
        chunks.removeAll { $0.record.id == result.record.id }
        chunks.append(result)
        meeting.segments = MeetingTranscriptMerger.merge(chunks)
        manifest = meeting
        try await store.save(meeting)
    }

    @discardableResult
    public func transcribeUpload(_ meeting: MeetingManifest) async throws -> MeetingManifest {
        guard manifest == nil, meeting.source == .upload, meeting.state == .transcribing,
              meeting.duration.isFinite, meeting.duration > 0 else {
            throw MeetingSessionError.invalidState
        }
        manifest = meeting
        try await store.save(meeting)
        return try await finishTranscription(meeting)
    }

    public func persistFinal(_ result: MeetingChunkProcessingResult) async throws {
        guard !uploadInvalidated,
              var meeting = manifest, meeting.state == .transcribing else {
            throw MeetingSessionError.invalidState
        }
        meeting.chunks.removeAll { $0.id == result.record.id }
        meeting.chunks.append(result.record)
        var chunks = meeting.chunks.filter { $0.id != result.record.id }.map { record in
            MeetingChunkProcessingResult(
                record: record,
                segments: meeting.segments.filter { $0.sourceChunkID == record.id }
            )
        }
        chunks.append(result)
        meeting.segments = MeetingTranscriptMerger.merge(chunks)
        manifest = meeting
        try await store.save(meeting)
    }

    public func invalidateUpload() async {
        uploadInvalidated = true
        cancelRequested = true
    }

    @discardableResult
    public func start(labels: ItemLabels = ItemLabels(), languages: [SpeechLanguage] = []) async throws -> MeetingManifest {
        guard manifest == nil else { throw MeetingSessionError.invalidState }
        let now = clock.now()
        var meeting = MeetingManifest(id: meetingID, startedAt: now, state: .recording, languages: languages)
        meeting.folderID = labels.folderID
        meeting.tags = labels.tags
        manifest = meeting
        do {
            try await store.save(meeting)
            try await audio.start(track: .mic)
            try await audio.start(track: .system)
            activeStartedAt = now
            return meeting
        } catch {
            let checkpoint = try? await audio.checkpoint()
            try? await audio.stop()
            let minimumKeepSamples = MeetingPCMJournal.sampleRate
            let hasCommittedAudio = checkpoint?.tracks.contains { $0.sampleCount >= minimumKeepSamples } ?? true
            guard hasCommittedAudio else {
                manifest = nil
                try? await store.delete(id: meeting.id)
                throw error
            }
            meeting.state = .failed
            meeting.transcriptionError = String(describing: error)
            manifest = meeting
            try? await store.save(meeting)
            throw error
        }
    }

    @discardableResult
    public func pause() async throws -> MeetingManifest {
        guard let initial = manifest, initial.state == .recording else { throw MeetingSessionError.invalidState }
        try await audio.pause()
        _ = try await audio.checkpoint()
        guard var meeting = manifest, meeting.id == initial.id, meeting.state == .recording else {
            throw MeetingSessionError.invalidState
        }
        accumulatedActiveTime = elapsed(at: clock.now())
        activeStartedAt = nil
        meeting.duration = accumulatedActiveTime
        meeting.state = .paused
        manifest = meeting
        try await store.save(meeting)
        return meeting
    }

    /// Sleep uses the same durable pause boundary as the recorder's Pause
    /// control. It deliberately leaves the session paused after wake.
    @discardableResult
    public func pauseForSleep() async throws -> MeetingManifest {
        try await pause()
    }

    @discardableResult
    public func resume() async throws -> MeetingManifest {
        guard let initial = manifest, initial.state == .paused else { throw MeetingSessionError.invalidState }
        try await audio.resume()
        guard var meeting = manifest, meeting.id == initial.id, meeting.state == .paused else {
            throw MeetingSessionError.invalidState
        }
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
        guard let initial = manifest, initial.state == .recording || initial.state == .paused else {
            throw MeetingSessionError.invalidState
        }
        accumulatedActiveTime = elapsed(at: clock.now())
        activeStartedAt = nil
        try await audio.stop()
        _ = try await audio.checkpoint()
        await scheduler.cancelQueued(meetingID: initial.id)
        await scheduler.waitForInFlight(meetingID: initial.id)
        guard var meeting = manifest, meeting.id == initial.id,
              meeting.state == .recording || meeting.state == .paused else {
            throw MeetingSessionError.invalidState
        }
        meeting.duration = accumulatedActiveTime
        meeting.endedAt = clock.now()
        meeting.state = .transcribing
        meeting.transcriptProgress = 0
        manifest = meeting
        try await store.save(meeting)
        return try await finishTranscription(meeting)
    }

    @discardableResult
    public func recover(id: MeetingID) async throws -> MeetingManifest {
        var recovered = try await store.load(id: id)
        if recovered.source == .upload, recovered.state == .interrupted {
            throw MeetingSessionError.invalidState
        }
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
    public func retryTranscription() async throws -> MeetingManifest {
        guard var meeting = manifest,
              meeting.state == .interrupted || meeting.state == .transcribing
        else { throw MeetingSessionError.invalidState }
        meeting.state = .transcribing
        meeting.endedAt = meeting.endedAt ?? clock.now()
        meeting.transcriptionError = nil
        cancelRequested = false
        finalProgressFailure = nil
        manifest = meeting
        try await store.save(meeting)
        return try await finishTranscription(meeting)
    }

    @discardableResult
    public func cancel() async throws -> MeetingManifest {
        guard let initial = manifest, initial.state.isRecoverable else { throw MeetingSessionError.invalidState }
        cancelRequested = true
        accumulatedActiveTime = elapsed(at: clock.now())
        await scheduler.cancelQueued(meetingID: initial.id)
        await scheduler.waitForInFlight(meetingID: initial.id)
        try await audio.stop()
        _ = try await audio.checkpoint()
        activeStartedAt = nil
        guard var meeting = manifest, meeting.id == initial.id else { throw MeetingSessionError.invalidState }
        meeting.duration = accumulatedActiveTime
        meeting.endedAt = meeting.endedAt ?? clock.now()
        meeting.state = .interrupted
        manifest = meeting
        try await store.save(meeting)
        return meeting
    }

    private func finishTranscription(_ initial: MeetingManifest) async throws -> MeetingManifest {
        var meeting = initial
        var audioAttempted = false
        do {
            let meetingID = meeting.id
            let chunks = try await scheduler.transcribeFinal(meeting, chunkSeconds: 30) { [weak self] progress in
                await self?.setTranscriptProgress(progress, meetingID: meetingID)
            }
            if initial.source == .recording, cancelRequested { return manifest ?? meeting }
            try Task.checkCancellation()
            guard !uploadInvalidated else { throw CancellationError() }
            if initial.source == .upload, chunks.contains(where: { $0.record.state == .failed }) {
                throw UploadFailure.transcript
            }
            if let finalProgressFailure { throw finalProgressFailure }
            meeting = manifest ?? meeting
            meeting.chunks = chunks.map(\.record)
            meeting.segments = MeetingTranscriptMerger.merge(chunks)
            meeting.transcriptProgress = 1
            meeting.transcriptionError = nil
            audioAttempted = true
            let finalized = try await finalizer.finalize(meeting)
            if initial.source == .recording, cancelRequested { return manifest ?? meeting }
            try Task.checkCancellation()
            guard !uploadInvalidated else { throw CancellationError() }
            var current = manifest ?? meeting
            current.audioFormat = finalized.audioFormat
            current.chunks = finalized.chunks
            current.segments = finalized.segments
            current.transcriptProgress = 1
            current.transcriptionError = nil
            current.state = .ready
            manifest = current
            try await store.save(current)
            try? await finalizer.cleanupCapture()
            return current
        } catch {
            if initial.source == .recording {
                if cancelRequested { return manifest ?? meeting }
                var current = manifest ?? meeting
                current.state = .transcribing
                current.transcriptionError = String(describing: error)
                manifest = current
                try? await store.save(current)
                throw error
            }
            if cancelRequested || uploadInvalidated || error is CancellationError {
                throw CancellationError()
            }
            if UploadFailure.isDiskFull(error) { throw error }
            var current = manifest ?? initial
            var failure = UploadFailure.audioSave
            if !audioAttempted {
                do {
                    current = try await finalizer.finalize(current)
                    failure = .transcript
                } catch {
                    if UploadFailure.isDiskFull(error) { throw error }
                    if error is CancellationError { throw error }
                    failure = .audioSave
                }
            }
            try Task.checkCancellation()
            guard !uploadInvalidated else { throw CancellationError() }
            current.state = .transcribing
            current.transcriptionError = failure.localizedDescription
            manifest = current
            try await store.save(current)
            throw failure
        }
    }

    private func setTranscriptProgress(_ progress: Double, meetingID: MeetingID) async {
        guard !uploadInvalidated,
              var meeting = manifest, meeting.id == meetingID, meeting.state == .transcribing else { return }
        meeting.transcriptProgress = progress.isFinite ? min(1, max(0, progress)) : nil
        manifest = meeting
        do {
            try await store.save(meeting)
        } catch {
            if meeting.source == .upload { finalProgressFailure = error }
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
