import Foundation

public enum InsightsPeriod: String, CaseIterable, Sendable, Identifiable {
    case all, days30, days7

    public var id: String { rawValue }

    public var dayCount: Int? {
        switch self {
        case .all: nil
        case .days30: 30
        case .days7: 7
        }
    }

    public var title: String {
        switch self {
        case .all: "All time"
        case .days30: "30 days"
        case .days7: "7 days"
        }
    }

    public var label: String {
        switch self {
        case .all: "All time"
        case .days30: "Last 30 days"
        case .days7: "Last 7 days"
        }
    }
}

/// Fixed thresholds so a colour means the same amount every month.
public enum HeatLevel {
    public static func level(forWords words: Int) -> Int {
        switch words {
        case ..<1: 0
        case 1..<150: 1
        case 150..<300: 2
        case 300..<480: 3
        default: 4
        }
    }
}

public struct HeatCell: Equatable, Sendable, Identifiable {
    public var key: String
    public var date: Date
    /// Dictation and note words.
    public var words: Int
    public var dictations: Int
    public var level: Int
    public var inPeriod: Bool
    public var id: String { key }
}

public struct HeatWeek: Equatable, Sendable, Identifiable {
    public var id: Int
    /// Seven entries, Sunday first; nil for days after today.
    public var days: [HeatCell?]
    /// Short month name on the first week of a month, never on column 0.
    public var monthLabel: String?
}

public struct BreakdownRow: Equatable, Sendable, Identifiable {
    public var name: String
    public var words: Int
    /// Fraction of all words in the period, 0...1.
    public var share: Double
    public var id: String { name }
}

/// Everything the Insights Usage tab shows.
public struct InsightsSummary: Equatable, Sendable {
    public var words = 0
    public var wordsToday = 0
    public var wordsPerMinute = 0
    public var dictations = 0
    public var currentStreak = 0
    public var longestStreak = 0
    public var notes = 0
    public var noteWords = 0
    public var meetings = 0
    public var meetingHours: Double = 0
    public var cleanupFixes = 0
    public var appCount = 0
    public var apps: [BreakdownRow] = []
    public var styles: [BreakdownRow] = []
    public var weeks: [HeatWeek] = []

    public static let weekCount = 52
    public static let topAppCount = 5

    public static func compute(file: InsightsFile, period: InsightsPeriod, today: Date, calendar: Calendar = .current) -> InsightsSummary {
        let start = calendar.startOfDay(for: today)
        func shifted(_ days: Int, from date: Date = start) -> Date {
            calendar.date(byAdding: .day, value: days, to: date) ?? date
        }
        func key(_ date: Date) -> String { InsightsDayKey.key(for: date, calendar: calendar) }

        let periodKeys: Set<String>? = period.dayCount.map { count in Set((0..<count).map { key(shifted(-$0)) }) }
        func inPeriod(_ dayKey: String) -> Bool { periodKeys?.contains(dayKey) ?? true }

        var summary = InsightsSummary()
        var seconds = 0.0
        var meetingSeconds = 0.0
        var apps: [String: Int] = [:]
        var styles: [String: Int] = [:]
        for (dayKey, day) in file.days where inPeriod(dayKey) {
            summary.words += day.words
            summary.dictations += day.dictations
            summary.notes += day.notes
            summary.noteWords += day.noteWords
            summary.meetings += day.meetings
            summary.cleanupFixes += day.cleanupFixes
            seconds += day.secondsSpoken
            meetingSeconds += day.meetingSeconds
            for (app, count) in day.wordsByApp { apps[app, default: 0] += count }
            for (style, count) in day.wordsByStyle { styles[style, default: 0] += count }
        }
        summary.wordsToday = file.days[key(start)]?.words ?? 0
        summary.wordsPerMinute = seconds > 0 ? Int((Double(summary.words + summary.noteWords) / seconds * 60).rounded()) : 0
        summary.meetingHours = (meetingSeconds / 3600 * 10).rounded() / 10

        // Streaks are all-time: the period never changes them.
        func active(_ date: Date) -> Bool { file.days[key(date)]?.hasActivity ?? false }
        var cursor = active(start) ? start : shifted(-1)
        while active(cursor) {
            summary.currentStreak += 1
            cursor = shifted(-1, from: cursor)
        }
        let activeDates = file.days.filter { $0.value.hasActivity }
            .compactMap { InsightsDayKey.date(for: $0.key, calendar: calendar) }
            .sorted()
        var run = 0
        var previous: Date?
        for date in activeDates {
            run = previous.map { shifted(1, from: $0) == date } == true ? run + 1 : 1
            summary.longestStreak = max(summary.longestStreak, run)
            previous = date
        }

        let appTotal = apps.values.reduce(0, +)
        let sortedApps = apps.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        summary.appCount = sortedApps.count
        func share(_ value: Int, of total: Int) -> Double { total > 0 ? Double(value) / Double(total) : 0 }
        summary.apps = sortedApps.prefix(topAppCount).map { BreakdownRow(name: $0.key, words: $0.value, share: share($0.value, of: appTotal)) }
        if sortedApps.count > topAppCount {
            let rest = sortedApps.dropFirst(topAppCount).reduce(0) { $0 + $1.value }
            summary.apps.append(BreakdownRow(name: "Other", words: rest, share: share(rest, of: appTotal)))
        }
        let styleTotal = styles.values.reduce(0, +)
        summary.styles = styles.filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { BreakdownRow(name: $0.key, words: $0.value, share: share($0.value, of: styleTotal)) }

        let weekday = calendar.component(.weekday, from: start)  // 1 = Sunday
        let firstSunday = shifted(-(weekday - 1) - 7 * (weekCount - 1))
        let monthNames = calendar.shortStandaloneMonthSymbols
        var lastMonth: Int?
        for column in 0..<weekCount {
            let weekStart = shifted(column * 7, from: firstSunday)
            var days: [HeatCell?] = []
            for offset in 0..<7 {
                let date = shifted(offset, from: weekStart)
                guard date <= start else { days.append(nil); continue }
                let dayKey = key(date)
                let day = file.days[dayKey]
                let words = (day?.words ?? 0) + (day?.noteWords ?? 0)
                days.append(HeatCell(key: dayKey, date: date, words: words, dictations: day?.dictations ?? 0,
                                     level: HeatLevel.level(forWords: words), inPeriod: inPeriod(dayKey)))
            }
            let month = calendar.component(.month, from: weekStart)
            let label = column > 0 && month != lastMonth ? monthNames[month - 1] : nil
            lastMonth = month
            summary.weeks.append(HeatWeek(id: column, days: days, monthLabel: label))
        }
        return summary
    }
}
