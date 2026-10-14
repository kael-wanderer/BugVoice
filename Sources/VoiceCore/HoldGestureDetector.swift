import Foundation

public enum KeyInput: Sendable, Equatable {
    case hotkeyDown(TimeInterval)
    case hotkeyUp(TimeInterval)
    case otherKeyDown(TimeInterval)
}

public enum GestureAction: Sendable, Equatable {
    case startHold
    case startHandsFree
    case stop
    case cancel
}

/// Pure state machine for the dictation hotkey. The app feeds it key events
/// and calls `tick(now:)` once `holdThreshold` after each key-down.
public struct HoldGestureDetector: Sendable {
    public var holdThreshold: TimeInterval = 0.15
    public var doubleTapWindow: TimeInterval = 0.30
    public var handsFreeEnabled = true

    enum Phase: Sendable, Equatable {
        case idle
        case pressed(since: TimeInterval, tainted: Bool)
        case holding
        case handsFree
        case handsFreePressed
    }

    var phase: Phase = .idle
    var lastTapAt: TimeInterval?

    public init() {}

    public var isRecording: Bool {
        switch phase {
        case .holding, .handsFree, .handsFreePressed: true
        case .idle, .pressed: false
        }
    }

    public mutating func reset() {
        phase = .idle
        lastTapAt = nil
    }

    public mutating func handle(_ input: KeyInput) -> [GestureAction] {
        switch (phase, input) {
        case (.idle, .hotkeyDown(let t)):
            phase = .pressed(since: t, tainted: false)
            return []
        case (.pressed(let since, _), .otherKeyDown):
            phase = .pressed(since: since, tainted: true)
            return []
        case (.pressed(let since, let tainted), .hotkeyUp(let t)):
            phase = .idle
            if tainted || t - since >= holdThreshold {
                lastTapAt = nil
                return []
            }
            if handsFreeEnabled, let last = lastTapAt, t - last <= doubleTapWindow {
                lastTapAt = nil
                phase = .handsFree
                return [.startHandsFree]
            }
            lastTapAt = t
            return []
        case (.holding, .otherKeyDown):
            phase = .idle
            return [.cancel]
        case (.holding, .hotkeyUp):
            phase = .idle
            return [.stop]
        case (.handsFree, .hotkeyDown):
            phase = .handsFreePressed
            return []
        case (.handsFreePressed, .hotkeyUp):
            phase = .idle
            return [.stop]
        default:
            return []
        }
    }

    public mutating func tick(now: TimeInterval) -> [GestureAction] {
        if case .pressed(let since, false) = phase, now - since >= holdThreshold {
            phase = .holding
            lastTapAt = nil
            return [.startHold]
        }
        return []
    }
}
