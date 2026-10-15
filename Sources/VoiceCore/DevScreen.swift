import Foundation

/// Development runs only: `Scripts/run-dev-app.sh` launches the app with
/// `BUGVOICE_DEV_SCREEN=second`, and its windows then open on a display that
/// is not primary (the one with the menu bar), so agents' runs stay off the
/// owner's work. With one display nothing changes. A normal launch (Finder,
/// login item, DMG) has no such variable and is never moved.
public enum DevScreen {
    public static let environmentKey = "BUGVOICE_DEV_SCREEN"

    /// A display's origin in desktop coordinates, unique per display.
    public struct Display: Equatable, Sendable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Index into `displays` to open on, or nil to leave the window where it is.
    public static func choose(_ displays: [Display], primary: Display?, setting: String?) -> Int? {
        guard setting?.lowercased() == "second", displays.count > 1 else { return nil }
        let primary = primary ?? displays[0]
        return displays.firstIndex { $0 != primary }
    }
}
