import AppKit
import AVFoundation
import Foundation
import Observation
import VoiceCore
import BugVoiceMac

@MainActor
@Observable
final class MeetingController {
    private unowned let model: AppModel
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var isTranscribing = false
    private(set) var statusMessage: String?
    private(set) var latestLine = ""
    private(set) var youLevel: Float = 0
    private(set) var othersLevel: Float = 0
    private(set) var elapsed: TimeInterval = 0
    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: (() -> Void)?
    @ObservationIgnored private var session: MeetingSession?
    @ObservationIgnored private var capture: MeetingAudioCaptureCoordinator?
    @ObservationIgnored private var writer: MeetingPCMJournalWriter?
    @ObservationIgnored private var scheduler: MeetingLiveTranscriptionScheduler?
    @ObservationIgnored private var meetingID: MeetingID?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var elapsedBeforePause: TimeInterval = 0
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var liveChunkCursor = MeetingLiveChunkCursor()

    init(model: AppModel) { self.model = model }

    var isActive: Bool { isRecording || isPaused || isTranscribing }

    func toggleRecording() {
        if isActive {
            Task { await stop() }
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard !isActive else { return }
        guard Permissions.isGranted(.microphone) else {
            statusMessage = "Grant Microphone access before recording a meeting."
            model.openPermissionsWindow()
            return
        }
        do {
            let id = MeetingID.new()
            let directory = model.paths.meetings.appendingPathComponent(id.rawValue, isDirectory: true)
            let writer = MeetingPCMJournalWriter(directory: directory.appendingPathComponent(".capture", isDirectory: true))
            let microphoneID: AudioDeviceID?
            if let uid = model.settings.speech.microphoneUID {
                guard let configuredDevice = AudioDevices.deviceID(forUID: uid) else { throw RecorderError.deviceNotFound }
                microphoneID = configuredDevice
            } else {
                microphoneID = nil
            }
            let sources: [MeetingTrack: any MeetingAudioSource] = [
                .mic: MeetingAudioEngineSource(track: .mic, deviceID: microphoneID),
                .system: CoreAudioProcessTapSource()
            ]
            let capture = MeetingAudioCaptureCoordinator(sources: sources, writer: writer)
            let store = MeetingStore(root: model.paths.meetings)
            let scheduler = MeetingLiveTranscriptionScheduler(
                writer: writer,
                transcriber: model.transcriptionRouter,
                language: model.settings.speech.language
            )
            let finalizer = MeetingAudioFinalizer(meetingDirectory: directory)
            let session = MeetingSession(
                store: store, audio: capture, scheduler: scheduler, finalizer: finalizer, meetingID: id
            )
            await scheduler.bindSession(session)
            _ = try await session.start()
            self.session = session
            self.capture = capture
            self.writer = writer
            self.scheduler = scheduler
            self.meetingID = id
            liveChunkCursor = MeetingLiveChunkCursor()
            startedAt = Date()
            elapsedBeforePause = 0
            elapsed = 0
            latestLine = ""
            isRecording = true
            isPaused = false
            statusMessage = nil
            model.setSystemAudioCaptureObserved(true)
            startMonitor()
            onRecordingStarted?()
        } catch {
            isRecording = false
            isPaused = false
            model.setSystemAudioCaptureObserved(false)
            if let coreAudioError = error as? MeetingAudioCaptureError,
               case .coreAudio(let operation, _) = coreAudioError,
               operation.contains("system audio") {
                statusMessage = "System Audio Recording access is required to start a meeting."
                model.noteSystemAudioCaptureStartFailure()
                model.openPermissionsWindow()
            } else {
                statusMessage = "Could not start meeting audio: \(error.localizedDescription)"
            }
        }
    }

    func recover(id: MeetingID) async {
        guard !isActive else { return }
        let directory = model.paths.meetings.appendingPathComponent(id.rawValue, isDirectory: true)
        let writer = MeetingPCMJournalWriter(directory: directory.appendingPathComponent(".capture", isDirectory: true))
        let microphoneID = model.settings.speech.microphoneUID.flatMap(AudioDevices.deviceID(forUID:))
        let sources: [MeetingTrack: any MeetingAudioSource] = [
            .mic: MeetingAudioEngineSource(track: .mic, deviceID: microphoneID),
            .system: CoreAudioProcessTapSource()
        ]
        let capture = MeetingAudioCaptureCoordinator(sources: sources, writer: writer)
        let store = MeetingStore(root: model.paths.meetings)
        let scheduler = MeetingLiveTranscriptionScheduler(
            writer: writer,
            transcriber: model.transcriptionRouter,
            language: model.settings.speech.language
        )
        let finalizer = MeetingAudioFinalizer(meetingDirectory: directory)
        let session = MeetingSession(store: store, audio: capture, scheduler: scheduler, finalizer: finalizer, meetingID: id)
        await scheduler.bindSession(session)
        self.session = session
        self.capture = capture
        self.writer = writer
        self.scheduler = scheduler
        self.meetingID = id
        isTranscribing = true
        statusMessage = nil
        do {
            var recovered = try await session.recover(id: id)
            if recovered.state == .interrupted {
                recovered = try await session.retryTranscription()
            }
            isTranscribing = false
            statusMessage = nil
            await model.reloadMeetings()
        } catch {
            isTranscribing = false
            statusMessage = "Transcript could not be completed. Your meeting audio is saved. \(error.localizedDescription)"
            await model.reloadMeetings()
        }
    }

    func pause() async {
        guard let session, isRecording else { return }
        do {
            try await session.pause()
            elapsedBeforePause = elapsed
            isRecording = false
            isPaused = true
        } catch {
            statusMessage = "Could not pause the meeting: \(error.localizedDescription)"
        }
    }

    func pauseForSleep() async {
        guard let session, isRecording else { return }
        do {
            try await session.pauseForSleep()
            elapsedBeforePause = elapsed
            isRecording = false
            isPaused = true
        } catch {
            statusMessage = "Could not checkpoint the meeting before sleep: \(error.localizedDescription)"
        }
    }

    func resume() async {
        guard let session, isPaused else { return }
        do {
            try await session.resume()
            startedAt = Date()
            isRecording = true
            isPaused = false
        } catch {
            statusMessage = "Could not resume the meeting: \(error.localizedDescription)"
        }
    }

    func mark() async {
        guard let session else { return }
        do { _ = try await session.mark() }
        catch { statusMessage = "Could not mark this moment: \(error.localizedDescription)" }
    }

    func stop() async {
        guard let session, isRecording || isPaused else { return }
        onRecordingStopped?()
        monitorTask?.cancel()
        monitorTask = nil
        isRecording = false
        isPaused = false
        isTranscribing = true
        do {
            _ = try await session.stop()
            isTranscribing = false
            statusMessage = nil
        } catch {
            isTranscribing = false
            statusMessage = "Transcript could not be completed. Your meeting audio is saved. \(error.localizedDescription)"
        }
        await model.reloadMeetings()
    }

    func renameSession(id: MeetingID, title: String) async throws -> Bool {
        guard meetingID == id, let session else { return false }
        try await session.rename(title: title)
        return true
    }

    func saveGeneratedTextToSession(id: MeetingID, text: String, kind: MeetingTextKind) async throws -> Bool {
        guard meetingID == id, let session else { return false }
        try await session.saveGeneratedText(text, kind: kind)
        return true
    }

    func cancel() async {
        guard let session else { return }
        onRecordingStopped?()
        monitorTask?.cancel()
        monitorTask = nil
        isRecording = false
        isPaused = false
        isTranscribing = false
        do { _ = try await session.cancel() }
        catch { statusMessage = "Could not stop meeting audio: \(error.localizedDescription)" }
        await model.reloadMeetings()
    }

    func stopAndKeepForQuit() async throws {
        guard let session, isRecording || isPaused else { return }
        onRecordingStopped?()
        monitorTask?.cancel()
        monitorTask = nil
        isRecording = false
        isPaused = false
        isTranscribing = false
        _ = try await session.cancel()
        await model.reloadMeetings()
    }

    private func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isRecording, let writer = self.writer, let scheduler = self.scheduler, let capture = self.capture, let meetingID = self.meetingID else { continue }
                self.elapsed = self.elapsedBeforePause + max(0, Date().timeIntervalSince(self.startedAt))
                do {
                    for track in MeetingTrack.allCases {
                        let count = writer.sampleCount(for: track)
                        guard count > 0 else { continue }
                        let ranges = self.liveChunkCursor.takeReadyRanges(track: track, sampleCount: count)
                        for range in ranges {
                            let samples = try await writer.committedSamplesAsync(for: track, range: range)
                            guard !samples.isEmpty else { continue }
                            await scheduler.enqueueInterim(
                                meetingID: meetingID,
                                id: "\(track.rawValue)-\(range.lowerBound)",
                                track: track,
                                offset: Double(range.lowerBound) / Double(MeetingPCMJournal.sampleRate),
                                clip: AudioClip(samples: samples)
                            )
                        }
                    }
                    let line = await scheduler.latestLine
                    if !line.isEmpty { self.latestLine = line }
                    self.youLevel = await capture.level(for: .mic)
                    self.othersLevel = await capture.level(for: .system)
                } catch {
                    self.statusMessage = "Meeting checkpoint failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

private actor MeetingLiveTranscriptionScheduler: MeetingTranscriptionScheduler {
    private struct Job {
        let meetingID: MeetingID
        let id: String
        let track: MeetingTrack
        let offset: TimeInterval
        let clip: AudioClip
    }

    private let writer: MeetingPCMJournalWriter
    private let transcriber: any Transcriber
    private let language: SpeechLanguage
    private let processor = MeetingChunkProcessor()
    private var pending: [Job] = []
    private var submitted: Set<String> = []
    private var isDraining = false
    private var isFinalTranscribing = false
    private var cancelled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var latestSegmentText = ""
    private var session: MeetingSession?

    var latestLine: String { latestSegmentText }

    init(writer: MeetingPCMJournalWriter, transcriber: any Transcriber, language: SpeechLanguage) {
        self.writer = writer
        self.transcriber = transcriber
        self.language = language
    }

    func bindSession(_ session: MeetingSession) { self.session = session }

    func enqueueInterim(meetingID: MeetingID, id: String, track: MeetingTrack, offset: TimeInterval, clip: AudioClip) {
        guard !cancelled, submitted.insert(id).inserted else { return }
        pending.append(Job(meetingID: meetingID, id: id, track: track, offset: offset, clip: clip))
        guard !isDraining else { return }
        isDraining = true
        Task { await drain() }
    }

    func cancelQueued(meetingID: MeetingID) async {
        cancelled = true
        pending.removeAll { $0.meetingID == meetingID }
    }

    func waitForInFlight(meetingID: MeetingID) async {
        guard isDraining || isFinalTranscribing else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func transcribeFinal(
        _ manifest: MeetingManifest,
        chunkSeconds: TimeInterval,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> [MeetingChunkProcessingResult] {
        await cancelQueued(meetingID: manifest.id)
        await waitForInFlight(meetingID: manifest.id)
        cancelled = false
        isFinalTranscribing = true
        defer { isFinalTranscribing = false; resumeWaiters() }

        let checkpoint = try writer.storedCheckpoint()
        let planned = MeetingTrack.allCases.map { track in
            MeetingChunkPlanner.plan(
                sampleCount: checkpoint.track(track)?.sampleCount ?? 0,
                chunkSeconds: chunkSeconds
            )
        }
        let total = max(1, planned.reduce(0) { $0 + $1.count })
        var results: [MeetingChunkProcessingResult] = []
        var completed = 0
        for (trackIndex, track) in MeetingTrack.allCases.enumerated() {
            for (index, range) in planned[trackIndex].enumerated() {
                if cancelled { break }
                let samples = try writer.committedSamples(for: track, range: range)
                let result = try await processor.process(
                    id: "\(track.rawValue)-final-\(index)",
                    track: track,
                    offset: Double(range.lowerBound) / Double(MeetingPCMJournal.sampleRate),
                    clip: AudioClip(samples: samples),
                    configuredLanguage: language,
                    transcriber: transcriber
                )
                results.append(result)
                completed += 1
                await progress(Double(completed) / Double(total))
                if cancelled { break }
            }
        }
        if !cancelled { await progress(1) }
        return results
    }

    private func drain() async {
        while !pending.isEmpty && !cancelled {
            let job = pending.removeFirst()
            do {
                let result = try await processor.process(
                    id: job.id,
                    track: job.track,
                    offset: job.offset,
                    clip: job.clip,
                    configuredLanguage: language,
                    transcriber: transcriber
                )
                latestSegmentText = MeetingRecorderPresentation.latestLine(after: result, previous: latestSegmentText)
                await persistInterim(result, meetingID: job.meetingID)
            } catch {
                // Keep the latest valid line visible when a later chunk fails.
            }
        }
        isDraining = false
        resumeWaiters()
    }

    private func persistInterim(_ result: MeetingChunkProcessingResult, meetingID: MeetingID) async {
        guard let session, await session.snapshot()?.id == meetingID else { return }
        try? await session.persistInterim(result)
    }

    private func resumeWaiters() {
        guard !isDraining, !isFinalTranscribing else { return }
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }
}
