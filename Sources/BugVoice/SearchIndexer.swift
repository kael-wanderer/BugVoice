import Foundation
import Observation
import VoiceCore

/// One serial queue. Text is rebuilt from the current items; disk stores only hashes and vectors.
@MainActor @Observable
final class SearchIndexer {
    enum Status: Equatable { case off, upToDate, indexing(done: Int, total: Int), unavailable }
    var status: Status = .off
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let store: SearchIndexStore
    @ObservationIgnored private var queue: [AskSource: Date] = [:]
    @ObservationIgnored private var revisions: [AskSource: Int] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var activeSource: AskSource?
    @ObservationIgnored private var activePassages: [AskPassage] = []
    /// Headers of the files on disk (no vectors), read once per item and kept in step with every
    /// save, remove and prune. A source in `checked` without a summary has no usable file.
    @ObservationIgnored private var summaries: [AskSource: SearchIndexSummary] = [:]
    @ObservationIgnored private var checked: Set<AskSource> = []
    /// False until bootstrap has loaded notes, meetings and history: before that a list that has
    /// not loaded yet would look empty and prune every file of its kind.
    @ObservationIgnored private var librariesLoaded = false
    @ObservationIgnored private var pendingKinds: Set<AskSource.Kind> = []
    @ObservationIgnored private var pendingBackfill = false
    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var lastMeetings: [MeetingManifest]?
    @ObservationIgnored private var lastNotes: [NoteDocument]?

    init(model: AppModel) {
        self.model = model
        store = SearchIndexStore(folder: model.paths.searchIndex)
    }

    /// `extend: false` keeps an earlier pending deadline (the dictation batch delay).
    func schedule(_ source: AskSource, after delay: Duration = .zero, extend: Bool = true) {
        revisions[source, default: 0] += 1
        let proposed = Date().addingTimeInterval(Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18)
        queue[source] = SearchIndexPlanner.deadline(existing: queue[source], proposed: proposed, extend: extend)
        start()
    }

    /// Bootstrap calls this once notes, meetings and history have all loaded.
    func librariesDidLoad() {
        librariesLoaded = true
        backfill()
    }

    /// After an embedding setting changes. Queues only items whose file is missing, stale or
    /// out of step with the item; does nothing until the libraries have loaded.
    func backfill() {
        guard let model, librariesLoaded else { return }
        generation += 1
        if ProviderFactory.embedder(settings: model.settings.models, credentials: model.credentials) == nil { status = .off }
        pendingBackfill = true
        pendingKinds.formUnion([.meeting, .note, .dictations])
        startListPass()
    }

    func remove(_ source: AskSource) async {
        revisions[source, default: 0] += 1
        queue[source] = nil
        try? await store.remove(source)
        summaries[source] = nil
        checked.insert(source)
    }

    private func prune(keeping sources: Set<AskSource>, kinds: Set<AskSource.Kind>) async {
        for source in Array(queue.keys) where kinds.contains(source.kind) && !sources.contains(source) {
            revisions[source, default: 0] += 1
            queue[source] = nil
        }
        try? await store.prune(keeping: sources, kinds: kinds)
        for source in checked.union(summaries.keys) where kinds.contains(source.kind) && !sources.contains(source) {
            summaries[source] = nil
            checked.insert(source)
        }
    }

    private func summary(_ source: AskSource) async -> SearchIndexSummary? {
        if checked.contains(source) { return summaries[source] }
        let read = await store.summary(source)
        summaries[source] = read
        checked.insert(source)
        return read
    }

    private func record(_ file: SearchIndexFile, for source: AskSource) {
        summaries[source] = SearchIndexSummary(file)
        checked.insert(source)
    }

    /// Drops deleted history vectors (delete, clear, retention), without embedding.
    func reconcileHistory() async {
        revisions[.dictations, default: 0] += 1
        let current = passages(.dictations)
        if current.isEmpty {
            await remove(.dictations)
            return
        }
        if let old = await store.load(.dictations) {
            let kept = SearchIndexPlanner.update(old, passages: current, model: old.model).keep
            if SearchIndexPlanner.needsSave(old: old, updated: kept), (try? await store.save(kept, for: .dictations)) != nil {
                record(kept, for: .dictations)
            }
        }
        // The revision bump stopped any dictation embedding in flight: queue it again.
        guard librariesLoaded, queue[.dictations] == nil, let model,
              let embedder = ProviderFactory.embedder(settings: model.settings.models, credentials: model.credentials)
        else { return }
        if SearchIndexPlanner.needsWork(await summary(.dictations), passages: passages(.dictations), model: embedder.modelID) {
            schedule(.dictations)
        }
    }

