import Foundation

/// The three keyboard event types the hotkey tap listens to.
public enum KeyEventKind: Sendable, Equatable {
    case keyDown, keyUp, flagsChanged
}

/// Maps a raw keyboard event (virtual key code and `CGEventFlags` raw value)
/// to a `KeyInput` for `HoldGestureDetector`. Pure, so the "hotkey held
/// alone" rules are tested without an event tap.
///
/// Right Option and Right Command are matched on their device-specific
/// right-side bits, so the left keys never act as the hotkey. The hotkey
/// pressed while another modifier is already held is ignored, so a chord
/// such as ⌃⌥V never starts a recording. Fn is not counted as another
/// modifier: function keys carry the Fn flag on many keyboards.
public enum KeyEventMapper {
    // Generic modifier masks (NX_*MASK).
    static let shift: UInt64 = 0x0002_0000
    static let control: UInt64 = 0x0004_0000
    static let option: UInt64 = 0x0008_0000
    static let command: UInt64 = 0x0010_0000
    static let secondaryFn: UInt64 = 0x0080_0000

    // Device-specific side bits (NX_DEVICE*KEYMASK).
    static let leftControl: UInt64 = 0x0001
    static let leftShift: UInt64 = 0x0002
    static let rightShift: UInt64 = 0x0004
    static let leftCommand: UInt64 = 0x0008
    static let rightCommand: UInt64 = 0x0010
    static let leftOption: UInt64 = 0x0020
    static let rightOption: UInt64 = 0x0040
    static let rightControl: UInt64 = 0x2000

    /// Modifier key code → the flag bit that is set while that key is down.
    static let modifierBits: [Int64: UInt64] = [
        54: rightCommand, 55: leftCommand,
        56: leftShift, 60: rightShift,
        59: leftControl, 62: rightControl,
        58: leftOption, 61: rightOption,
        63: secondaryFn,
    ]

    /// Every bit that means "a modifier other than Fn is held".
    static let anyModifier: UInt64 = shift | control | option | command
        | leftControl | leftShift | rightShift | leftCommand | rightCommand
        | leftOption | rightOption | rightControl

    struct Spec {
        let keyCode: Int64
        /// Set for modifier hotkeys (reported via flagsChanged); nil for
        /// F13–F19 (reported via keyDown/keyUp).
        let downBit: UInt64?
        /// Bits the hotkey sets itself, excluded from "other modifier held".
        let ownBits: UInt64
    }

    static func spec(for key: HotkeyKey) -> Spec {
        switch key {
        case .rightOption: Spec(keyCode: 61, downBit: rightOption, ownBits: option | rightOption)
        case .rightCommand: Spec(keyCode: 54, downBit: rightCommand, ownBits: command | rightCommand)
        case .fn: Spec(keyCode: 63, downBit: secondaryFn, ownBits: 0)
        case .f13: Spec(keyCode: 105, downBit: nil, ownBits: 0)
        case .f14: Spec(keyCode: 107, downBit: nil, ownBits: 0)
        case .f15: Spec(keyCode: 113, downBit: nil, ownBits: 0)
        case .f16: Spec(keyCode: 106, downBit: nil, ownBits: 0)
        case .f17: Spec(keyCode: 64, downBit: nil, ownBits: 0)
        case .f18: Spec(keyCode: 79, downBit: nil, ownBits: 0)
        case .f19: Spec(keyCode: 80, downBit: nil, ownBits: 0)
        }
    }

    public static func map(
        kind: KeyEventKind,
        keyCode: Int64,
        flags: UInt64,
        isAutorepeat: Bool,
        hotkey: HotkeyKey,
        timestamp: TimeInterval
    ) -> KeyInput? {
        let spec = spec(for: hotkey)
        let otherModifierHeld = flags & anyModifier & ~spec.ownBits != 0

        switch kind {
        case .flagsChanged:
            guard let bit = modifierBits[keyCode] else { return nil }
            let isDown = flags & bit != 0
            if keyCode == spec.keyCode, spec.downBit != nil {
                guard isDown else { return .hotkeyUp(timestamp) }
                return otherModifierHeld ? nil : .hotkeyDown(timestamp)
            }
            return isDown ? .otherKeyDown(timestamp) : nil

        case .keyDown:
            guard spec.downBit == nil, keyCode == spec.keyCode else { return .otherKeyDown(timestamp) }
            if isAutorepeat || otherModifierHeld { return nil }
            return .hotkeyDown(timestamp)

        case .keyUp:
            guard spec.downBit == nil, keyCode == spec.keyCode else { return nil }
            return .hotkeyUp(timestamp)
        }
    }
}
