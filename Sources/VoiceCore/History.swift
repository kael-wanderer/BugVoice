import Foundation

public struct StageTimings: Codable, Equatable, Sendable {
    public var recording: Double
    public var transcribe: Double
    public var clean: Double
    public var insert: Double

    public init(recording: Double = 0, transcribe: Double = 0, clean: Double = 0, insert: Double = 0) {
        self.recording = recording
        self.transcribe = transcribe
        self.clean = clean
        self.insert = insert
    }

    /// From key release to text in place.
    public var releaseToText: Double { transcribe + clean + insert }
}

public struct HistoryEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var appName: String?
    public var bundleID: String?
    public var style: Style
    public var language: String?
    public var raw: String
    public var cleaned: String?
    public var text: String
    public var outcome: String
    public var rawReason: RawReason?
    public var timings: StageTimings

    /// On disk, `appName` is `app` and `text` is `inserted` (spec history.jsonl keys).
    enum CodingKeys: String, CodingKey {
        case id, startedAt, bundleID, style, language, raw, cleaned, outcome, rawReason, timings
        case appName = "app"
        case text = "inserted"
    }

    public init(
        id: UUID, startedAt: Date, appName: String?, bundleID: String?, style: Style,
        language: String?, raw: String, cleaned: String?, text: String, outcome: String,
        rawReason: RawReason?, timings: StageTimings
    ) {
        self.id = id
        self.startedAt = startedAt
        self.appName = appName
        self.bundleID = bundleID
        self.style = style
        self.language = language
        self.raw = raw
        self.cleaned = cleaned
        self.text = text
        self.outcome = outcome
        self.rawReason = rawReason
        self.timings = timings
    }

    public var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

/// Append-only JSONL file, one entry per line, oldest first on disk.
public actor HistoryLog {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func append(_ entry: HistoryEntry) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var line = try Self.makeEncoder().encode(entry)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url, options: .atomic)
        }
    }

    /// Newest first. Lines that do not decode are skipped, not fatal.
    public func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = Self.makeDecoder()
        return data.split(separator: 0x0A)
            .compactMap { try? decoder.decode(HistoryEntry.self, from: Data($0)) }
            .reversed()
    }

    public func delete(id: UUID) throws {
        try rewrite(load().filter { $0.id != id })
    }

    /// Clearing a missing file is a no-op. Any other failure is thrown, so the UI never reports history gone when it is not.
    public func clear() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func prune(olderThan cutoff: Date) throws {
        try rewrite(load().filter { $0.startedAt >= cutoff })
    }

    /// Takes newest-first input and writes it back oldest-first, matching `append`.
    private func rewrite(_ newestFirst: [HistoryEntry]) throws {
        let encoder = Self.makeEncoder()
        var data = Data()
        for entry in newestFirst.reversed() {
            data.append(try encoder.encode(entry))
            data.append(0x0A)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

public struct HistoryStats: Equatable, Sendable {
    public var wordsToday: Int
    public var dictationsToday: Int
    public var wordsPerMinute: Int
    public var medianReleaseToText: Double?

    public static func compute(_ entries: [HistoryEntry], now: Date, calendar: Calendar = .current) -> HistoryStats {
        let today = entries.filter { calendar.isDate($0.startedAt, inSameDayAs: now) }
        let words = today.reduce(0) { $0 + $1.wordCount }
        let seconds = today.reduce(0.0) { $0 + $1.timings.recording }
        let wpm = seconds > 0 ? Int((Double(words) / seconds * 60).rounded()) : 0
        let latencies = today.map(\.timings.releaseToText).sorted()
        let median: Double? = latencies.isEmpty ? nil : latencies.count % 2 == 1
            ? latencies[latencies.count / 2]
            : (latencies[latencies.count / 2 - 1] + latencies[latencies.count / 2]) / 2
        return HistoryStats(
            wordsToday: words,
            dictationsToday: today.count,
            wordsPerMinute: wpm,
            medianReleaseToText: median.map { ($0 * 100).rounded() / 100 }
        )
    }
}
