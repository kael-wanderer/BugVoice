import Foundation
import Testing
@testable import VoiceCore

struct InsightsStoreTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("bv-\(UUID().uuidString)/insights.json")
    }

    func historyEntry(_ text: String, on key: String) -> HistoryEntry {
        HistoryEntry(
            id: UUID(), startedAt: insightsDate(key), appName: "Code", bundleID: nil, style: .other,
            language: "en", raw: text, cleaned: nil, text: text, outcome: "inserted", rawReason: nil,
            timings: StageTimings(recording: 2))
    }

    func delta(_ text: String) -> InsightsDelta {
        InsightsDelta.dictation(dictationResult(text), noteID: nil)!
    }

    @Test func missingFileLoadsEmpty() async {
        let store = InsightsStore(url: tempURL())
        let (file, issue) = await store.load()
        #expect(file == InsightsFile())
        #expect(issue == .none)
    }

    @Test func addPersistsAndReloads() async throws {
        let url = tempURL()
        let store = InsightsStore(url: url)
        _ = try await store.add(delta("a b c"), at: insightsDate("2026-10-15"), calendar: insightsCalendar())
        let (file, _) = await InsightsStore(url: url).load()
        #expect(file.days["2026-10-15"]?.words == 3)
    }

    @Test func addFilesUnderGivenDate() async throws {
        let store = InsightsStore(url: tempURL())
        let lateStart = ISO8601DateFormatter().date(from: "2026-10-15T23:59:58Z")!
        let file = try await store.add(delta("late one"), at: lateStart, calendar: insightsCalendar())
        #expect(file.days["2026-10-15"]?.words == 2)
        #expect(file.days["2026-10-16"] == nil)
    }

    @Test func backfillRunsOnce() async throws {
        let store = InsightsStore(url: tempURL())
        let entries = [historyEntry("one two", on: "2026-10-14"), historyEntry("three", on: "2026-10-15")]
        var file = try await store.backfillIfNeeded(from: entries, calendar: insightsCalendar())
        #expect(file.backfilledFromHistory)
        #expect(file.days["2026-10-14"]?.words == 2)
        file = try await store.backfillIfNeeded(from: entries, calendar: insightsCalendar())
        #expect(file.days["2026-10-14"]?.words == 2)
    }

    @Test func resetZeroesAndBlocksBackfill() async throws {
        let store = InsightsStore(url: tempURL())
        _ = try await store.add(delta("a b"), at: insightsDate("2026-10-15"), calendar: insightsCalendar())
        var file = try await store.reset()
        #expect(file.days.isEmpty)
        #expect(file.backfilledFromHistory)
        file = try await store.backfillIfNeeded(from: [historyEntry("x y", on: "2026-10-15")], calendar: insightsCalendar())
        #expect(file.days.isEmpty)
    }

    @Test func corruptFileIsRenamedAndRebuilt() async throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = InsightsStore(url: url)
        let (file, issue) = await store.load(now: Date(timeIntervalSince1970: 1_000))
        #expect(issue == .rebuiltFromCorrupt)
        #expect(file == InsightsFile())
        let backup = url.deletingLastPathComponent().appendingPathComponent("insights.corrupt-1000.json")
        #expect(FileManager.default.fileExists(atPath: backup.path))
        let rebuilt = try await store.backfillIfNeeded(from: [historyEntry("a b", on: "2026-10-15")], calendar: insightsCalendar())
        #expect(rebuilt.days["2026-10-15"]?.words == 2)
    }

    @Test func newerSchemaIsNeverOverwritten() async throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let newer = Data(#"{"schemaVersion": 99, "days": {}}"#.utf8)
        try newer.write(to: url)
        let store = InsightsStore(url: url)
        let (_, issue) = await store.load()
        #expect(issue == .newerVersion)
        await #expect(throws: InsightsStoreError.newerVersion) {
            _ = try await store.add(delta("a"), at: insightsDate("2026-10-15"), calendar: insightsCalendar())
        }
        await #expect(throws: InsightsStoreError.newerVersion) { _ = try await store.reset() }
        #expect(try Data(contentsOf: url) == newer)
    }

    @Test func addWithoutExplicitLoadLoadsFirst() async throws {
        let url = tempURL()
        _ = try await InsightsStore(url: url).add(delta("a b"), at: insightsDate("2026-10-15"), calendar: insightsCalendar())
        let file = try await InsightsStore(url: url).add(delta("c"), at: insightsDate("2026-10-15"), calendar: insightsCalendar())
        #expect(file.days["2026-10-15"]?.words == 3)
    }

    @Test func appPathsInsights() {
        let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/bv"))
        #expect(paths.insights.path == "/tmp/bv/insights.json")
    }
}
