import SwiftUI
import VoiceCore

struct RoundPills<Value: Hashable>: View {
    enum Size { case regular, small }
    @Environment(AppearanceStore.self) private var store
    let label: String
    let items: [(Value, String)]
    @Binding var selection: Value
    var size: Size

    init(_ label: String, items: [(Value, String)], selection: Binding<Value>, size: Size = .regular) {
        self.label = label; self.items = items; self._selection = selection; self.size = size
    }

    var body: some View {
        EqualPillLayout(spacing: LayoutTokens.spacing[0]) {
            ForEach(items, id: \.0) { value, title in
                Button { selection = value } label: {
                    Text(title)
                        .bvFont(size == .small ? .footnote : selection == value ? .bodyStrong : .body)
                        .fontWeight(selection == value ? .semibold : .regular)
                        .foregroundStyle(selection == value ? store.theme.text : store.theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, size == .small ? LayoutTokens.spacing[1] : LayoutTokens.spacing[2])
                        .padding(.vertical, LayoutTokens.spacing[1])
                        .background {
                            if selection == value {
                                Capsule().fill(.bvBackground)
                                    .shadow(color: store.theme.text.opacity(0.2), radius: store.scaled(1.5), y: store.scaled(1))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(LayoutTokens.spacing[0])
        .background(.bvHover, in: RoundedRectangle(cornerRadius: store.scaled(24)))
        .overlay(RoundedRectangle(cornerRadius: store.scaled(24)).stroke(.bvSeparator))
        .accessibilityElement(children: .contain).accessibilityLabel(label)
    }
}

/// A flow layout that measures the widest label, wraps complete pills, and
/// proposes equal widths to every pill on a row (including the final row).
private struct EqualPillLayout: Layout {
    var spacing: CGFloat
    private func rows(_ width: CGFloat, _ views: Subviews) -> [(Range<Int>, CGFloat, CGFloat)] {
        guard !views.isEmpty else { return [] }
        let widest = views.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let fit = max(1, min(views.count, Int((width + spacing) / max(1, widest + spacing))))
        // Spread the pills evenly over the rows they need, so no row holds one stray pill.
        let rowCount = (views.count + fit - 1) / fit
        let columns = (views.count + rowCount - 1) / rowCount
        return stride(from: 0, to: views.count, by: columns).map { start in
            let range = start..<min(start + columns, views.count)
            let cell = max(0, (width - spacing * CGFloat(range.count - 1)) / CGFloat(range.count))
            let height = range.map { views[$0].sizeThatFits(.init(width: cell, height: nil)).height }.max() ?? 0
            return (range, cell, height)
        }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let natural = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width = proposal.width ?? natural * CGFloat(subviews.count) + spacing * CGFloat(max(0, subviews.count - 1))
        let rows = rows(width, subviews)
        return .init(width: width, height: rows.reduce(0) { $0 + $1.2 } + spacing * CGFloat(max(0, rows.count - 1)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for (range, cell, height) in rows(bounds.width, subviews) {
            for (column, index) in range.enumerated() {
                subviews[index].place(at: .init(x: bounds.minX + CGFloat(column) * (cell + spacing), y: y), proposal: .init(width: cell, height: height))
            }
            y += height + spacing
        }
    }
}
