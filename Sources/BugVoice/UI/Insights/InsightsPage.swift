import SwiftUI
import VoiceCore

enum InsightsTab: Hashable { case usage, details }

struct InsightsPage: View {
    @Bindable var model: AppModel
    @State private var tab: InsightsTab = .usage
    @State private var period: InsightsPeriod = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Insights").font(.title2.weight(.semibold))
                header
                if model.insightsReadOnly {
                    Text("Insights were saved by a newer BugVoice.")
                        .foregroundStyle(.secondary)
                } else {
                    InsightsUsageView(
                        summary: InsightsSummary.compute(file: model.insights, period: period, today: Date()),
                        period: period
                    )
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            PillTabs(
                items: [
                    .init(value: InsightsTab.usage, title: "Usage"),
                    .init(value: InsightsTab.details, title: "Details", badge: "Later", isEnabled: false),
                ],
                selection: $tab
            )
            Spacer()
            PillTabs(
                items: InsightsPeriod.allCases.map { .init(value: $0, title: $0.title) },
                selection: $period,
                size: .small
            )
            Label("Local", systemImage: "desktopcomputer")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
