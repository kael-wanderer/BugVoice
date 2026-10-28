import AppKit
import AVFoundation
import Foundation
import Observation
import VoiceCore
import BugVoiceMac

@MainActor
@Observable
final class MeetingController {
    unowned let model: AppModel
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var isTranscribing = false
    private(set) var statusMessage: String? {
        didSet { if let statusMessage { Log.meeting.error("\(statusMessage, privacy: .public)") } }
    }
    private(set) var latestLine = ""
    private(set) var youLevel: Float = 0
    private(set) var othersLevel: Float = 0
    private(set) var elapsed: TimeInterval = 0
    /// Languages for the meeting being recorded; the recorder panel can change them.
    private(set) var languages: [SpeechLanguage] = MeetingLanguages.defaults
    /// The app whose microphone use offered this recording, if it came from the popup.
    private(set) var detected: MeetingCandidate?
    /// The meeting the meeting window shows. It stays after Stop until the window closes.
    private(set) var shownMeetingID: MeetingID?
    private(set) var title = ""
    private(set) var meetingStartedAt: Date?
    private(set) var folderID: FolderID?
    private(set) var segments: [MeetingSegment] = []
    private(set) var speakers: [MeetingSpeaker] = []
    private(set) var marks: [MeetingMark] = []
    private(set) var transcriptProgress: Double = 0
    /// "Marked at 12:47" for 2 seconds after Mark.
    private(set) var markFeedback: String?
    /// The owner's notes in the meeting window; saved 1 second after the last change.
    var notes = "" {
        didSet { if notes != oldValue { scheduleNotesSave() } }
    }
    private(set) var notesSaveFailed = false
    /// Opens the meeting window. Set by the app delegate, which owns it.
    var onShowWindow: (() -> Void)?
    /// Live summary state; written by `MeetingController+Assistant`.
    var liveSummary: String?
    var liveSummaryUpdatedAt: Date?
    /// The summary written after Stop; the Summary tab shows it once it exists.
    var finalSummary: String?
    var summaryState: MeetingSummaryState = .waiting
    var answer: MeetingAnswer?
    @ObservationIgnored var liveSummaryCutoff: TimeInterval = 0
    /// Active time at the last refresh; nil before the first.
    @ObservationIgnored var lastRefreshActiveTime: TimeInterval?
    @ObservationIgnored var notesAtLastRefresh = ""
    @ObservationIgnored var summaryTask: Task<Void, Never>?
    @ObservationIgnored var askTask: Task<Void, Never>?
    /// Show English for the shown meeting; written by `MeetingController+Translation`.
    var showEnglish = true
    /// The last translation try found no Meetings model.
    var translationNeedsModel = false
    @ObservationIgnored var translationTask: Task<Void, Never>?
    @ObservationIgnored var translationLoop: Task<Void, Never>?
    /// No translation before this time after a failed request.
    @ObservationIgnored var translationRetryAt: Date?
    /// True from Stop until the final summary is written.
    @ObservationIgnored var translationHeld = false
    @ObservationIgnored private var notesSaveTask: Task<Void, Never>?
    @ObservationIgnored private var markFeedbackTask: Task<Void, Never>?
    @ObservationIgnored private(set) var session: MeetingSession?
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
    /// The window shows a meeting that has finished transcribing.
    var isFinished: Bool { shownMeetingID != nil && !isActive }

    func toggleRecording() {
        if isActive {
            Task { await stop() }
        } else {
            Task { await start() }
        }
    }

    /// Turns one language on or off for the current meeting. The last one stays on.
    func toggleLanguage(_ language: SpeechLanguage) {
        var next = languages.contains(language) ? languages.filter { $0 != language } : languages + [language]
        guard !next.isEmpty else { return }
        next = MeetingLanguages.choices.filter(next.contains)
        languages = next
        guard let session, let scheduler else { return }
        Task {
            await scheduler.setLanguages(next)
            try? await session.setLanguages(next)
        }
    }

