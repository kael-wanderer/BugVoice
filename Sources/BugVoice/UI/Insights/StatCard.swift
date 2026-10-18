import AppKit
import SwiftUI
import VoiceCore

extension View {
    /// Rounded panel used by every Insights card.
    func insightsCard() -> some View {
        padding(LayoutTokens.spacing[3])
            .frame(maxWidth: .infinity, alignment: .leading)
            .bvCard()
    }
}

struct StatCard: View {
    @Environment(AppearanceStore.self) private var store
    let title: String
    let symbol: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
            Label(title, systemImage: symbol)
                .bvFont(.body)
                .lineLimit(1)
                .foregroundStyle(.bvSecondary)
            Text(value)
                .bvFont(.stat)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(subtitle)
                .bvFont(.footnote)
                .foregroundStyle(.bvSecondary)
                .lineLimit(2)
        }
        .padding(LayoutTokens.spacing[3])
        // Fills the row height `CardGrid` gives it, so cards in a row match.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .bvCard()
    }
}
