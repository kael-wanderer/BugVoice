import Foundation
import Testing
@testable import VoiceCore

struct InsightsSummaryTests {
    let calendar = insightsCalendar()
    let today = insightsDate("2026-10-15")  // a Thursday

    func file(_ days: [String: InsightsDay]) -> InsightsFile {
        var file = InsightsFile()
        file.days = days
        return file
    }

    func day(words: Int = 0, dictations: Int = 0, seconds: Double = 0, apps: [String: Int] = [:],
             styles: [String: Int] = [:], noteWords: Int = 0, notes: Int = 0, meetings: Int = 0,
             meetingSeconds: Double = 0, fixes: Int = 0) -> InsightsDay {
        var d = InsightsDay()
        d.words = words; d.dictations = dictations; d.secondsSpoken = seconds
        d.wordsByApp = apps; d.wordsByStyle = styles; d.noteWords = noteWords; d.notes = notes
        d.noteIDs = (0..<notes).map { "n\($0)" }
        d.meetings = meetings; d.meetingSeconds = meetingSeconds; d.cleanupFixes = fixes
        return d
    }

    func compute(_ f: InsightsFile, _ period: InsightsPeriod = .all) -> InsightsSummary {
        InsightsSummary.compute(file: f, period: period, today: today, calendar: calendar)
    }

    @Test func emptyFile() {
        let s = compute(InsightsFile())
        #expect(s.words == 0)
        #expect(s.wordsPerMinute == 0)
        #expect(s.currentStreak == 0)
        #expect(s.apps.isEmpty)
        #expect(s.weeks.count == 52)
    }

    @Test func periodsFilterDays() {
        let f = file([
            "2026-10-15": day(words: 10, dictations: 1),
            "2026-10-09": day(words: 20, dictations: 2),   // 7th day back is 10-09
            "2026-10-08": day(words: 40, dictations: 4),   // outside 7 days
            "2026-09-16": day(words: 80, dictations: 8),   // 30th day back
            "2026-09-15": day(words: 160, dictations: 16), // outside 30 days
        ])
        #expect(compute(f, .all).words == 310)
        #expect(compute(f, .days30).words == 150)
        #expect(compute(f, .days7).words == 30)
        #expect(compute(f, .days7).dictations == 3)
        #expect(compute(f, .all).wordsToday == 10)
    }

    @Test func wordsPerMinuteIncludesNoteWords() {
        let f = file(["2026-10-15": day(words: 90, seconds: 60, noteWords: 30)])
        #expect(compute(f).wordsPerMinute == 120)
    }

    @Test func notesMeetingsFixes() {
        let f = file(["2026-10-15": day(noteWords: 140, notes: 2, meetings: 1, meetingSeconds: 2700, fixes: 9)])
        let s = compute(f)
        #expect(s.notes == 2)
        #expect(s.noteWords == 140)
        #expect(s.meetings == 1)
        #expect(s.meetingHours == 0.8)
        #expect(s.cleanupFixes == 9)
    }

    @Test func streakCountsThroughYesterdayWhenTodayEmpty() {
        let f = file([
            "2026-10-14": day(words: 1), "2026-10-13": day(words: 1), "2026-10-11": day(words: 1),
        ])
        #expect(compute(f).currentStreak == 2)
    }

    @Test func streakIncludesToday() {
        let f = file(["2026-10-15": day(words: 1), "2026-10-14": day(words: 1)])
        #expect(compute(f).currentStreak == 2)
    }

    @Test func streakBreaksAfterAFullEmptyDay() {
        let f = file(["2026-10-13": day(words: 1)])
        #expect(compute(f).currentStreak == 0)
    }

    @Test func meetingOnlyDayKeepsStreak() {
        let f = file(["2026-10-15": day(meetings: 1, meetingSeconds: 60), "2026-10-14": day(words: 3)])
        #expect(compute(f).currentStreak == 2)
    }

    @Test func longestStreakAndPeriodDoesNotChangeStreak() {
        let f = file([
            "2026-08-01": day(words: 1), "2026-08-02": day(words: 1), "2026-08-03": day(words: 1),
            "2026-10-15": day(words: 1),
        ])
        #expect(compute(f).longestStreak == 3)
        #expect(compute(f, .days7).longestStreak == 3)
        #expect(compute(f, .days7).currentStreak == 1)
    }

