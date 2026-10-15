import SwiftUI
import VoiceCore

struct ActivityHeatmap: View {
    let weeks: [HeatWeek]
    @State private var hovered: HeatCell?

    private let cell: CGFloat = 12
    private let gap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Speaking activity").font(.headline)
                Spacer()
                Text("Last 52 weeks").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .trailing, spacing: gap) {
                        Color.clear.frame(height: 14)
                        ForEach(0..<7, id: \.self) { row in
                            Text(Self.dayLabel(row))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(height: cell)
                        }
                    }
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(weeks) { week in
                            VStack(spacing: gap) {
                                Text(week.monthLabel ?? "")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                                    .frame(width: cell, height: 14, alignment: .leading)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                legend
            }
        }
        .insightsCard()
    }

    private func square(_ day: HeatCell) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Self.color(level: day.level))
            .opacity(day.inPeriod ? 1 : 0.35)
            .frame(width: cell, height: cell)
            .overlay {
                if hovered == day {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary, lineWidth: 1.5)
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
        HStack(spacing: 4) {
            Text("Less")
            ForEach(1...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2).fill(Self.color(level: level)).frame(width: 10, height: 10)
            }
            Text("More")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    static func dayLabel(_ row: Int) -> String {
        switch row {
        case 1: "Mon"
        case 3: "Wed"
        case 5: "Fri"
        default: ""
        }
    }

    static func color(level: Int) -> Color {
        let opacities: [Double] = [0.3, 0.5, 0.75, 1]
        return level <= 0 ? Color.primary.opacity(0.08) : Color.accentColor.opacity(opacities[min(level, 4) - 1])
    }
}
