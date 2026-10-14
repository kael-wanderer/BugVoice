import Foundation
import Testing
@testable import VoiceCore

struct HistoryTests {
    func entry(_ text: String, at date: Date, recording: Double = 6, transcribe: Double = 0.5, clean: Double = 0.3) -> HistoryEntry {
        HistoryEntry(
            id: UUID(), startedAt: date, appName: "Terminal", bundleID: "com.apple.Terminal",
            style: .terminal, language: "en", raw: text, cleaned: nil, text: text,
            outcome: "inserted", rawReason: .cleanupOff,
            timings: StageTimings(recording: recording, transcribe: transcribe, clean: clean, insert: 0.1)
        )
    }

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("bv-\(UUID().uuidString)/history.jsonl")
    }

    @Test func appendLoadNewestFirst() async throws {
        let log = HistoryLog(url: tempURL())
        let a = entry("first", at: Date(timeIntervalSince1970: 100))
        let b = entry("second", at: Date(timeIntervalSince1970: 200))
        try await log.append(a)
        try await log.append(b)
        #expect(await log.load().map(\.text) == ["second", "first"])
    }

    @Test func badLinesAreSkipped() async throws {
        let url = tempURL()
        let log = HistoryLog(url: url)
        try await log.append(entry("ok", at: Date()))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{broken\n".utf8))
        try handle.close()
        #expect(await log.load().map(\.text) == ["ok"])
    }

    @Test func deleteClearPrune() async throws {
        let log = HistoryLog(url: tempURL())
        let old = entry("old", at: Date(timeIntervalSince1970: 0))
        let new = entry("new", at: Date())
        try await log.append(old)
        try await log.append(new)
        try await log.prune(olderThan: Date(timeIntervalSince1970: 1_000))
        #expect(await log.load().map(\.text) == ["new"])
        try await log.delete(id: new.id)
        #expect(await log.load().isEmpty)
        try await log.append(new)
        try await log.clear()
        #expect(await log.load().isEmpty)
    }

    @Test func statsCountTodayOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!   // now = 08:53 UTC, no midnight crossing
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let yesterday = now.addingTimeInterval(-86_400)
        let entries = [
            entry("one two three four five six", at: now, recording: 3, transcribe: 0.4, clean: 0.2),   // 6 words, 3 s
            entry("seven eight nine", at: now.addingTimeInterval(-60), recording: 3, transcribe: 0.8, clean: 0.0), // 3 words
            entry("old words here", at: yesterday),
        ]
        let stats = HistoryStats.compute(entries, now: now, calendar: calendar)
        #expect(stats.wordsToday == 9)
        #expect(stats.dictationsToday == 2)
        #expect(stats.wordsPerMinute == 90)   // 9 words / 6 s
        #expect(stats.medianReleaseToText == 0.8)  // releaseToText 0.7 and 0.9
    }

    @Test func deleteMiddleKeepsOrderOnDisk() async throws {
        let log = HistoryLog(url: tempURL())
        let first = entry("first", at: Date(timeIntervalSince1970: 100))
        let second = entry("second", at: Date(timeIntervalSince1970: 200))
        let third = entry("third", at: Date(timeIntervalSince1970: 300))
        try await log.append(first)
        try await log.append(second)
        try await log.append(third)
        try await log.delete(id: second.id)
        #expect(await log.load() == [third, first])
    }

    @Test func clearOnMissingFileIsNoOp() async throws {
        let log = HistoryLog(url: tempURL())
        try await log.clear()
        #expect(await log.load().isEmpty)
    }

    @Test func clearThrowsWhenFileCannotBeRemoved() async throws {
        let url = tempURL()
        let directory = url.deletingLastPathComponent()
        let log = HistoryLog(url: url)
        try await log.append(entry("kept", at: Date()))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        await #expect(throws: (any Error).self) {
            try await log.clear()
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func encodedKeysUseSpecNames() throws {
        let data = try JSONEncoder().encode(entry("hi", at: Date(timeIntervalSince1970: 0)))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        #expect(object["app"] as? String == "Terminal")
        #expect(object["inserted"] as? String == "hi")
        #expect(object["appName"] == nil)
        #expect(object["text"] == nil)
    }
}
