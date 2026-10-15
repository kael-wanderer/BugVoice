import SwiftUI
import VoiceCore

struct GeneralTab: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsScroll {
            SettingsCard {
                SettingsRow(title: "Hotkey") {
                    Picker("Hotkey", selection: $model.settings.hotkey) {
                        ForEach(HotkeyKey.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                Text("Hold to talk. Pressing another key cancels.").font(.caption).foregroundStyle(.secondary)
                Divider()
                SettingsToggle(title: "Hands-free: double-tap the hotkey to start, tap once to stop", isOn: $model.settings.handsFreeEnabled)
                Divider()
                SettingsRow(title: "Hands-free limit") {
                    Picker("Hands-free limit", selection: $model.settings.handsFreeLimitMinutes) {
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("20 minutes").tag(20)
                    }
                    .labelsHidden().fixedSize()
                }
            }
            SettingsCard {
                SettingsToggle(title: "Start and stop sounds", isOn: $model.settings.soundsEnabled)
                Divider()
                SettingsToggle(title: "Put the previous clipboard back after pasting", isOn: $model.settings.restoreClipboard)
                Divider()
                SettingsToggle(title: "Launch at login", isOn: $model.settings.launchAtLogin)
            }
        }
    }
}
