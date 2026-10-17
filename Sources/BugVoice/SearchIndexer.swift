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

    init(model: AppModel) {
        self.model = model
        store = SearchIndexStore(folder: model.paths.searchIndex)
    }

    func schedule(_ source: AskSource, after delay: Duration = .zero) {
        revisions[source, default: 0] += 1
        queue[source] = Date().addingTimeInterval(Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18)
        start()
    }

    func backfill() {
        guard let model else { return }
        generation += 1
        for source in sourcesNewestFirst() { schedule(source) }
        if ProviderFactory.embedder(settings: model.settings.models, credentials: model.credentials) == nil { status = .off }
    }

    func remove(_ source: AskSource) async {
        revisions[source, default: 0] += 1
        queue[source] = nil
        try? await store.remove(source)
    }

    func prune(keeping sources: Set<AskSource>) async {
        for source in Array(queue.keys) where !sources.contains(source) {
            revisions[source, default: 0] += 1
            queue[source] = nil
        }
        try? await store.prune(keeping: sources)
    }

    /// Drops deleted history vectors synchronously with the app's reload, without embedding.
    func reconcileHistory() async {
        revisions[.dictations, default: 0] += 1
        guard let old = await store.load(.dictations) else { return }
        let kept = SearchIndexPlanner.update(old, passages: passages(.dictations), model: old.model).keep
        try? await store.save(kept, for: .dictations)
    }

    func listLoaded() async {
        let sources = Set(sourcesNewestFirst())
        await prune(keeping: sources)
        guard let model, let embedder = ProviderFactory.embedder(settings: model.settings.models, credentials: model.credentials) else { return }
        for source in sourcesNewestFirst() {
            let old = await store.load(source)
            let current = passages(source)
            let plan = SearchIndexPlanner.update(old, passages: current, model: embedder.modelID)
            if !plan.missing.isEmpty || plan.keep.entries.count != old?.entries.count {
                // Do not bypass a note's 30-second debounce or the dictation batch delay.
                if queue[source] == nil && (activeSource != source || activePassages != current) { schedule(source) }
            }
        }
        if !queue.isEmpty { start() }
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
                var (file, missing) = SearchIndexPlanner.update(await store.load(source), passages: current, model: embedder.modelID)
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
                if sourcesNewestFirst().contains(source) { try await store.save(file, for: source) }
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
