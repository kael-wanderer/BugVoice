import Foundation

/// What identifies a focused field when its accessibility reference does not:
/// browsers and text views sometimes hand back a new reference for the same
/// field, so reference equality alone turns a same-field paste into a copy.
public struct FocusFingerprint: Equatable, Sendable {
    public var pid: Int32
    public var role: String?
    public var subrole: String?
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(pid: Int32, role: String?, subrole: String?, x: Double, y: Double, width: Double, height: Double) {
        self.pid = pid
        self.role = role
        self.subrole = subrole
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Frame differences below this many points are rounding, not another field.
    static let tolerance = 1.0

    /// Same target when the references are equal, or when both fingerprints name
    /// the same app, role, subrole and on-screen frame. Fails closed without a role or a real frame.
    public static func isSameTarget(identical: Bool, start: FocusFingerprint?, now: FocusFingerprint?) -> Bool {
        if identical { return true }
        guard let start, let now, start.role != nil, start.width > 0, start.height > 0 else { return false }
        return start.pid == now.pid
            && start.role == now.role
            && start.subrole == now.subrole
            && abs(start.x - now.x) < tolerance
            && abs(start.y - now.y) < tolerance
            && abs(start.width - now.width) < tolerance
            && abs(start.height - now.height) < tolerance
    }
}
