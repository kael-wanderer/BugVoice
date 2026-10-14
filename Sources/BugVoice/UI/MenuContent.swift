import SwiftUI

/// The menu-bar menu. Basic for now; completed in Task 20.
struct MenuContent: View {
    @Bindable var model: AppModel

    var body: some View {
        Text(model.hotkeyActive ? "Ready · hold Right ⌥ to talk" : "Hotkey not active")
        Divider()
        Button("Open BugVoice…") { model.openMainWindow(.dictation) }
        Button("Settings…") { model.openMainWindow(.settings) }.keyboardShortcut(",")
        Divider()
        Button("Quit BugVoice") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

/// The menu-bar icon. A badge means a permission is missing.
struct MenuBarIcon: View {
    var model: AppModel

    var body: some View {
        Image(systemName: model.permissionsGranted ? "waveform" : "waveform.badge.exclamationmark")
    }
}
