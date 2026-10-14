import Carbon
import Testing
@testable import BugVoiceMac

@MainActor
struct GlobalShortcutsTests {
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
