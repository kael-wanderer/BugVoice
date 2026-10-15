import SwiftUI
import VoiceCore

struct BreakdownBars: View {
    let title: String
    var trailing: String? = nil
    let rows: [BreakdownRow]
    /// The text on the right of each bar.
    let value: (BreakdownRow) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let trailing { Text(trailing).font(.caption).foregroundStyle(.secondary) }
            }
            if rows.isEmpty {
                Text("No dictation in this period.").font(.callout).foregroundStyle(.secondary)
            } else {
                let top = rows.map(\.share).max() ?? 1
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Text(row.name).lineLimit(1).frame(width: 90, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.07))
                                Capsule().fill(Color.accentColor)
                                    .frame(width: top > 0 ? proxy.size.width * row.share / top : 0)
                            }
                        }
                        .frame(height: 8)
                        Text(value(row))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
        .insightsCard()
    }
}
