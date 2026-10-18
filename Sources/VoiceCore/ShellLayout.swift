import Foundation

public enum ShellLayout {
    public static let minimumContentWidth: Double = 420
    public static let baseMinimumWindowWidth: Double = 820
    public static let minimumWindowHeight: Double = 560

    public static func sidebarWidth(scale: Int) -> Double {
        min(TypeScale.scaled(200, scale: scale), 260)
    }

    public static func listPaneWidth(scale: Int) -> Double {
        min(TypeScale.scaled(250, scale: scale), 320)
    }

    public static func sectionListWidth(scale: Int) -> Double {
        min(TypeScale.scaled(180, scale: scale), 230)
    }

    public static func minimumWindowWidth(scale: Int, screenWidth: Double) -> Double {
        min(
            max(baseMinimumWindowWidth, sidebarWidth(scale: scale) + listPaneWidth(scale: scale) + minimumContentWidth + 2 * 24),
            screenWidth
        )
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
