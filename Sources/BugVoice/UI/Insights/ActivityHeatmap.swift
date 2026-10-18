import SwiftUI
import VoiceCore

struct ActivityHeatmap: View {
    @Environment(AppearanceStore.self) private var store
    let weeks: [HeatWeek]
    @State private var hovered: HeatCell?

    private var cell: CGFloat { store.scaled(12) }
    private let gap: CGFloat = LayoutTokens.spacing[0]

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            HStack {
                Text("Speaking activity").bvFont(.bodyStrong)
                Spacer()
                Text("Last 52 weeks").bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: LayoutTokens.spacing[0]) {
                    VStack(alignment: .trailing, spacing: gap) {
                        Color.clear.frame(height: store.scaled(14))
                        ForEach(0..<7, id: \.self) { row in
                            Text(Self.dayLabel(row))
                                .bvFont(.caption)
                                .foregroundStyle(.bvSecondary)
                                .frame(height: cell)
                        }
                    }
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(weeks) { week in
                            VStack(spacing: gap) {
                                Text(week.monthLabel ?? "")
                                    .bvFont(.caption)
                                    .foregroundStyle(.bvSecondary)
                                    .fixedSize()
                                    .frame(width: cell, height: store.scaled(14), alignment: .leading)
                                ForEach(0..<7, id: \.self) { row in
                                    if let day = week.days[row] {
                                        square(day)
                                    } else {
                                        Color.clear.frame(width: cell, height: cell)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            HStack {
                Text(caption)
                    .bvFont(.footnote)
                    .foregroundStyle(.bvSecondary)
                    .monospacedDigit()
                Spacer()
                legend
            }
        }
        .insightsCard()
    }

    private func square(_ day: HeatCell) -> some View {
        RoundedRectangle(cornerRadius: LayoutTokens.controlRadius)
            .fill(color(level: day.level))
            .opacity(day.inPeriod ? 1 : 0.35)
            .frame(width: cell, height: cell)
            .overlay {
                if hovered == day {
                    RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).strokeBorder(store.theme.text, lineWidth: 1.5)
                }
            }
            .onHover { inside in
                if inside { hovered = day } else if hovered == day { hovered = nil }
            }
    }

    private var caption: String {
        guard let day = hovered else { return "Hover a day to see its words and dictations." }
        let date = day.date.formatted(.dateTime.month(.abbreviated).day())
        guard day.words > 0 else { return "\(date): no dictation" }
        return "\(date): \(day.words.formatted()) words · \(day.dictations) dictations"
    }

    private var legend: some View {
        HStack(spacing: LayoutTokens.spacing[0]) {
            Text("Less")
            ForEach(1...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2).fill(color(level: level)).frame(width: 10, height: 10)
            }
            Text("More")
        }
        .bvFont(.footnote)
        .foregroundStyle(.bvSecondary)
    }

    static func dayLabel(_ row: Int) -> String {
        switch row {
        case 1: "Mon"
        case 3: "Wed"
        case 5: "Fri"
        default: ""
        }
    }

    private func color(level: Int) -> Color {
        let opacities: [Double] = [0.3, 0.5, 0.75, 1]
        return level <= 0 ? store.theme.text.opacity(0.08) : store.theme.accent.opacity(opacities[min(level, 4) - 1])
    }
}
