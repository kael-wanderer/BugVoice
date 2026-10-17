import AppKit
import BugVoiceMac
import Foundation
import Observation
import VoiceCore

@MainActor
@Observable
final class UploadController {
    struct Draft: Identifiable, Sendable {
        let id = UUID()
        let url: URL
        let metadata: UploadMediaMetadata
        let scoped: Bool
        var labels = ItemLabels()
    }

    private unowned let model: AppModel
    private(set) var queue = UploadQueue()
    private(set) var drafts: [Draft] = []
    private(set) var draftError: String?
    private(set) var errorFileName: String?
    private(set) var probing = false
    private(set) var sleeping = false
    private(set) var accepting = false
    private(set) var waitingForMeeting = false
    @ObservationIgnored private var inputs: [UUID: Draft] = [:]
    @ObservationIgnored private var restored: [UUID: MeetingManifest] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var decoder: Task<Void, Error>?
    @ObservationIgnored private var session: MeetingSession?
    @ObservationIgnored private var scheduler: UploadTranscriptionScheduler?
    @ObservationIgnored private var activeID: UUID?
    @ObservationIgnored private var activeDirectory: URL?
    @ObservationIgnored private var progressMonitor: Task<Void, Never>?
    private var stopping = false
    private var selectionVersion = 0

