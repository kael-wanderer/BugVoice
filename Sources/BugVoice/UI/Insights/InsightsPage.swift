import SwiftUI
import VoiceCore


struct InsightsPage: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
                Label("Local", systemImage: "desktopcomputer").bvFont(.body).foregroundStyle(.bvSecondary)
                if model.insightsReadOnly {
                    Text("Insights were saved by a newer BugVoice.")
                        .foregroundStyle(.bvSecondary)
                } else {
                    InsightsUsageView(
                        summary: InsightsSummary.compute(file: model.insights, period: model.insightsPeriod, today: Date()),
                        period: model.insightsPeriod
                    )
                }
            }
            .bvPageColumn(.wide)

        }
    }

}
