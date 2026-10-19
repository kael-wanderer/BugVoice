import AppKit
import CoreGraphics
import VoiceCore

/// Listen-only event tap: it observes keys and never blocks them, so only the
/// Input Monitoring permission is needed. Runs on the main run loop.
///
/// Key rules live in `KeyEventMapper` (VoiceCore). The hold threshold tick is
/// the caller's job (`HoldGestureDetector.tick` after each `.hotkeyDown`).
@MainActor
public final class HotkeyMonitor {
    public var key: HotkeyKey
    public var languageKey: LanguageKey = .off
    public var onKeyDown: (@MainActor (Int64, UInt64, Int64) -> Void)?
    /// Called once the tap is disabled by the system and three re-enables in a
    /// row have failed. The monitor is stopped by then.
    public var onTapLost: (@MainActor () -> Void)?
    private let onInput: @MainActor (KeyInput) -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var failedReenables = 0
    private var retryTask: Task<Void, Never>?
    public private(set) var reenableCount = 0

    static let maxFailedReenables = 3
    static let reenableRetryDelay: Duration = .milliseconds(500)

    public init(key: HotkeyKey, onInput: @escaping @MainActor (KeyInput) -> Void) {
        self.key = key
        self.onInput = onInput
    }

    public var isRunning: Bool { tap != nil }

    /// Returns false when the tap cannot be created (Input Monitoring missing
    /// or granted but not yet effective until relaunch).
    public func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        failedReenables = 0
        return true
    }

    public func stop() {
        retryTask?.cancel()
        retryTask = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Plain values read from the event inside the tap callback; the
    /// `CGEvent` itself never crosses into main-actor code.
    func handle(type: CGEventType, keyCode: Int64, flags: UInt64, isAutorepeat: Bool, userData: Int64 = 0) {
        let kind: KeyEventKind
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reenable()
            return
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        default: return
        }
        if kind == .keyDown { onKeyDown?(keyCode, flags, userData) }
        let input = KeyEventMapper.map(
            kind: kind,
            keyCode: keyCode,
            flags: flags,
            isAutorepeat: isAutorepeat,
            hotkey: key,
            timestamp: ProcessInfo.processInfo.systemUptime,
            languageKey: languageKey
        )
        if let input { onInput(input) }
    }

    /// Re-enables a tap the system switched off. A failed attempt is retried
    /// after a short delay because a disabled tap delivers no further events.
    private func reenable() {
        guard let tap else { return }
        retryTask?.cancel()
        retryTask = nil
        CGEvent.tapEnable(tap: tap, enable: true)
        reenableCount += 1
        if CGEvent.tapIsEnabled(tap: tap) {
            failedReenables = 0
            return
        }
        failedReenables += 1
        if failedReenables >= Self.maxFailedReenables {
            stop()
            onTapLost?()
            return
        }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.reenableRetryDelay)
            guard !Task.isCancelled else { return }
            self?.reenable()
        }
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.rawValue
        let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let userData = event.getIntegerValueField(.eventSourceUserData)
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated {
            monitor.handle(type: type, keyCode: keyCode, flags: flags, isAutorepeat: isAutorepeat, userData: userData)
        }
    }
    return Unmanaged.passUnretained(event)
}
