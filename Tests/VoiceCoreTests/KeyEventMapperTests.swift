import Testing
@testable import VoiceCore

/// Raw flag bits as CoreGraphics reports them (`CGEventFlags.rawValue`).
private enum Bits {
    static let shift: UInt64 = 0x0002_0000
    static let control: UInt64 = 0x0004_0000
    static let option: UInt64 = 0x0008_0000
    static let command: UInt64 = 0x0010_0000
    static let fn: UInt64 = 0x0080_0000
    static let leftControl: UInt64 = 0x01
    static let leftShift: UInt64 = 0x02
    static let leftCommand: UInt64 = 0x08
    static let rightCommand: UInt64 = 0x10
    static let leftOption: UInt64 = 0x20
    static let rightOption: UInt64 = 0x40
    static let rightControl: UInt64 = 0x2000

    static let rightOptionDown = option | rightOption
    static let leftOptionDown = option | leftOption
    static let rightControlDown = control | rightControl
    static let leftControlDown = control | leftControl
    static let rightCommandDown = command | rightCommand
    static let leftCommandDown = command | leftCommand
    static let controlDown = control | leftControl
    static let shiftDown = shift | leftShift
}

private enum Code {
    static let rightOption: Int64 = 61
    static let rightControl: Int64 = 62
    static let leftOption: Int64 = 58
    static let rightCommand: Int64 = 54
    static let leftCommand: Int64 = 55
    static let leftControl: Int64 = 59
    static let leftShift: Int64 = 56
    static let fn: Int64 = 63
    static let e: Int64 = 14
    static let v: Int64 = 9
}

private func map(
    _ kind: KeyEventKind,
    _ code: Int64,
    _ flags: UInt64 = 0,
    repeat isAutorepeat: Bool = false,
    hotkey: HotkeyKey = .rightOption,
    at t: Double = 1
) -> KeyInput? {
    KeyEventMapper.map(kind: kind, keyCode: code, flags: flags, isAutorepeat: isAutorepeat, hotkey: hotkey, timestamp: t)
}

struct KeyEventMapperTests {
    @Test func rightControlPressAndRelease() {
        #expect(map(.flagsChanged, Code.rightControl, Bits.rightControlDown, hotkey: .rightControl, at: 2) == .hotkeyDown(2))
        #expect(map(.flagsChanged, Code.rightControl, 0, hotkey: .rightControl, at: 3) == .hotkeyUp(3))
    }

    @Test func leftControlIsNeverTheRightControlHotkey() {
        #expect(map(.flagsChanged, Code.leftControl, Bits.leftControlDown, hotkey: .rightControl) == .otherKeyDown(1))
        #expect(map(.flagsChanged, Code.leftControl, 0, hotkey: .rightControl) == nil)
    }

    @Test func leftControlReleaseWhileRightControlHeldIsNotAPress() {
        #expect(map(.flagsChanged, Code.leftControl, Bits.rightControlDown, hotkey: .rightControl) == nil)
    }

    @Test func rightControlReleaseWhileLeftControlStillHeldIsHotkeyUp() {
        #expect(map(.flagsChanged, Code.rightControl, Bits.leftControlDown, hotkey: .rightControl) == .hotkeyUp(1))
    }

    @Test func rightControlThenOptionVIsAChord() {
        #expect(map(.flagsChanged, Code.rightControl, Bits.rightControlDown, hotkey: .rightControl) == .hotkeyDown(1))
        #expect(map(.flagsChanged, Code.leftOption, Bits.rightControlDown | Bits.leftOptionDown, hotkey: .rightControl) == .otherKeyDown(1))
        #expect(map(.keyDown, Code.v, Bits.rightControlDown | Bits.leftOptionDown, hotkey: .rightControl) == .otherKeyDown(1))
    }

    // MARK: Right Option / Right Command use device-specific bits

    @Test func rightOptionPressAndRelease() {
        #expect(map(.flagsChanged, Code.rightOption, Bits.rightOptionDown, at: 2) == .hotkeyDown(2))
        #expect(map(.flagsChanged, Code.rightOption, 0, at: 3) == .hotkeyUp(3))
    }

    @Test func leftOptionIsNeverTheRightOptionHotkey() {
        // Left ⌥ sets the generic ⌥ mask but not the right-side device bit.
        #expect(map(.flagsChanged, Code.leftOption, Bits.leftOptionDown) == .otherKeyDown(1))
        #expect(map(.flagsChanged, Code.leftOption, 0) == nil)
    }

