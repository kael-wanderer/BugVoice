import AppKit
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
                        .lineLimit(1)
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
            // One line per possible row break; the layout hides the ones it does not use.
            ForEach(1..<max(1, items.count), id: \.self) { _ in
                Rectangle().fill(.bvSeparator).layoutValue(key: PillDivider.self, value: true)
                    .accessibilityHidden(true)
            }
        }
        .padding(LayoutTokens.spacing[0])
        .background(.bvHover, in: RoundedRectangle(cornerRadius: store.scaled(24)))
        .overlay(RoundedRectangle(cornerRadius: store.scaled(24)).stroke(.bvSeparator))
        .accessibilityElement(children: .contain).accessibilityLabel(label)
    }
}

extension RoundPills {
    /// Width of a regular-size pill row on one line, every label measured in
    /// the selected (semibold) font so any selection fits.
    static func singleRowWidth(_ titles: [String], font: NSFont) -> CGFloat {
        let spacing = LayoutTokens.spacing
        let labels = titles.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) + 2 * spacing[2] }
        return labels.reduce(0, +) + spacing[0] * CGFloat(max(0, titles.count - 1)) + 2 * spacing[0] + 2
    }
}

private struct PillDivider: LayoutValueKey { static let defaultValue = false }

/// Lays the pills out in one row when it can: equal widths when the widest
/// label fits that way, else each pill at its own width plus an even share of
/// the spare space. Only when one row is too narrow does it wrap, spreading
/// the pills evenly over the rows (equal widths per row) with a line between rows.
private struct EqualPillLayout: Layout {
    var spacing: CGFloat
    private struct Row { var range: Range<Int>; var widths: [CGFloat]; var height: CGFloat }

    private func rows(_ width: CGFloat, _ pills: [LayoutSubview]) -> [Row] {
        guard !pills.isEmpty else { return [] }
        let natural = pills.map { $0.sizeThatFits(.unspecified).width }
        let widest = natural.max() ?? 0
        let gaps = spacing * CGFloat(pills.count - 1)
        func row(_ range: Range<Int>, _ widths: [CGFloat]) -> Row {
            let height = zip(range, widths).map { pills[$0].sizeThatFits(.init(width: $1, height: nil)).height }.max() ?? 0
            return Row(range: range, widths: widths, height: height)
        }
        if widest * CGFloat(pills.count) + gaps <= width {
            return [row(0..<pills.count, Array(repeating: (width - gaps) / CGFloat(pills.count), count: pills.count))]
        }
        let total = natural.reduce(0, +)
        if total + gaps <= width {
            let share = (width - gaps - total) / CGFloat(pills.count)
            return [row(0..<pills.count, natural.map { $0 + share })]
        }
        let fit = max(1, min(pills.count, Int((width + spacing) / max(1, widest + spacing))))
        // Spread the pills evenly over the rows they need, so no row holds one stray pill.
        let rowCount = (pills.count + fit - 1) / fit
        let columns = (pills.count + rowCount - 1) / rowCount
        return stride(from: 0, to: pills.count, by: columns).map { start in
            let range = start..<min(start + columns, pills.count)
            let cell = max(0, (width - spacing * CGFloat(range.count - 1)) / CGFloat(range.count))
            return row(range, Array(repeating: cell, count: range.count))
        }
    }
    private func split(_ subviews: Subviews) -> (pills: [LayoutSubview], dividers: [LayoutSubview]) {
        (subviews.filter { !$0[PillDivider.self] }, subviews.filter { $0[PillDivider.self] })
    }
    /// Space between two rows: a gap, the 1 pt line, a gap.
    private var rowGap: CGFloat { spacing * 2 + 1 }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let pills = split(subviews).pills
        let natural = pills.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +)
        let width = proposal.width ?? natural + spacing * CGFloat(max(0, pills.count - 1))
        let rows = rows(width, pills)
        return .init(width: width, height: rows.reduce(0) { $0 + $1.height } + rowGap * CGFloat(max(0, rows.count - 1)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (pills, dividers) = split(subviews)
        let rows = rows(bounds.width, pills)
        let inset = spacing * 4
        var y = bounds.minY
        for (rowIndex, row) in rows.enumerated() {
            var x = bounds.minX
            for (index, width) in zip(row.range, row.widths) {
                pills[index].place(at: .init(x: x, y: y), proposal: .init(width: width, height: row.height))
                x += width + spacing
            }
            y += row.height
            if rowIndex < rows.count - 1, dividers.indices.contains(rowIndex) {
                dividers[rowIndex].place(at: .init(x: bounds.minX + inset, y: y + spacing), proposal: .init(width: bounds.width - inset * 2, height: 1))
                y += rowGap
            }
        }
        for divider in dividers.dropFirst(max(0, rows.count - 1)) {
            divider.place(at: .init(x: bounds.minX, y: bounds.minY), proposal: .zero)
        }
    }
}
