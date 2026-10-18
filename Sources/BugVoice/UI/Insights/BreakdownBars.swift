import SwiftUI
import VoiceCore

struct BreakdownBars: View {
    @Environment(AppearanceStore.self) private var store
    let title: String
    var trailing: String? = nil
    let rows: [BreakdownRow]
    /// The text on the right of each bar.
    let value: (BreakdownRow) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            HStack {
                Text(title).bvFont(.bodyStrong)
                Spacer()
                if let trailing { Text(trailing).bvFont(.footnote).foregroundStyle(.bvSecondary) }
            }
            if rows.isEmpty {
                Text("No dictation in this period.").bvFont(.body).foregroundStyle(.bvSecondary)
            } else {
                let top = rows.map(\.share).max() ?? 1
                ForEach(rows) { row in
                    HStack(spacing: LayoutTokens.spacing[1]) {
                        Text(row.name).lineLimit(1).frame(width: store.scaled(90), alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(store.theme.text.opacity(0.07))
                                Capsule().fill(store.theme.accent)
                                    .frame(width: top > 0 ? proxy.size.width * row.share / top : 0)
                            }
                        }
                        .frame(height: 8)
                        Text(value(row))
                            .bvFont(.footnote)
                            .foregroundStyle(.bvSecondary)
                            .monospacedDigit()
                            .frame(width: store.scaled(60), alignment: .trailing)
                    }
                }
            }
        }
        .insightsCard()
    }
}
