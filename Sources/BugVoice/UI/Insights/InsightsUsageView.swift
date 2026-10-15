import SwiftUI
import VoiceCore

struct InsightsUsageView: View {
    let summary: InsightsSummary
    let period: InsightsPeriod

    var body: some View {
        Text("\(summary.words) words").font(.title)
    }
}