    init(model: AppModel) {
        self.model = model
        progressMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                await self?.refreshProgress()
            }
        }
    }

    var isBusy: Bool { worker != nil || !queue.jobs.filter { !$0.state.isTerminal }.isEmpty }
    var active: UploadJob? { queue.active }

    func choose(_ urls: [URL]) async {
        guard accepting else { return }
        clearDraft()
        selectionVersion += 1
        let version = selectionVersion
        probing = true
        defer { if version == selectionVersion { probing = false } }
        var selected: [Draft] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            do {
                let metadata = try await Task.detached(priority: .utility) {
                    try await MediaAudioDecoder.probe(url)
                }.value
                guard version == selectionVersion else {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    for item in selected { release(item) }
                    return
                }
                var draft = Draft(url: url, metadata: metadata, scoped: scoped)
                draft.labels.folderID = model.library.folder(model.library.lastUploadFolderID)?.id
                selected.append(draft)
            } catch {
                if scoped { url.stopAccessingSecurityScopedResource() }
                for item in selected { release(item) }
                guard version == selectionVersion else { return }
                errorFileName = url.lastPathComponent
                draftError = (error as? UploadFailure ?? .unreadable).localizedDescription
                return
            }
        }
        drafts = selected
    }

    func clearDraft() {
        selectionVersion += 1
        for item in drafts { release(item) }
        drafts.removeAll()
        draftError = nil
        errorFileName = nil
        probing = false
    }

    func setDraftLabels(_ id: UUID, _ labels: ItemLabels) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].labels = labels
    }

    /// Copies the first card's folder and tags to every card.
    func applyFirstLabelsToAll() {
        guard let first = drafts.first?.labels else { return }
        for index in drafts.indices { drafts[index].labels = first }
    }

    func submit() {
        guard accepting, !probing else { return }
        let jobs = drafts.map { draft in
            let job = UploadJob(
                fileName: draft.metadata.fileName, kind: draft.metadata.kind,
                duration: draft.metadata.duration, byteSize: draft.metadata.byteSize)
            inputs[job.id] = draft
            return job
        }
        let lastFolder = drafts.last?.labels.folderID
        Task { await model.setLastUploadFolder(lastFolder) }
        drafts.removeAll()
        queue.append(jobs)
        pump()
    }

    func clearFinished() {
        queue.clearFinished()
    }

    func restore(_ manifests: [MeetingManifest]) {
        for manifest in manifests.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            appendRecovery(manifest)
        }
        accepting = true
        pump()
    }

    func retry(_ meeting: MeetingManifest) {
        guard meeting.source == .upload, meeting.state == .transcribing,
            !queue.jobs.contains(where: { $0.meetingID == meeting.id && !$0.state.isTerminal })
        else { return }
        appendRecovery(meeting)
        pump()
    }

    private func appendRecovery(_ meeting: MeetingManifest) {
        var job = UploadJob(
            fileName: meeting.sourceFileName ?? meeting.title, kind: .audio, duration: meeting.duration,
            byteSize: 0)
        job.meetingID = meeting.id
        restored[job.id] = meeting
        queue.append([job])
    }

    func reconcile(_ manifests: [MeetingManifest]) {
        queue.reconcile(existing: Set(manifests.map(\.id)))
    }

    func open(_ id: MeetingID) {
        model.selectedMeetingID = id
        model.openMainWindow(.meetings)
    }

    func renameSession(id: MeetingID, title: String) async throws -> Bool {
        guard activeDirectory?.lastPathComponent == id.rawValue, let session else { return false }
        try await session.rename(title: title)
        return true
    }

    func setLabelsInSession(id: MeetingID, folderID: FolderID?, tags: [String], suggestedTags: [String]?) async throws -> Bool {
        guard activeDirectory?.lastPathComponent == id.rawValue, let session else { return false }
        try await session.setLabels(folderID: folderID, tags: tags, suggestedTags: suggestedTags)
        return true
    }

    func updateSpeakersInSession(id: MeetingID, change: @Sendable (MeetingManifest) throws -> MeetingManifest) async throws -> Bool {
        guard activeDirectory?.lastPathComponent == id.rawValue, let session else { return false }
        try await session.updateSpeakers(change)
        return true
    }

    func saveGeneratedTextToSession(id: MeetingID, text: String, kind: MeetingTextKind, names: [String: String]? = nil)
        async throws -> Bool
    {
        guard activeDirectory?.lastPathComponent == id.rawValue, let session else { return false }
        try await session.saveGeneratedText(text, kind: kind, names: names)
        return true
    }

    func setSleeping(_ value: Bool) {
        sleeping = value
        if !value { pump() }
    }

    private func waitForReadingBoundary() async throws {
        while sleeping {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
    }

    private func waitForRecognition() async throws {
        while sleeping || model.meetings?.isActive == true {
            waitingForMeeting = model.meetings?.isActive == true
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(100))
        }
        waitingForMeeting = false
        try Task.checkCancellation()
    }

    private func pump() {
        guard worker == nil, accepting, !stopping else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            defer {
                self.worker = nil
                self.activeID = nil
                self.activeDirectory = nil
                self.session = nil
                self.scheduler = nil
            }
            while !Task.isCancelled && !self.stopping {
                // Keep queued jobs waiting through recording, pause and final pass.
                if self.sleeping || self.model.meetings?.isActive == true {
                    do { try await self.waitForRecognition() } catch { return }
                }
                guard let job = self.queue.admit(meetingActive: false) else { return }
                await self.run(job)
            }
        }
    }

    private func run(_ job: UploadJob) async {
        let saved = restored.removeValue(forKey: job.id)
        let id = saved?.id ?? MeetingID.new()
        let directory = model.paths.meetings.appendingPathComponent(id.rawValue, isDirectory: true)
        activeID = job.id
        activeDirectory = directory
        queue.attach(id: job.id, meetingID: id)
        let writer = MeetingPCMJournalWriter(directory: directory.appendingPathComponent(".capture"))
        let scheduler = UploadTranscriptionScheduler(
            writer: writer, transcriber: model.transcriptionRouter,
            languages: model.settings.meetings.languages,
            gate: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.waitForRecognition()
            }
        )
        let session = MeetingSession(
            store: MeetingStore(root: model.paths.meetings),
            audio: UploadAudioSourceControl(writer: writer),
            scheduler: scheduler,
            finalizer: UploadAudioFinalizer(meetingDirectory: directory),
            meetingID: id
        )
        self.scheduler = scheduler
        self.session = session
        await scheduler.bindSession(session)
        do {
            if let saved {
                queue.apply(id: job.id, event: .committed(saved.id))
                _ = try await session.recover(id: saved.id)
            } else {
                guard let draft = inputs[job.id] else { throw UploadFailure.unreadable }
                let now = Date()
                let startedAt = draft.metadata.creationDate ?? now
                var manifest = MeetingManifest(
                    id: id,
                    title: (draft.metadata.fileName as NSString).deletingPathExtension,
                    startedAt: startedAt,
                    endedAt: startedAt.addingTimeInterval(draft.metadata.duration),
                    duration: draft.metadata.duration,
                    state: .interrupted,
                    source: .upload,
                    sourceFileName: draft.metadata.fileName,
                    importedAt: now,
                    folderID: draft.labels.folderID,
                    tags: draft.labels.tags
                )
                try await MeetingStore(root: model.paths.meetings).save(manifest)
                let decoding = Task.detached(priority: .utility) { [controller = self] in
                    try await MediaAudioDecoder.decode(
                        draft.url, metadata: draft.metadata, writer: writer,
                        boundary: {
                            try await controller.waitForReadingBoundary()
                        },
                        progress: { value in
                            await controller.readingProgress(value, id: job.id)
                        })
                }
                decoder = decoding
                try await withTaskCancellationHandler {
                    try await decoding.value
                } onCancel: {
                    decoding.cancel()
                }
                decoder = nil
                releaseInput(job.id)
                try Task.checkCancellation()
                manifest.state = .transcribing
                // Writer is closed, EOF checkpoint succeeded: atomically commit before speech.
                try await MeetingStore(root: model.paths.meetings).save(manifest)
                queue.apply(id: job.id, event: .committed(id))
                _ = try await session.transcribeUpload(manifest)
            }
            try Task.checkCancellation()
            guard !stopping else { return }
            queue.apply(id: job.id, event: .ready)
            if let ready = await session.snapshot(), !ready.segments.isEmpty {
                await model.findSpeakers(id: ready.id, people: nil)
            }
        } catch {
            decoder = nil
            releaseInput(job.id)
            if stopping || error is CancellationError { return }
            let failure: UploadFailure
            if UploadFailure.isDiskFull(error) {
                failure = .diskFull
                await removeFailedImport(directory)
            } else if let upload = error as? UploadFailure, upload == .transcript || upload == .audioSave
            {
                failure = upload
            } else if saved != nil, error as? UploadFailure == .missingJournal {
                failure = .missingJournal
                var failed = saved!
                failed.state = .failed
                failed.transcriptionError = failure.localizedDescription
                do { try await MeetingStore(root: model.paths.meetings).save(failed) } catch {
                    model.saveError = error.localizedDescription
                }
            } else {
                failure = (error as? UploadFailure) == .noAudio ? .noAudio : .unreadable
                await removeFailedImport(directory)
            }
            queue.apply(id: job.id, event: .failed(failure.localizedDescription))
        }
        await model.reloadMeetings()
    }

    private func readingProgress(_ value: Double?, id: UUID) {
        guard !stopping, activeID == id else { return }
        queue.apply(id: id, event: .progress(value))
    }

    func refreshProgress() async {
        guard !stopping, let id = activeID, queue.active?.state == .transcribing,
            let manifest = await session?.snapshot()
        else { return }
        queue.apply(id: id, event: .progress(manifest.transcriptProgress))
    }

    func cancel(_ id: UUID) async {
        guard let job = queue.jobs.first(where: { $0.id == id }), !job.state.isTerminal else { return }
        if id != activeID {
            if let meeting = restored[id] {
                let directory = model.paths.meetings.appendingPathComponent(meeting.id.rawValue)
                do {
                    try markForRemoval(directory)
                    await model.cancelMeetingText(id: meeting.id)
                    try FileManager.default.removeItem(at: directory)
                } catch {
                    queue.apply(id: id, event: .cleanupFailed)
                    return
                }
            }
            releaseInput(id)
            restored.removeValue(forKey: id)
            queue.apply(id: id, event: .cancelled)
            await model.reloadMeetings()
            return
        }
        guard let directory = activeDirectory else { return }
        do {
            try markForRemoval(directory)
        } catch {
            model.saveError = UploadFailure.cleanup.localizedDescription
            return
        }
        stopping = true
        if let meetingID = job.meetingID {
            await model.cancelMeetingText(id: meetingID)
        }
        await session?.invalidateUpload()
        worker?.cancel()
        decoder?.cancel()
        let draining = worker
        await draining?.value
        do {
            try FileManager.default.removeItem(at: directory)
            queue.apply(id: id, event: .cancelled)
        } catch {
            queue.apply(id: id, event: .cleanupFailed)
        }
        releaseInput(id)
        stopping = false
        await model.reloadMeetings()
        pump()
    }

    func quiesceForQuit() async {
        accepting = false
        stopping = true
        progressMonitor?.cancel()
        progressMonitor = nil
        clearDraft()
        worker?.cancel()
        decoder?.cancel()
        let draining = worker
        await draining?.value
        for id in Array(inputs.keys) { releaseInput(id) }
        // No marker, no deletion: interrupted reading is discardable; transcribing is resumable.
    }

    private func release(_ draft: Draft) {
        if draft.scoped { draft.url.stopAccessingSecurityScopedResource() }
    }

    private func releaseInput(_ id: UUID) {
        if let draft = inputs.removeValue(forKey: id) { release(draft) }
    }

    private func markForRemoval(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = directory.appendingPathComponent(".upload-cancelled")
        try Data().write(to: marker)
        let handle = try FileHandle(forWritingTo: marker)
        try handle.synchronize()
        try handle.close()
        // Directory sync uses the same macOS durability primitive as AAC replacement.
        try UploadCancellationMarker.sync(directory)
    }

    private func removeFailedImport(_ directory: URL) async {
        do {
            try markForRemoval(directory)
            try FileManager.default.removeItem(at: directory)
        } catch {
            model.saveError = UploadFailure.cleanup.localizedDescription
        }
    }
}
