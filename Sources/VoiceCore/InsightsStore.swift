import Foundation

public enum InsightsLoadIssue: Equatable, Sendable {
    case none
    /// The file could not be read; it was renamed aside and Insights starts
    /// empty, to be refilled from history.
    case rebuiltFromCorrupt
    /// Written by a newer BugVoice; left untouched and never written.
    case newerVersion
}

public enum InsightsStoreError: Error, Equatable {
    case newerVersion
}

/// Owns `insights.json`. Every write replaces the file atomically.
public actor InsightsStore {
    public let url: URL
    private var file = InsightsFile()
    private var loaded = false
    private var readOnly = false

    public init(url: URL) {
        self.url = url
    }

    @discardableResult
    public func load(now: Date = Date()) -> (InsightsFile, InsightsLoadIssue) {
        loaded = true
        readOnly = false
        file = InsightsFile()
        guard FileManager.default.fileExists(atPath: url.path) else { return (file, .none) }
        struct Header: Decodable { var schemaVersion: Int? }
        if let data = try? Data(contentsOf: url) {
            if let version = (try? JSONDecoder().decode(Header.self, from: data))?.schemaVersion,
               version > InsightsFile.supportedSchemaVersion {
                readOnly = true
                return (file, .newerVersion)
            }
            if let decoded = try? JSONDecoder().decode(InsightsFile.self, from: data) {
                file = decoded
                return (file, .none)
            }
        }
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("insights.corrupt-\(Int(now.timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: backup)
        return (file, .rebuiltFromCorrupt)
    }

    public func add(_ delta: InsightsDelta, at date: Date, calendar: Calendar = .current) throws -> InsightsFile {
        try ensureWritable()
        var next = file
        next.add(delta, at: date, calendar: calendar)
        try commit(next)
        return file
    }

    /// Adds every history entry once. Later calls return the file unchanged.
    public func backfillIfNeeded(from entries: [HistoryEntry], calendar: Calendar = .current) throws -> InsightsFile {
        try ensureWritable()
        guard !file.backfilledFromHistory else { return file }
        var next = file
        for entry in entries {
            if let delta = InsightsDelta.history(entry) { next.add(delta, at: entry.startedAt, calendar: calendar) }
        }
        next.backfilledFromHistory = true
        try commit(next)
        return file
    }

    /// Back to zero. Marks the backfill as done so history does not refill it.
    public func reset() throws -> InsightsFile {
        try ensureWritable()
        var next = InsightsFile()
        next.backfilledFromHistory = true
        try commit(next)
        return file
    }

    private func ensureWritable() throws {
        if !loaded { load() }
        if readOnly { throw InsightsStoreError.newerVersion }
    }

    private func commit(_ next: InsightsFile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(next).write(to: url, options: .atomic)
        file = next
    }
}
