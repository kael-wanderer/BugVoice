import SwiftUI

/// Stat cards in rows of four, or two (then one) when four would be narrower
/// than `minCardWidth`. Columns share the full width; every card in a row
/// gets the row's tallest height, so the cards line up.
struct CardGrid: Layout {
    var minCardWidth: CGFloat
    var spacing: CGFloat

    private func columns(_ width: CGFloat) -> Int {
        for count in [4, 2] where (width - CGFloat(count - 1) * spacing) / CGFloat(count) >= minCardWidth {
            return count
        }
        return 1
    }

    private func rows(_ width: CGFloat, _ subviews: Subviews) -> (columnWidth: CGFloat, heights: [CGFloat], columns: Int) {
        let columns = columns(width)
        let columnWidth = max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        var heights: [CGFloat] = []
        for start in stride(from: 0, to: subviews.count, by: columns) {
            let row = subviews[start..<min(start + columns, subviews.count)]
            heights.append(row.map { $0.sizeThatFits(.init(width: columnWidth, height: nil)).height }.max() ?? 0)
        }
        return (columnWidth, heights, columns)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minCardWidth * 4 + spacing * 3
        let layout = rows(width, subviews)
        let height = layout.heights.reduce(0, +) + CGFloat(max(0, layout.heights.count - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = rows(bounds.width, subviews)
        var y = bounds.minY
        for (rowIndex, height) in layout.heights.enumerated() {
            for column in 0..<layout.columns {
                let index = rowIndex * layout.columns + column
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(column) * (layout.columnWidth + spacing)
                subviews[index].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading,
                    proposal: .init(width: layout.columnWidth, height: height))
            }
            y += height + spacing
        }
    }
}
