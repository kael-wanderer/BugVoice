import SwiftUI
import VoiceCore

enum InsightsTab: Hashable { case usage, details }

struct InsightsPage: View {
    @Bindable var model: AppModel
    @State private var tab: InsightsTab = .usage
    @State private var period: InsightsPeriod = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
                Text("Insights").bvFont(.title2)
                header
                if model.insightsReadOnly {
                    Text("Insights were saved by a newer BugVoice.")
                        .foregroundStyle(.bvSecondary)
                } else {
                    InsightsUsageView(
                        summary: InsightsSummary.compute(file: model.insights, period: period, today: Date()),
                        period: period
                    )
                }
            }
            .padding(LayoutTokens.spacing[4])
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: LayoutTokens.spacing[2]) {
                tabs
                Spacer()
                periods
            }
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                tabs
                periods
            }
        }
    }

    private var tabs: some View {
        PillTabs(
            items: [
                .init(value: InsightsTab.usage, title: "Usage"),
                .init(value: InsightsTab.details, title: "Details", badge: "Later", isEnabled: false),
            ],
            selection: $tab
        )
    }

    private var periods: some View {
        HStack(spacing: LayoutTokens.spacing[2]) {
            PillTabs(
                items: InsightsPeriod.allCases.map { .init(value: $0, title: $0.title) },
                selection: $period,
                size: .small
            )
            Label("Local", systemImage: "desktopcomputer")
                .bvFont(.body)
                .foregroundStyle(.bvSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