    @Test func gridIs52WeeksSundayFirstEndingToday() throws {
        let s = compute(InsightsFile())
        let first = try #require(s.weeks.first?.days.first ?? nil)
        #expect(calendar.component(.weekday, from: first.date) == 1)
        let last = try #require(s.weeks.last)
        // Thursday is weekday 5: index 4 is today, 5 and 6 are in the future.
        #expect(last.days[4]?.key == "2026-10-15")
        #expect(last.days[5] == nil)
        #expect(last.days[6] == nil)
        #expect(s.weeks.allSatisfy { $0.days.count == 7 })
    }

    @Test func gridCellsCarryWordsLevelAndPeriod() throws {
        let f = file(["2026-10-15": day(words: 300, dictations: 12), "2026-10-01": day(words: 10)])
        let s = compute(f, .days7)
        let cells = s.weeks.flatMap { $0.days.compactMap { $0 } }
        let todayCell = try #require(cells.first { $0.key == "2026-10-15" })
        #expect(todayCell.words == 300)
        #expect(todayCell.dictations == 12)
        #expect(todayCell.level == 3)
        #expect(todayCell.inPeriod)
        let old = try #require(cells.first { $0.key == "2026-10-01" })
        #expect(!old.inPeriod)
        #expect(cells.allSatisfy { $0.inPeriod } == false)
        #expect(compute(f, .all).weeks.flatMap { $0.days.compactMap { $0 } }.allSatisfy { $0.inPeriod })
    }

    @Test func gridCountsNoteWords() throws {
        let f = file(["2026-10-15": day(words: 100, noteWords: 60)])
        let cell = try #require(compute(f).weeks.last?.days[4] ?? nil)
        #expect(cell.words == 160)
        #expect(cell.level == 2)
    }

    @Test func monthLabelsOnFirstWeekOfEachMonthExceptColumnZero() {
        let s = compute(InsightsFile())
        #expect(s.weeks[0].monthLabel == nil)
        let labels = s.weeks.compactMap(\.monthLabel)
        #expect(labels.last == "Oct")
        #expect(labels.count >= 11 && labels.count <= 12)
    }

    @Test func topFiveAppsPlusOther() {
        let apps = ["A": 60, "B": 50, "C": 40, "D": 30, "E": 20, "F": 10, "G": 5]
        let s = compute(file(["2026-10-15": day(words: 215, apps: apps)]))
        #expect(s.appCount == 7)
        #expect(s.apps.map(\.name) == ["A", "B", "C", "D", "E", "Other"])
        #expect(s.apps.last?.words == 15)
        #expect(abs(s.apps.reduce(0) { $0 + $1.share } - 1) < 0.0001)
    }

    @Test func appTiesSortByName() {
        let s = compute(file(["2026-10-15": day(words: 20, apps: ["Notion": 10, "Code": 10])]))
        #expect(s.apps.map(\.name) == ["Code", "Notion"])
    }

    @Test func noOtherRowWithFiveOrFewerApps() {
        let s = compute(file(["2026-10-15": day(words: 3, apps: ["A": 1, "B": 2])]))
        #expect(s.apps.map(\.name) == ["B", "A"])
    }

    @Test func styleShares() {
        let s = compute(file(["2026-10-15": day(words: 100, styles: ["terminal": 50, "other": 30, "document": 20])]))
        #expect(s.styles.map(\.name) == ["terminal", "other", "document"])
        #expect(s.styles.first?.share == 0.5)
        #expect(abs(s.styles.reduce(0) { $0 + $1.share } - 1) < 0.0001)
    }

    @Test func heatLevelBoundaries() {
        #expect(HeatLevel.level(forWords: 0) == 0)
        #expect(HeatLevel.level(forWords: 1) == 1)
        #expect(HeatLevel.level(forWords: 149) == 1)
        #expect(HeatLevel.level(forWords: 150) == 2)
        #expect(HeatLevel.level(forWords: 299) == 2)
        #expect(HeatLevel.level(forWords: 300) == 3)
        #expect(HeatLevel.level(forWords: 479) == 3)
        #expect(HeatLevel.level(forWords: 480) == 4)
    }

    @Test func periodTitles() {
        #expect(InsightsPeriod.allCases.map(\.title) == ["All time", "30 days", "7 days"])
        #expect(InsightsPeriod.days30.label == "Last 30 days")
    }
}
