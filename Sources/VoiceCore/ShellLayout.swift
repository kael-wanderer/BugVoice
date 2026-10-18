import Foundation

public enum ShellLayout {
    public static let minimumContentWidth: Double = 420
    public static let baseMinimumWindowWidth: Double = 820
    public static let minimumWindowHeight: Double = 560

    /// Widths the owner can drag the sidebar and the list pane to.
    public static let sidebarRange: ClosedRange<Double> = 180...320
    public static let listPaneRange: ClosedRange<Double> = 220...440

    /// The dragged width, clamped, or the default for this text size.
    public static func sidebarWidth(scale: Int, dragged: Double? = nil) -> Double {
        dragged.map { clamp($0, sidebarRange) } ?? min(TypeScale.scaled(200, scale: scale), 260)
    }

    public static func listPaneWidth(scale: Int, dragged: Double? = nil) -> Double {
        dragged.map { clamp($0, listPaneRange) } ?? min(TypeScale.scaled(290, scale: scale), 360)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    public static func minimumWindowWidth(scale: Int, screenWidth: Double) -> Double {
        minimumWindowWidth(sidebar: sidebarWidth(scale: scale), listPane: listPaneWidth(scale: scale), screenWidth: screenWidth)
    }

    /// `content` is the widest block a page must keep on one line, such as
    /// the Settings section pills, so shrinking the window never wraps it.
    public static func minimumWindowWidth(sidebar: Double, listPane: Double, content: Double = 0, screenWidth: Double) -> Double {
        min(max(baseMinimumWindowWidth, sidebar + max(listPane + minimumContentWidth, content) + 2 * 24), screenWidth)
    }

    public static func sidebarMustHide(scale: Int, screenWidth: Double) -> Bool {
        sidebarWidth(scale: scale) + listPaneWidth(scale: scale) + minimumContentWidth + 2 * 24 > screenWidth
    }

    public static func gutter(available: Double, block: Double) -> Double {
        available >= block + 2 * 32 ? 32 : 24
    }

    public static func blockWidth(available: Double, block: Double) -> Double {
        max(0, min(block, available - 2 * gutter(available: available, block: block)))
    }
}