    @Test func rightOptionReleaseWhileLeftOptionStillHeldIsHotkeyUp() {
        // Generic ⌥ stays set by left ⌥; the right-side bit is what counts.
        #expect(map(.flagsChanged, Code.rightOption, Bits.leftOptionDown) == .hotkeyUp(1))
    }

    @Test func rightCommandPressAndRelease() {
        #expect(map(.flagsChanged, Code.rightCommand, Bits.rightCommandDown, hotkey: .rightCommand) == .hotkeyDown(1))
        #expect(map(.flagsChanged, Code.rightCommand, 0, hotkey: .rightCommand) == .hotkeyUp(1))
    }

    @Test func leftCommandIsNeverTheRightCommandHotkey() {
        #expect(map(.flagsChanged, Code.leftCommand, Bits.leftCommandDown, hotkey: .rightCommand) == .otherKeyDown(1))
    }

    // MARK: Fn

    @Test func fnPressAndRelease() {
        #expect(map(.flagsChanged, Code.fn, Bits.fn, hotkey: .fn) == .hotkeyDown(1))
        #expect(map(.flagsChanged, Code.fn, 0, hotkey: .fn) == .hotkeyUp(1))
    }

    // MARK: F13–F19

    @Test func functionKeyCodes() {
        let codes: [(HotkeyKey, Int64)] = [
            (.f13, 105), (.f14, 107), (.f15, 113), (.f16, 106), (.f17, 64), (.f18, 79), (.f19, 80),
        ]
        for (key, code) in codes {
            #expect(map(.keyDown, code, hotkey: key) == .hotkeyDown(1), "\(key) down")
            #expect(map(.keyUp, code, hotkey: key) == .hotkeyUp(1), "\(key) up")
        }
    }

    @Test func functionKeyHotkeyToleratesFnFlag() {
        // F-keys carry the secondary-fn flag on many keyboards.
        #expect(map(.keyDown, 105, Bits.fn, hotkey: .f13) == .hotkeyDown(1))
    }

    @Test func autorepeatOfFunctionKeyHotkeyProducesNothing() {
        #expect(map(.keyDown, 105, repeat: true, hotkey: .f13) == nil)
    }

    @Test func otherFunctionKeyIsOtherKey() {
        #expect(map(.keyDown, 107, hotkey: .f13) == .otherKeyDown(1))
        #expect(map(.keyUp, 107, hotkey: .f13) == nil)
    }

    // MARK: Other keys

    @Test func anyNonHotkeyKeyDownIsOtherKey() {
        #expect(map(.keyDown, Code.e, Bits.rightOptionDown) == .otherKeyDown(1))
        #expect(map(.keyDown, Code.e, repeat: true) == .otherKeyDown(1))
        #expect(map(.keyUp, Code.e) == nil)
    }

    @Test func nonHotkeyModifierGoingDownIsOtherKey() {
        // ⌥⇧K: Right ⌥ held, then ⇧.
        #expect(map(.flagsChanged, Code.leftShift, Bits.rightOptionDown | Bits.shiftDown) == .otherKeyDown(1))
        // ⌃ while Right ⌥ held.
        #expect(map(.flagsChanged, Code.leftControl, Bits.rightOptionDown | Bits.controlDown) == .otherKeyDown(1))
        // Left ⌘ while Right ⌥ held.
        #expect(map(.flagsChanged, Code.leftCommand, Bits.rightOptionDown | Bits.leftCommandDown) == .otherKeyDown(1))
        // The other right-side modifier.
        #expect(map(.flagsChanged, Code.rightCommand, Bits.rightOptionDown | Bits.rightCommandDown) == .otherKeyDown(1))
        #expect(map(.flagsChanged, Code.rightOption, Bits.rightOptionDown, hotkey: .rightCommand) == .otherKeyDown(1))
    }

    @Test func nonHotkeyModifierGoingUpIsNothing() {
        #expect(map(.flagsChanged, Code.leftShift, Bits.rightOptionDown) == nil)
        #expect(map(.flagsChanged, Code.leftControl, 0) == nil)
    }

    // MARK: Hotkey must be held alone

