import Carbon

/// System-wide ⌃⌥ shortcuts (Paste last, Open BugVoice). These consume the
/// keystroke, unlike the listen-only dictation tap.
@MainActor
public final class GlobalShortcuts {
    public static let shared = GlobalShortcuts()
    public static let controlOption = UInt32(controlKey | optionKey)

    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var installed = false
    private let registerHotKey: @MainActor (UInt32, UInt32, EventHotKeyID) -> (OSStatus, EventHotKeyRef?)
    private let unregisterHotKey: @MainActor (EventHotKeyRef) -> OSStatus

    public init() {
        registerHotKey = Self.systemRegister
        unregisterHotKey = Self.systemUnregister
    }

    init(
        registerHotKey: @escaping @MainActor (UInt32, UInt32, EventHotKeyID) -> (OSStatus, EventHotKeyRef?)
    ) {
        self.registerHotKey = registerHotKey
        unregisterHotKey = Self.systemUnregister
    }

    init(
        registerHotKey: @escaping @MainActor (UInt32, UInt32, EventHotKeyID) -> (OSStatus, EventHotKeyRef?),
        unregisterHotKey: @escaping @MainActor (EventHotKeyRef) -> OSStatus
    ) {
        self.registerHotKey = registerHotKey
        self.unregisterHotKey = unregisterHotKey
    }

    @discardableResult
    public func register(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) -> Bool {
        guard installHandler() else { return false }
        let id = UInt32(actions.count + 1)
        let hotKeyID = EventHotKeyID(signature: OSType(0x4256_4345), id: id) // 'BVCE'
        let (status, ref) = registerHotKey(keyCode, modifiers, hotKeyID)
        guard status == noErr,
              let ref else { return false }
        actions[id] = action
        refs.append(ref)
        return true
    }

    func fire(_ id: UInt32) {
        actions[id]?()
    }

    public func unregisterAll() {
        for ref in refs { _ = unregisterHotKey(ref) }
        refs.removeAll()
        actions.removeAll()
    }

    private func installHandler() -> Bool {
        guard !installed else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let id = hotKeyID.id
            MainActor.assumeIsolated { GlobalShortcuts.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
        guard status == noErr else { return false }
        installed = true
        return true
    }

    private static func systemRegister(
        _ keyCode: UInt32,
        _ modifiers: UInt32,
        _ id: EventHotKeyID
    ) -> (OSStatus, EventHotKeyRef?) {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        return (status, ref)
    }

    private static func systemUnregister(_ ref: EventHotKeyRef) -> OSStatus {
        UnregisterEventHotKey(ref)
    }
}
