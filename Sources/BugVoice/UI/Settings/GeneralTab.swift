import SwiftUI
import VoiceCore

struct GeneralTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Picker("Hotkey", selection: $model.settings.hotkey) {
                ForEach(HotkeyKey.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Text("Hold to talk. Pressing another key cancels.").font(.caption).foregroundStyle(.secondary)
            Toggle("Hands-free: double-tap the hotkey to start, tap once to stop", isOn: $model.settings.handsFreeEnabled)
            Picker("Hands-free limit", selection: $model.settings.handsFreeLimitMinutes) {
                Text("5 minutes").tag(5)
                Text("10 minutes").tag(10)
                Text("20 minutes").tag(20)
            }
            Toggle("Start and stop sounds", isOn: $model.settings.soundsEnabled)
            Toggle("Put the previous clipboard back after pasting", isOn: $model.settings.restoreClipboard)
            Toggle("Launch at login", isOn: $model.settings.launchAtLogin)
        }
        .formStyle(.grouped)
    }
}
