import SwiftUI
import VoiceCore

struct InsightsUsageView: View {
    @Environment(AppearanceStore.self) private var store
    let summary: InsightsSummary
    let period: InsightsPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            CardGrid(minCardWidth: store.scaled(170), spacing: LayoutTokens.spacing[2]) {
                StatCard(title: "Words spoken", symbol: "mic", value: summary.words.formatted(),
                         subtitle: "\(period.label) · \(summary.wordsToday.formatted()) today")
                StatCard(title: "Words per minute", symbol: "gauge.with.needle", value: "\(summary.wordsPerMinute)",
                         subtitle: "Words ÷ time speaking")
                StatCard(title: "Dictations", symbol: "chart.bar", value: summary.dictations.formatted(),
                         subtitle: period.label)
                StatCard(title: "Current streak", symbol: "flame", value: Self.days(summary.currentStreak),
                         subtitle: "Longest: \(Self.days(summary.longestStreak))")
                StatCard(title: "Time saved", symbol: "clock", value: Self.duration(minutes: summary.minutesSaved),
                         subtitle: "Compared with typing at \(Int(InsightsSummary.typingWordsPerMinute)) words per minute")
                StatCard(title: "Notes", symbol: "note.text", value: summary.notes.formatted(),
                         subtitle: "\(summary.noteWords.formatted()) words spoken into notes")
                StatCard(title: "Meetings", symbol: "person.2", value: summary.meetings.formatted(),
                         subtitle: String(format: "%.1f hours recorded", summary.meetingHours))
                StatCard(title: "Cleanup fixes", symbol: "wand.and.stars", value: summary.cleanupFixes.formatted(),
                         subtitle: "Words changed by the text model")
            }
            ActivityHeatmap(weeks: summary.weeks)
            HStack(alignment: .top, spacing: LayoutTokens.spacing[2]) {
                BreakdownBars(title: "Where you dictate",
                              trailing: summary.appCount == 1 ? "1 app" : "\(summary.appCount) apps",
                              rows: summary.apps) { $0.words.formatted() }
                BreakdownBars(title: "By style",
                              rows: summary.styles.map {
                                  BreakdownRow(name: Style(rawValue: $0.name)?.title ?? "Chat (old)", words: $0.words, share: $0.share)
                              }) {
                    "\(Int(($0.share * 100).rounded()))%"
                }
            }
        }
    }

    /// "45 min", "3 h 20 min", "12 h".
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    static func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }
}
