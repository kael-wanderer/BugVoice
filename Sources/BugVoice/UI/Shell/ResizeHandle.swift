import SwiftUI

/// The 1 pt border between two columns. Dragging it sets the width of the
/// column on its left; double-clicking it goes back to the default width.
struct ResizeHandle: View {
    let width: Double
    let range: ClosedRange<Double>
    /// The new width, or nil for the default.
    let onChange: (Double?) -> Void
    @State private var dragStart: Double?

    var body: some View {
        Rectangle().fill(.bvSeparator).frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .pointerStyle(.columnResize)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStart ?? width
                                dragStart = start
                                onChange(min(max(start + value.translation.width, range.lowerBound), range.upperBound))
                            }
                            .onEnded { _ in dragStart = nil }
                    )
                    .onTapGesture(count: 2) { onChange(nil) }
            }
            .zIndex(1)
            .accessibilityHidden(true)
    }
}