    /// A list of `kind` was reloaded. Never awaited by the caller; passes coalesce.
    func listLoaded(_ kind: AskSource.Kind) {
        guard librariesLoaded else { return }
        pendingKinds.insert(kind)
        startListPass()
    }

    private func startListPass() {
        guard listTask == nil else { return }
        listTask = Task { [weak self] in
            while let self, !self.pendingKinds.isEmpty {
                let kinds = self.pendingKinds, force = self.pendingBackfill
                self.pendingKinds = []
                self.pendingBackfill = false
                await self.reconcileLists(kinds, force: force)
            }
            self?.listTask = nil
        }
    }

    private func reconcileLists(_ requested: Set<AskSource.Kind>, force: Bool) async {
        guard let model else { return }
        var kinds = requested
        // The meetings list reloads every 2 s while one is open: skip when nothing changed.
        if !force {
            if kinds.contains(.meeting), lastMeetings == model.meetingManifests { kinds.remove(.meeting) }
            if kinds.contains(.note), lastNotes == model.notesController.notes { kinds.remove(.note) }
        }
        if kinds.contains(.meeting) { lastMeetings = model.meetingManifests }
        if kinds.contains(.note) { lastNotes = model.notesController.notes }
        guard !kinds.isEmpty else { return }
        let sources = sourcesNewestFirst()
        await prune(keeping: Set(sources), kinds: kinds)
        guard let embedder = ProviderFactory.embedder(settings: model.settings.models, credentials: model.credentials) else { return }
        for source in sources where kinds.contains(source.kind) && queue[source] == nil {
            let current = passages(source)
            guard SearchIndexPlanner.needsWork(await summary(source), passages: current, model: embedder.modelID) else { continue }
            // A backfill bumped the generation, so work in flight is dropped and must be queued again.
            // Otherwise in-flight work for the same text will save it; a note's 30-second debounce
            // and the dictation batch delay stay in the queue and are not bypassed.
            if force || activeSource != source || activePassages != current { schedule(source) }
        }
        if queue.isEmpty && worker == nil { status = .upToDate }
        if !queue.isEmpty { start() } // Retries an item left queued by a failed run.
    }

    func searchInputs() -> (passages: [AskPassage], titles: [SearchTitle]) {
        guard let model else { return ([], []) }
        let passages = sourcesNewestFirst().flatMap { self.passages($0) }
        let titles = model.meetingManifests.map { SearchTitle(source: .meeting($0.id), title: $0.title, date: $0.startedAt) }
            + model.notesController.notes.map { SearchTitle(source: .note($0.id), title: $0.title, date: $0.modifiedAt) }
        return (passages, titles)
    }

    private func sourcesNewestFirst() -> [AskSource] {
        guard let model else { return [] }
        var dated = model.meetingManifests.filter { $0.state == .ready }.map { (AskSource.meeting($0.id), $0.startedAt) }
        dated += model.notesController.notes.map { (AskSource.note($0.id), $0.modifiedAt) }
        if let date = model.history.map(\.startedAt).max() { dated.append((.dictations, date)) }
        return dated.sorted { $0.1 > $1.1 }.map(\.0)
    }

    private func passages(_ source: AskSource) -> [AskPassage] {
        guard let model else { return [] }
        switch source {
        case .meeting(let id):
            guard let meeting = model.meetingManifests.first(where: { $0.id == id }) else { return [] }
            return AskPassageBuilder.passages(meeting: meeting)
        case .note(let id):
            guard let note = model.notesController.notes.first(where: { $0.id == id }) else { return [] }
            return AskPassageBuilder.passages(note: note)
        case .dictations: return AskPassageBuilder.passages(dictations: model.history)
        }
    }

    private func waitUntilAvailable() async throws {
        while let model, model.dictation?.isBusy == true || model.isListening || model.notesIsListening || model.meetings?.isRecording == true {
            try await Task.sleep(for: .seconds(1))
        }
        try Task.checkCancellation()
    }

    private func start() {
        guard worker == nil else { return }
        worker = Task(priority: .background) { [weak self] in
            await self?.run()
            self?.worker = nil
        }
    }

