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

    public func register(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        installHandler()
        let id = UInt32(actions.count + 1)
        actions[id] = action
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4256_4345), id: id) // 'BVCE'
        if RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
            refs.append(ref)
        }
    }

    func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let id = hotKeyID.id
            MainActor.assumeIsolated { GlobalShortcuts.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
