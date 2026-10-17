import Foundation

/// Keeps a window inside a display's visible frame, so its buttons stay reachable.
public enum WindowPlacement {
    /// A frame in screen points. VoiceCore's own type: a `CGRect` here crashed the
    /// release build's optimizer when inlined into the app.
    public struct Frame: Equatable, Sendable {
        public var x, y, width, height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// The frame moved, and shrunk only when larger than `visible`, to lie fully inside it.
    public static func onScreen(_ frame: Frame, visible: Frame) -> Frame {
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        return Frame(
            x: min(max(frame.x, visible.x), visible.x + visible.width - width),
            y: min(max(frame.y, visible.y), visible.y + visible.height - height),
            width: width,
            height: height
        )
    }
}