    private func run() async {
        var done = 0
        defer { activeSource = nil; activePassages = [] }
        while !queue.isEmpty {
            var epoch = generation
            do {
                try await waitUntilAvailable()
                guard let model, let embedder = ProviderFactory.embedder(settings: model.settings.models, credentials: model.credentials) else {
                    status = .off
                    return
                }
                epoch = generation
                guard let next = queue.min(by: { $0.value < $1.value }) else { break }
                if next.value > Date() { try await Task.sleep(for: .seconds(min(1, next.value.timeIntervalSinceNow))); continue }
                let source = next.key
                activeSource = source
                queue[source] = nil
                let revision = revisions[source, default: 0]
                status = .indexing(done: done, total: done + queue.count + 1)
                let current = passages(source)
                activePassages = current
                let old = await store.load(source)
                var (file, missing) = SearchIndexPlanner.update(old, passages: current, model: embedder.modelID)
                for offset in stride(from: 0, to: missing.count, by: OpenAICompatibleEmbedder.batchSize) {
                    try await waitUntilAvailable()
                    guard generation == epoch, revisions[source] == revision else { break }
                    let batch = Array(missing[offset..<min(offset + OpenAICompatibleEmbedder.batchSize, missing.count)])
                    let vectors = try await embedder.embed(batch.map(\.searchText))
                    guard vectors.count == batch.count, let dimensions = vectors.first?.count, dimensions > 0,
                          vectors.allSatisfy({ $0.count == dimensions }), file.dimensions == 0 || file.dimensions == dimensions else {
                        throw ProviderError.malformedResponse("Invalid embedding dimensions")
                    }
                    file.dimensions = dimensions
                    file.entries += batch.map { .init(passageID: $0.id, contentHash: $0.contentHash) }
                    file.vectors += vectors
                }
                guard generation == epoch, revisions[source] == revision else { continue }
                // A deleted item must never be recreated by an in-flight embedding response.
                // An unchanged file is not rewritten.
                if sourcesNewestFirst().contains(source), SearchIndexPlanner.needsSave(old: old, updated: file) {
                    try await store.save(file, for: source)
                    record(file, for: source)
                } else {
                    summaries[source] = old.map(SearchIndexSummary.init)
                    checked.insert(source)
                }
                done += 1
            } catch {
                // A failure from a replaced model must not strand the new rebuild.
                if generation != epoch { continue }
                if let activeSource, queue[activeSource] == nil { queue[activeSource] = Date() }
                status = .unavailable
                return // A later trigger retries; no partial file is saved.
            }
        }
        status = .upToDate
    }

    func corpus(scope: AskScope) async -> AskCorpus {
        guard let model else { return AskCorpus(passages: [], info: [:], vectors: [:], meetings: 0, notes: 0, dictations: 0) }
        var all: [AskPassage] = [], info: [AskSource: AskItemInfo] = [:], vectors: [String: [Float]] = [:]
        var meetings = 0, notes = 0, dictations = 0
        let modelID = ProviderFactory.embedder(settings: model.settings.models, credentials: model.credentials)?.modelID ?? ""
        for source in sourcesNewestFirst() {
            let folderID: FolderID?
            switch source {
            case .meeting(let id): folderID = model.meetingManifests.first { $0.id == id }?.folderID
            case .note(let id): folderID = model.notesController.notes.first { $0.id == id }?.frontMatter.folderID
            case .dictations: folderID = nil
            }
            guard scope.includes(source, folderID: folderID) else { continue }
            let current = passages(source)
            all += current
            vectors.merge(await store.vectors(for: current, source: source, model: modelID)) { _, new in new }
            switch source {
            case .meeting(let id):
                guard let meeting = model.meetingManifests.first(where: { $0.id == id }) else { continue }
                var people: [String] = []
                for line in meeting.segments where !people.contains(line.speaker) { people.append(line.speaker) }
                info[source] = AskItemInfo(title: meeting.title, kind: meeting.source == .upload ? .uploaded : .meeting, date: meeting.startedAt, people: people)
                meetings += 1
            case .note(let id):
                guard let note = model.notesController.notes.first(where: { $0.id == id }) else { continue }
                info[source] = AskItemInfo(title: note.title, kind: .note, date: note.modifiedAt, folderName: model.library.folders.first { $0.id == folderID }?.name)
                notes += 1
            case .dictations:
                info[source] = AskItemInfo(title: "Dictation", kind: .dictation, date: model.history.first?.startedAt ?? Date())
                dictations = current.count
            }
        }
        return AskCorpus(passages: all, info: info, vectors: vectors, meetings: meetings, notes: notes, dictations: dictations)
    }
}
