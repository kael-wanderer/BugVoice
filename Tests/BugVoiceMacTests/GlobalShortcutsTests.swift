import Carbon
import Testing
@testable import BugVoiceMac

@MainActor
struct GlobalShortcutsTests {
    @Test func unregisterAllClearsRegisteredShortcuts() {
        var nextRef = 1
        var unregistered = 0
        var fired: [String] = []
        let shortcuts = GlobalShortcuts(
            registerHotKey: { _, _, _ in
                defer { nextRef += 1 }
                return (noErr, EventHotKeyRef(bitPattern: nextRef))
            },
            unregisterHotKey: { _ in
                unregistered += 1
                return noErr
            },
            installEventHandler: { true }
        )
        #expect(shortcuts.register(keyCode: 9, modifiers: GlobalShortcuts.controlOption) { fired.append("old-1") })
        #expect(shortcuts.register(keyCode: 45, modifiers: GlobalShortcuts.controlOption) { fired.append("old-2") })
        shortcuts.unregisterAll()
        #expect(unregistered == 2)
        #expect(shortcuts.register(keyCode: 40, modifiers: GlobalShortcuts.controlOption) { fired.append("new") })
        shortcuts.fire(1)
        #expect(fired == ["new"])
    }

    @Test func failedSystemRegistrationIsReported() {
        let shortcuts = GlobalShortcuts(registerHotKey: { _, _, _ in (OSStatus(paramErr), nil) })
        let registered = shortcuts.register(
            keyCode: 0,
            modifiers: GlobalShortcuts.controlOption,
            action: {}
        )
        #expect(!registered)
    }
}
