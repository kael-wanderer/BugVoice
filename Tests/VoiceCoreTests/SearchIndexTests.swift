import Foundation
import Testing

@testable import VoiceCore

@Suite("SearchIndex")
struct SearchIndexTests {
    private func tempFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SearchIndexTests-\(UUID().uuidString)")
            .appendingPathComponent("SearchIndex")
    }

    private func passage(_ source: AskSource, _ index: Int, _ text: String) -> AskPassage {
        AskPassage(
            source: source, part: .note, index: index, date: Date(timeIntervalSince1970: 0),
            lines: [AskLine(id: "b\(index).0", text: text)])
    }

    private func file(for passages: [AskPassage], model: String = "m1") -> SearchIndexFile {
        SearchIndexFile(
            model: model, dimensions: 3,
            entries: passages.map { .init(passageID: $0.id, contentHash: $0.contentHash) },
            vectors: passages.enumerated().map { [Float($0.offset), 0.5, -0.25] })
    }

    private let source = AskSource.note(NoteID(rawValue: "n1"))

    @Test func fileRoundTrips() throws {
        let ps = [passage(source, 0, "a"), passage(source, 1, "b")]
        var f = file(for: ps)
        f.vectors = [[0.1, -0.2, 0.3], [1.5, 0, -2]]
        let back = try SearchIndexFile.decode(f.encoded())
        #expect(back.model == "m1" && back.dimensions == 3 && back.entries == f.entries)
        for (a, b) in zip(back.vectors, f.vectors) {
            for (x, y) in zip(a, b) { #expect(abs(x - y) < 1e-3) }
        }
    }

    @Test func decodeRejectsBadData() throws {
        let data = try file(for: [passage(source, 0, "a")]).encoded()
        #expect(throws: (any Error).self) { try SearchIndexFile.decode(data.dropLast()) }
        #expect(throws: (any Error).self) { try SearchIndexFile.decode(data + Data([0, 0])) }
        #expect(throws: (any Error).self) { try SearchIndexFile.decode(Data([1, 2])) }
        #expect(throws: (any Error).self) { try SearchIndexFile.decode(Data([2, 0, 0, 0, 0x7b, 0x7d])) }
    }

    @Test func permissions() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let store = SearchIndexStore(folder: folder)
        try await store.save(file(for: [passage(source, 0, "a")]), for: source)
        let fm = FileManager.default
        let dir = try fm.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int
        let path = folder.appendingPathComponent(SearchIndexStore.fileName(for: source)).path
        let mode = try fm.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(dir == 0o700)
        #expect(mode == 0o600)
    }

    @Test func fileNames() {
        #expect(SearchIndexStore.fileName(for: .note(NoteID(rawValue: "n1"))) == "note-n1.idx")
        #expect(SearchIndexStore.fileName(for: .meeting(MeetingID(rawValue: "m1"))) == "meeting-m1.idx")
        #expect(SearchIndexStore.fileName(for: .dictations) == "dictations.idx")
    }

    @Test func unsafeIDIsNoFile() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let store = SearchIndexStore(folder: folder)
        let bad = AskSource.note(NoteID(rawValue: "../x"))
        await #expect(throws: (any Error).self) {
            try await store.save(file(for: []), for: bad)
        }
        #expect(await store.load(bad) == nil)
    }

    @Test func staleOnModelChange() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let store = SearchIndexStore(folder: folder)
        let ps = [passage(source, 0, "a")]
        try await store.save(file(for: ps), for: source)
        #expect(await store.vectors(for: ps, source: source, model: "m1").count == 1)
        #expect(await store.vectors(for: ps, source: source, model: "m2").isEmpty)
    }

    @Test func hashMismatchHasNoVector() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let store = SearchIndexStore(folder: folder)
        try await store.save(file(for: [passage(source, 0, "a")]), for: source)
        let changed = [passage(source, 0, "changed")]
        #expect(await store.vectors(for: changed, source: source, model: "m1").isEmpty)
    }

    @Test func plannerReusesUnchanged() {
        let a = passage(source, 0, "a"), b = passage(source, 1, "b")
        let old = file(for: [a, b])
        let (keep, missing) = SearchIndexPlanner.update(old, passages: [a, passage(source, 1, "b2")], model: "m1")
        #expect(keep.entries.map(\.passageID) == [a.id])
        #expect(keep.vectors == [old.vectors[0]])
        #expect(missing.map(\.id) == [b.id])
        #expect(keep.model == "m1" && keep.dimensions == 3)
    }

    @Test func plannerDropsRemovedPassages() {
        let a = passage(source, 0, "a"), b = passage(source, 1, "b")
        let (keep, missing) = SearchIndexPlanner.update(file(for: [a, b]), passages: [b], model: "m1")
        #expect(keep.entries.map(\.passageID) == [b.id])
        #expect(missing.isEmpty)
    }

    @Test func plannerModelChangeAndNil() {
        let a = passage(source, 0, "a")
        let (k1, m1) = SearchIndexPlanner.update(file(for: [a]), passages: [a], model: "m2")
        #expect(k1.entries.isEmpty && k1.dimensions == 0 && k1.model == "m2" && m1.count == 1)
        let (k2, m2) = SearchIndexPlanner.update(nil, passages: [a], model: "m2")
        #expect(k2.entries.isEmpty && m2.count == 1)
    }

    @Test func pruneRemovesOthers() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let store = SearchIndexStore(folder: folder)
        let other = AskSource.meeting(MeetingID(rawValue: "m1"))
        try await store.save(file(for: []), for: source)
        try await store.save(file(for: []), for: other)
        try await store.save(file(for: []), for: .dictations)
        try Data().write(to: folder.appendingPathComponent("keep.txt"))
        try await store.prune(keeping: [source])
        #expect(await store.load(source) != nil)
        #expect(await store.load(other) == nil)
        #expect(await store.load(.dictations) == nil)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("keep.txt").path))
    }

    @Test func removeDeletesFile() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let store = SearchIndexStore(folder: folder)
        try await store.save(file(for: []), for: source)
        try await store.remove(source)
        #expect(await store.load(source) == nil)
        try await store.remove(source)
    }

    @Test func corruptFileLoadsNil() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let store = SearchIndexStore(folder: folder)
        try await store.save(file(for: []), for: source)
        try Data([9, 9, 9]).write(to: folder.appendingPathComponent(SearchIndexStore.fileName(for: source)))
        #expect(await store.load(source) == nil)
    }

    @Test func saveIsAtomic() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let store = SearchIndexStore(folder: folder)
        let ps = [passage(source, 0, "a")]
        try await store.save(file(for: ps), for: source)
        try await store.save(file(for: ps), for: source)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names == ["note-n1.idx"])
    }

    // MARK: Summaries (header only, no vectors)

    @Test func summaryReadsHeaderWithoutVectors() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let store = SearchIndexStore(folder: folder)
        let f = file(for: [passage(source, 0, "a"), passage(source, 1, "b")])
        try await store.save(f, for: source)
        let summary = try #require(await store.summary(source))
        #expect(summary == SearchIndexSummary(model: "m1", dimensions: 3, entries: f.entries))
        #expect(SearchIndexSummary(f) == summary)
        #expect(await store.summary(.dictations) == nil)
    }

    @Test func summaryRejectsTruncatedOrCorruptFile() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let store = SearchIndexStore(folder: folder)
        let data = try file(for: [passage(source, 0, "a")]).encoded()
        let url = folder.appendingPathComponent(SearchIndexStore.fileName(for: source))
        try await store.save(file(for: []), for: source)
        try data.dropLast().write(to: url)
        #expect(await store.summary(source) == nil)
        try Data([9, 9, 9]).write(to: url)
        #expect(await store.summary(source) == nil)
    }

    // MARK: Work decisions

    @Test func needsWorkIsFalseWhenEveryPassageMatches() {
        let a = passage(source, 0, "a"), b = passage(source, 1, "b")
        let summary = SearchIndexSummary(file(for: [a, b]))
        #expect(!SearchIndexPlanner.needsWork(summary, passages: [a, b], model: "m1"))
    }

    @Test func needsWorkForChangedAddedOrRemovedPassages() {
        let a = passage(source, 0, "a"), b = passage(source, 1, "b")
        let summary = SearchIndexSummary(file(for: [a, b]))
        #expect(SearchIndexPlanner.needsWork(summary, passages: [a, passage(source, 1, "b2")], model: "m1"))
        #expect(SearchIndexPlanner.needsWork(summary, passages: [a, b, passage(source, 2, "c")], model: "m1"))
        #expect(SearchIndexPlanner.needsWork(summary, passages: [a], model: "m1"))
        #expect(SearchIndexPlanner.needsWork(summary, passages: [], model: "m1"))
    }

    @Test func needsWorkForModelChangeOrMissingFile() {
        let a = passage(source, 0, "a")
        #expect(SearchIndexPlanner.needsWork(SearchIndexSummary(file(for: [a])), passages: [a], model: "m2"))
        #expect(SearchIndexPlanner.needsWork(nil, passages: [a], model: "m1"))
    }

    @Test func nothingToDoForAnEmptyItemWithoutAFile() {
        #expect(!SearchIndexPlanner.needsWork(nil, passages: [], model: "m1"))
        #expect(!SearchIndexPlanner.needsWork(SearchIndexSummary(file(for: [])), passages: [], model: "m1"))
    }

    @Test func needsSaveSkipsAnUnchangedFile() {
        let a = passage(source, 0, "a"), b = passage(source, 1, "b")
        let old = file(for: [a, b])
        let (kept, missing) = SearchIndexPlanner.update(old, passages: [a, b], model: "m1")
        #expect(missing.isEmpty)
        #expect(!SearchIndexPlanner.needsSave(old: old, updated: kept))
        #expect(!SearchIndexPlanner.needsSave(old: nil, updated: SearchIndexFile(model: "m1", dimensions: 0, entries: [], vectors: [])))
    }

    @Test func needsSaveWhenEntriesWereDroppedOrAdded() {
        let a = passage(source, 0, "a"), b = passage(source, 1, "b")
        let old = file(for: [a, b])
        let (kept, _) = SearchIndexPlanner.update(old, passages: [a], model: "m1")
        #expect(SearchIndexPlanner.needsSave(old: old, updated: kept))
        #expect(SearchIndexPlanner.needsSave(old: nil, updated: file(for: [a])))
    }

    // MARK: Per-kind prune

    @Test func pruneOfOneKindLeavesOtherKinds() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let store = SearchIndexStore(folder: folder)
        let otherNote = AskSource.note(NoteID(rawValue: "n2"))
        let meeting = AskSource.meeting(MeetingID(rawValue: "m1"))
        for s in [source, otherNote, meeting, AskSource.dictations] { try await store.save(file(for: []), for: s) }
        // Notes loaded before meetings and history: only note files are pruned.
        try await store.prune(keeping: [source], kinds: [.note])
        #expect(await store.load(source) != nil)
        #expect(await store.load(otherNote) == nil)
        #expect(await store.load(meeting) != nil)
        #expect(await store.load(.dictations) != nil)
        try await store.prune(keeping: [], kinds: [.meeting])
        #expect(await store.load(meeting) == nil)
        #expect(await store.load(.dictations) != nil)
        try await store.prune(keeping: [], kinds: [.dictations])
        #expect(await store.load(.dictations) == nil)
        #expect(await store.load(source) != nil)
    }

    @Test func sourceKinds() {
        #expect(AskSource.note(NoteID(rawValue: "n")).kind == .note)
        #expect(AskSource.meeting(MeetingID(rawValue: "m")).kind == .meeting)
        #expect(AskSource.dictations.kind == .dictations)
    }

    // MARK: Schedule deadlines

    @Test func debounceMovesTheDeadline() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(SearchIndexPlanner.deadline(existing: now, proposed: now + 30, extend: true) == now + 30)
    }

    @Test func batchDelayKeepsAnEarlierPendingDeadline() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(SearchIndexPlanner.deadline(existing: now + 60, proposed: now + 600, extend: false) == now + 60)
        #expect(SearchIndexPlanner.deadline(existing: nil, proposed: now + 600, extend: false) == now + 600)
        #expect(SearchIndexPlanner.deadline(existing: now + 900, proposed: now + 600, extend: false) == now + 600)
    }
}