    func start(detected: MeetingCandidate? = nil) async {
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
            let languages = model.settings.meetings.languages
            let scheduler = MeetingLiveTranscriptionScheduler(
                writer: writer,
                transcriber: model.transcriptionRouter,
                languages: languages
            )
            let finalizer = MeetingAudioFinalizer(meetingDirectory: directory)
            let session = MeetingSession(
                store: store, audio: capture, scheduler: scheduler, finalizer: finalizer, meetingID: id
            )
            await scheduler.bindSession(session)
            _ = try await session.start(
                labels: ItemLabels(folderID: model.meetingsFolderFilter.newItemFolderID),
                languages: languages
            )
            if let detected {
                // The recording matters more than its title.
                try? await session.rename(title: detected.title)
                try? await session.setDetectedApp(detected.bundleID)
            }
            self.detected = detected
            self.session = session
            self.capture = capture
            self.writer = writer
            self.scheduler = scheduler
            self.meetingID = id
            liveChunkCursor = MeetingLiveChunkCursor()
            startedAt = Date()
            elapsedBeforePause = 0
            elapsed = 0
            self.languages = languages
            latestLine = ""
            showMeeting(await session.snapshot())
            isRecording = true
            isPaused = false
            statusMessage = nil
            model.setSystemAudioCaptureObserved(true)
            startMonitor()
            startTranslationLoop()
            onShowWindow?()
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
            languages: model.settings.meetings.languages
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
            // Like Stop, a new recording may start while speakers and the summary are worked out.
            isTranscribing = false
            statusMessage = nil
            await model.reloadMeetings()
            if recovered.state == .ready, !recovered.segments.isEmpty {
                await model.findSpeakers(id: id, people: nil)
                await refreshSnapshot()
                // Recovery may have no visible meeting window. Finish the same sequence as Stop.
                if shownMeetingID == id { await generateFinalSummary() }
                else { _ = try? await model.generateMeetingText(id: id, kind: .summary) { _ in } }
            }
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
        do {
            let mark = try await session.mark()
            marks.append(mark)
            markFeedback = "Marked at \(MeetingTimeText.text(mark.offset))"
            markFeedbackTask?.cancel()
            markFeedbackTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.markFeedback = nil
            }
        } catch {
            statusMessage = "Could not mark this moment: \(error.localizedDescription)"
        }
    }

    /// Renames the meeting in the window; an empty title keeps the old one.
    func rename(_ newTitle: String) async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session, !trimmed.isEmpty, trimmed != title else { return }
        do {
            try await session.rename(title: trimmed)
            title = trimmed
        } catch {
            statusMessage = "Could not rename the meeting: \(error.localizedDescription)"
        }
    }

    func setFolder(_ folderID: FolderID?) async {
        guard let session, let meeting = await session.snapshot() else { return }
        do {
            try await session.setLabels(folderID: folderID, tags: meeting.tags, suggestedTags: nil)
            self.folderID = folderID
        } catch {
            statusMessage = "Could not move the meeting: \(error.localizedDescription)"
        }
    }

    /// Saves the notes now instead of after the 1-second pause.
    func flushNotes() async {
        notesSaveTask?.cancel()
        notesSaveTask = nil
        await saveNotes()
    }

    /// Notes for `id` from the detail page; false when the window's session does not own it.
    func setNotesInSession(id: MeetingID, notes: String) async throws -> Bool {
        guard meetingID == id, let session else { return false }
        try await session.setNotes(notes)
        if shownMeetingID == id { self.notes = notes }
        return true
    }

    /// Closes the finished meeting in the window. A recording keeps its window.
    func closeWindow() async {
        guard !isActive else { return }
        closeAnswer()
        await flushNotes()
        shownMeetingID = nil
        await model.reloadMeetings()
    }

    private func scheduleNotesSave() {
        guard shownMeetingID != nil else { return }
        notesSaveTask?.cancel()
        notesSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.saveNotes()
        }
    }

    private func saveNotes() async {
        guard let session, let meeting = await session.snapshot(), meeting.id == shownMeetingID,
              meeting.notes != notes else { return }
        do {
            try await session.setNotes(notes)
            notesSaveFailed = false
        } catch {
            // The notes stay in the editor; the next change or flush tries again.
            notesSaveFailed = true
        }
    }

    /// Loads the window's fields from a manifest when a meeting starts.
    private func showMeeting(_ meeting: MeetingManifest?) {
        guard let meeting else { return }
        shownMeetingID = meeting.id
        title = meeting.title
        meetingStartedAt = meeting.startedAt
        folderID = meeting.folderID
        segments = meeting.segments
        speakers = meeting.speakers
        marks = meeting.marks
        transcriptProgress = meeting.transcriptProgress ?? 0
        notesSaveTask?.cancel()
        notes = meeting.notes
        notesSaveTask?.cancel()
        notesSaveFailed = false
        markFeedback = nil
        liveSummary = meeting.liveSummary
        liveSummaryUpdatedAt = meeting.liveSummaryUpdatedAt
        liveSummaryCutoff = meeting.liveSummaryCutoff
        lastRefreshActiveTime = nil
        notesAtLastRefresh = meeting.notes
        finalSummary = meeting.summary
        summaryState = .waiting
        answer = nil
        showEnglish = meeting.showEnglish
    }

    /// Shows English the translation loop saved, also after Stop when no snapshot refresh runs.
    func showTranslations(from meeting: MeetingManifest) {
        guard meeting.id == shownMeetingID, segments != meeting.segments else { return }
        segments = meeting.segments
        speakers = meeting.speakers
    }

    /// Picks up transcript lines, marks and progress the session saved.
    private func refreshSnapshot() async {
        guard let session, let meeting = await session.snapshot(), meeting.id == shownMeetingID else { return }
        if segments != meeting.segments { segments = meeting.segments }
        if speakers != meeting.speakers { speakers = meeting.speakers }
        if marks != meeting.marks { marks = meeting.marks }
        if let progress = meeting.transcriptProgress, transcriptProgress != progress { transcriptProgress = progress }
        if title != meeting.title { title = meeting.title }
    }

    func stop() async {
        guard let session, isRecording || isPaused else { return }
        let recordedSeconds = elapsed
        // A finished window has no Ask box; an open answer would offer Add to notes after the notes are saved.
        closeAnswer()
        await flushNotes()
        translationHeld = true
        defer { translationHeld = false }
        isRecording = false
        isPaused = false
        isTranscribing = true
        var transcribed = false
        do {
            _ = try await session.stop()
            await refreshSnapshot()
            isTranscribing = false
            statusMessage = nil
            transcribed = true
        } catch {
            isTranscribing = false
            statusMessage = "Transcript could not be completed. Your meeting audio is saved. \(error.localizedDescription)"
        }
        monitorTask?.cancel()
        monitorTask = nil
        await model.reloadMeetings()
        await model.recordMeetingInsights(seconds: recordedSeconds)
        if transcribed, let id = meetingID, !segments.isEmpty {
            await model.findSpeakers(id: id, people: nil)
            await refreshSnapshot()
            await generateFinalSummary()
        }
    }

    func updateSpeakersInSession(id: MeetingID, change: @Sendable (MeetingManifest) throws -> MeetingManifest) async throws -> Bool {
        guard let session, await session.snapshot()?.id == id else { return false }
        try await session.updateSpeakers(change)
        await refreshSnapshot()
        return true
    }

    func renameSession(id: MeetingID, title: String) async throws -> Bool {
        guard meetingID == id, let session else { return false }
        try await session.rename(title: title)
        return true
    }

    func setLabelsInSession(id: MeetingID, folderID: FolderID?, tags: [String], suggestedTags: [String]?) async throws -> Bool {
        guard meetingID == id, let session else { return false }
        try await session.setLabels(folderID: folderID, tags: tags, suggestedTags: suggestedTags)
        return true
    }

    func saveGeneratedTextToSession(
        id: MeetingID, text: String, kind: MeetingTextKind, names: [String: String]? = nil, template: SummaryTemplate = .general
    ) async throws -> Bool {
        guard meetingID == id, let session else { return false }
        try await session.saveGeneratedText(text, kind: kind, names: names, template: template)
        return true
    }

    func cancel() async {
        guard let session else { return }
        await flushNotes()
        monitorTask?.cancel()
        monitorTask = nil
        translationLoop?.cancel()
        translationLoop = nil
        isRecording = false
        isPaused = false
        isTranscribing = false
        do { _ = try await session.cancel() }
        catch { statusMessage = "Could not stop meeting audio: \(error.localizedDescription)" }
        await model.reloadMeetings()
    }

    func stopAndKeepForQuit() async throws {
        guard let session, isRecording || isPaused else { return }
        let recordedSeconds = elapsed
        await flushNotes()
        monitorTask?.cancel()
        monitorTask = nil
        isRecording = false
        isPaused = false
        isTranscribing = false
        _ = try await session.cancel()
        await model.reloadMeetings()
        // The audio is kept and finished on next launch, so it counts now.
        await model.recordMeetingInsights(seconds: recordedSeconds)
    }

    private func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                await self.refreshSnapshot()
                guard self.isRecording, let writer = self.writer, let scheduler = self.scheduler, let capture = self.capture, let meetingID = self.meetingID else { continue }
                self.elapsed = self.elapsedBeforePause + max(0, Date().timeIntervalSince(self.startedAt))
                do {
                    for track in MeetingTrack.recordingTracks {
                        while let range = self.liveChunkCursor.nextReadyRange(
                            track: track,
                            sampleCount: writer.sampleCount(for: track)
                        ) {
                            let samples = try await writer.committedSamplesAsync(for: track, range: range)
                            guard !samples.isEmpty else { break }
                            await scheduler.enqueueInterim(
                                meetingID: meetingID,
                                id: "\(track.rawValue)-\(range.lowerBound)",
                                track: track,
                                offset: Double(range.lowerBound) / Double(MeetingPCMJournal.sampleRate),
                                clip: AudioClip(samples: samples)
                            )
                            self.liveChunkCursor.markSent(track: track)
                        }
                    }
                    let line = await scheduler.latestLine
                    if !line.isEmpty { self.latestLine = line }
                    self.youLevel = await capture.level(for: .mic)
                    self.othersLevel = await capture.level(for: .system)
                    self.refreshLiveSummaryIfDue()
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
    private var languages: [SpeechLanguage]
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

    init(writer: MeetingPCMJournalWriter, transcriber: any Transcriber, languages: [SpeechLanguage]) {
        self.writer = writer
        self.transcriber = transcriber
        self.languages = languages
    }

    func setLanguages(_ languages: [SpeechLanguage]) { self.languages = languages }

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

        let languages = manifest.languages.isEmpty ? languages : manifest.languages
        let checkpoint = try writer.storedCheckpoint()
        let planned = MeetingTrack.recordingTracks.map { track in
            MeetingChunkPlanner.plan(
                sampleCount: checkpoint.track(track)?.sampleCount ?? 0,
                chunkSeconds: chunkSeconds
            )
        }
        let total = max(1, planned.reduce(0) { $0 + $1.count })
        var results: [MeetingChunkProcessingResult] = []
        var completed = 0
        for (trackIndex, track) in MeetingTrack.recordingTracks.enumerated() {
            for (index, range) in planned[trackIndex].enumerated() {
                if cancelled { break }
                let samples = try writer.committedSamples(for: track, range: range)
                let result = try await processor.process(
                    id: "\(track.rawValue)-final-\(index)",
                    track: track,
                    offset: Double(range.lowerBound) / Double(MeetingPCMJournal.sampleRate),
                    clip: AudioClip(samples: samples),
                    languages: languages,
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
                    languages: languages,
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
