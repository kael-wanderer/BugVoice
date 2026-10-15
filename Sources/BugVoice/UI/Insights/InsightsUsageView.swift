import SwiftUI
import VoiceCore

struct InsightsUsageView: View {
    let summary: InsightsSummary
    let period: InsightsPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatCard(title: "Words spoken", symbol: "mic", value: summary.words.formatted(),
                             subtitle: "\(period.label) · \(summary.wordsToday.formatted()) today")
                    StatCard(title: "Words per minute", symbol: "gauge.with.needle", value: "\(summary.wordsPerMinute)",
                             subtitle: "Words ÷ time speaking")
                    StatCard(title: "Dictations", symbol: "chart.bar", value: summary.dictations.formatted(),
                             subtitle: period.label)
                    StatCard(title: "Current streak", symbol: "flame", value: Self.days(summary.currentStreak),
                             subtitle: "Longest: \(Self.days(summary.longestStreak))")
                }
            }
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatCard(title: "Notes", symbol: "note.text", value: summary.notes.formatted(),
                             subtitle: "\(summary.noteWords.formatted()) words spoken into notes")
                    StatCard(title: "Meetings", symbol: "person.2", value: summary.meetings.formatted(),
                             subtitle: String(format: "%.1f hours recorded", summary.meetingHours))
                    StatCard(title: "Cleanup fixes", symbol: "wand.and.stars", value: summary.cleanupFixes.formatted(),
                             subtitle: "Words changed by the text model")
                }
            }
            ActivityHeatmap(weeks: summary.weeks)
            HStack(alignment: .top, spacing: 12) {
                BreakdownBars(title: "Where you dictate",
                              trailing: summary.appCount == 1 ? "1 app" : "\(summary.appCount) apps",
                              rows: summary.apps) { $0.words.formatted() }
                BreakdownBars(title: "By style",
                              rows: summary.styles.map { BreakdownRow(name: $0.name.capitalized, words: $0.words, share: $0.share) }) {
                    "\(Int(($0.share * 100).rounded()))%"
                }
            }
        }
    }

    static func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }
}
