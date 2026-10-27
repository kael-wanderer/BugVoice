import Foundation

/// One day's activity. Numbers, app and style names and note IDs only:
/// never dictated text.
public struct InsightsDay: Codable, Equatable, Sendable {
    public var words = 0
    public var dictations = 0
    public var secondsSpoken: Double = 0
    public var notes = 0
    public var noteIDs: [String] = []
    public var noteWords = 0
    public var meetings = 0
    public var meetingSeconds: Double = 0
    public var wordsByApp: [String: Int] = [:]
    public var wordsByStyle: [String: Int] = [:]
    public var cleanupFixes = 0

    public init() {}

    /// Missing keys decode as zero, so later versions can add fields.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        words = try c.decodeIfPresent(Int.self, forKey: .words) ?? 0
        dictations = try c.decodeIfPresent(Int.self, forKey: .dictations) ?? 0
        secondsSpoken = try c.decodeIfPresent(Double.self, forKey: .secondsSpoken) ?? 0
        notes = try c.decodeIfPresent(Int.self, forKey: .notes) ?? 0
        noteIDs = try c.decodeIfPresent([String].self, forKey: .noteIDs) ?? []
        noteWords = try c.decodeIfPresent(Int.self, forKey: .noteWords) ?? 0
        meetings = try c.decodeIfPresent(Int.self, forKey: .meetings) ?? 0
        meetingSeconds = try c.decodeIfPresent(Double.self, forKey: .meetingSeconds) ?? 0
        wordsByApp = try c.decodeIfPresent([String: Int].self, forKey: .wordsByApp) ?? [:]
        wordsByStyle = try c.decodeIfPresent([String: Int].self, forKey: .wordsByStyle) ?? [:]
        cleanupFixes = try c.decodeIfPresent(Int.self, forKey: .cleanupFixes) ?? 0
    }

    /// A day counts toward a streak when anything was spoken or recorded.
    public var hasActivity: Bool { words > 0 || noteWords > 0 || notes > 0 || meetings > 0 }

    public mutating func merge(_ other: InsightsDay) {
        words += other.words
        dictations += other.dictations
        secondsSpoken += other.secondsSpoken
        noteWords += other.noteWords
        meetings += other.meetings
        meetingSeconds += other.meetingSeconds
        cleanupFixes += other.cleanupFixes
        for (app, count) in other.wordsByApp { wordsByApp[app, default: 0] += count }
        for (style, count) in other.wordsByStyle { wordsByStyle[style, default: 0] += count }
        for id in other.noteIDs where !noteIDs.contains(id) { noteIDs.append(id) }
        notes = noteIDs.count
    }
}

/// `insights.json`.
public struct InsightsFile: Codable, Equatable, Sendable {
    public static let supportedSchemaVersion = 1

    public var schemaVersion = InsightsFile.supportedSchemaVersion
    public var backfilledFromHistory = false
    /// Keyed by local day, `yyyy-MM-dd`.
    public var days: [String: InsightsDay] = [:]

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.supportedSchemaVersion
        backfilledFromHistory = try c.decodeIfPresent(Bool.self, forKey: .backfilledFromHistory) ?? false
        days = try c.decodeIfPresent([String: InsightsDay].self, forKey: .days) ?? [:]
    }

    public mutating func add(_ delta: InsightsDelta, at date: Date, calendar: Calendar) {
        days[InsightsDayKey.key(for: date, calendar: calendar), default: InsightsDay()].merge(delta.day)
    }
}

public enum InsightsDayKey {
    public static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Midnight of that day in `calendar`'s time zone; nil for a malformed key.
    public static func date(for key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// What one event adds to its day.
public struct InsightsDelta: Equatable, Sendable {
    public var day: InsightsDay

    public init(day: InsightsDay) {
        self.day = day
    }

    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Nil when nothing counts: secure fields, failures, empty text.
    public static func dictation(_ result: DictationResult, noteID: NoteID?) -> InsightsDelta? {
        guard result.command == nil else { return nil }
        return spoken(outcome: result.outcome, appName: result.appName, style: result.style, raw: result.raw,
               cleaned: result.cleaned, text: result.finalText, seconds: result.timings.recording, noteID: noteID)
    }

    public static func history(_ entry: HistoryEntry) -> InsightsDelta? {
        guard entry.command == nil else { return nil }
        guard let outcome = DictationOutcome(rawValue: entry.outcome) else { return nil }
        return spoken(outcome: outcome, appName: entry.appName, style: entry.style, raw: entry.raw,
                      cleaned: entry.cleaned, text: entry.text, seconds: entry.timings.recording, noteID: nil)
    }

    public static func meeting(seconds: TimeInterval) -> InsightsDelta? {
        guard seconds > 0 else { return nil }
        var day = InsightsDay()
        day.meetings = 1
        day.meetingSeconds = seconds
        return InsightsDelta(day: day)
    }

    private static func spoken(
        outcome: DictationOutcome, appName: String?, style: Style, raw: String, cleaned: String?,
        text: String, seconds: Double, noteID: NoteID?
    ) -> InsightsDelta? {
        let words = wordCount(text)
        guard words > 0 else { return nil }
        var day = InsightsDay()
        switch outcome {
        case .inserted, .copiedNotConsumed, .copiedFocusChanged:
            let app = appName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
            day.words = words
            day.wordsByApp[app] = words
            day.wordsByStyle[style.rawValue] = words
        case .insertedInNote:
            day.noteWords = words
            if let noteID {
                day.noteIDs = [noteID.rawValue]
                day.notes = 1
            }
        case .copiedSecureField, .discardedTooShort, .nothingHeard, .transcriptionFailed, .cancelled, .noteDeleted, .noteSaveFailed:
            return nil
        }
        day.dictations = 1
        day.secondsSpoken = max(0, seconds)
        day.cleanupFixes = cleaned.map { WordErrorRate.editDistance(reference: raw, hypothesis: $0) } ?? 0
        return InsightsDelta(day: day)
    }
}