    @Test func hotkeyDownWithAnotherModifierAlreadyHeldIsIgnored() {
        // ⌃ held, then Right ⌥ (a ⌃⌥V chord) must not start a recording.
        #expect(map(.flagsChanged, Code.rightOption, Bits.rightOptionDown | Bits.controlDown) == nil)
        #expect(map(.flagsChanged, Code.rightOption, Bits.rightOptionDown | Bits.shiftDown) == nil)
        #expect(map(.flagsChanged, Code.rightOption, Bits.rightOptionDown | Bits.leftCommandDown) == nil)
        #expect(map(.flagsChanged, Code.rightOption, Bits.rightOptionDown | Bits.leftOption) == nil)
        #expect(map(.flagsChanged, Code.rightCommand, Bits.rightCommandDown | Bits.leftCommand, hotkey: .rightCommand) == nil)
        #expect(map(.flagsChanged, Code.fn, Bits.fn | Bits.controlDown, hotkey: .fn) == nil)
        #expect(map(.keyDown, 105, Bits.controlDown, hotkey: .f13) == nil)
    }

    @Test func hotkeyReleaseWithOtherModifiersHeldIsStillHotkeyUp() {
        #expect(map(.flagsChanged, Code.rightOption, Bits.controlDown) == .hotkeyUp(1))
        #expect(map(.keyUp, 105, Bits.controlDown, hotkey: .f13) == .hotkeyUp(1))
    }

    // MARK: Option used as a normal modifier never records (detector + mapper)

    /// Feeds events and threshold ticks to a detector in time order.
    private enum Step { case event(KeyInput?), tick(Double) }

    private func run(_ steps: [Step]) -> (actions: [GestureAction], recording: Bool) {
        var d = HoldGestureDetector()
        var actions: [GestureAction] = []
        for step in steps {
            switch step {
            case .event(let input?): actions += d.handle(input)
            case .event(nil): break
            case .tick(let now): actions += d.tick(now: now)
            }
        }
        return (actions, d.isRecording)
    }

    @Test func optionEChordWhileHoldingRightOptionNeverStartsRecording() {
        let result = run([
            .event(map(.flagsChanged, Code.rightOption, Bits.rightOptionDown, at: 0)),
            .event(map(.keyDown, Code.e, Bits.rightOptionDown, at: 0.05)),
            .tick(0.15),
            .event(map(.flagsChanged, Code.rightOption, 0, at: 0.4)),
        ])
        #expect(result.actions.isEmpty)
        #expect(!result.recording)
    }

    @Test func optionShiftChordWhileHoldingRightOptionNeverStartsRecording() {
        let result = run([
            .event(map(.flagsChanged, Code.rightOption, Bits.rightOptionDown, at: 0)),
            .event(map(.flagsChanged, Code.leftShift, Bits.rightOptionDown | Bits.shiftDown, at: 0.05)),
            .tick(0.15),
            .event(map(.keyDown, 40, Bits.rightOptionDown | Bits.shiftDown, at: 0.2)),
            .event(map(.flagsChanged, Code.rightOption, Bits.shiftDown, at: 0.4)),
        ])
        #expect(result.actions.isEmpty)
        #expect(!result.recording)
    }

    @Test func optionKeyAfterThresholdCancelsRecording() {
        // Slow ⌥E: the hold has started, the chord cancels it (nothing pasted).
        let result = run([
            .event(map(.flagsChanged, Code.rightOption, Bits.rightOptionDown, at: 0)),
            .tick(0.15),
            .event(map(.keyDown, Code.e, Bits.rightOptionDown, at: 0.3)),
            .event(map(.flagsChanged, Code.rightOption, 0, at: 0.4)),
        ])
        #expect(result.actions == [.startHold, .cancel])
        #expect(!result.recording)
    }

    @Test func controlOptionVChordNeverStartsRecording() {
        let result = run([
            .event(map(.flagsChanged, Code.leftControl, Bits.controlDown, at: 0)),
            .event(map(.flagsChanged, Code.rightOption, Bits.controlDown | Bits.rightOptionDown, at: 0.01)),
            .tick(0.16),
            .event(map(.keyDown, Code.v, Bits.controlDown | Bits.rightOptionDown, at: 0.3)),
            .event(map(.flagsChanged, Code.rightOption, Bits.controlDown, at: 0.4)),
        ])
        #expect(result.actions.isEmpty)
        #expect(!result.recording)
    }
}
