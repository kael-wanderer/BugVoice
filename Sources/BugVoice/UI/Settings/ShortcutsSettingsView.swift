import SwiftUI
import VoiceCore

struct ShortcutsSettingsView: View {
    @Bindable var model: AppModel
    @State private var conflicts: [ShortcutAction: String] = [:]
    @Environment(AppearanceStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
                AppearanceCard(title: "Dictation") {
                    HStack {
                        Text("Hold to talk")
                        Spacer()
                        Picker("Hold to talk", selection: $model.settings.hotkey) {
                            ForEach(HotkeyKey.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }.labelsHidden().fixedSize()
                    }
                    fixed("Hands-free", "Double-tap \(model.settings.hotkey.spokenName)")
                    if let key = model.settings.effectiveCommandKey.hotkeyKey {
                        fixed("Command", "Hold \(key.spokenName)")
                    }
                    shortcut(.pasteLast)
                    shortcut(.pasteRaw)
                    shortcut(.redoOtherLanguage)
                    shortcut(.toggleMeeting)
                }
                AppearanceCard(title: "Windows") {
                    shortcut(.openApp)
                    shortcut(.newNote)
                    fixed("Search everything", "⌘K")
                    fixed("Show or hide sidebar", "⌃⌘S")
                }
                AppearanceCard(title: "Text size") {
                    fixed("Bigger text", "⌘+")
                    fixed("Smaller text", "⌘−")
                    fixed("Actual size", "⌘0")
                }
                AppearanceCard(title: "Scratchpad") {
                    fixed("New note", "⌘N")
                    fixed("Bold, italic, underline, link", "⌘B  ⌘I  ⌘U  ⌘K")
                    fixed("Copy as Markdown", "⌘⇧C")
                    fixed("Run the AI bar", "⌘↩")
                }
            }.bvFont(.body).padding(LayoutTokens.spacing[0])
        }
    }
    private func fixed(_ title: String, _ keys: String, coming: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
            HStack { Text(title); Spacer(); Text(keys).bvFont(.bodyStrong) }
            if coming { Text("Coming with the new window layout.").bvFont(.footnote).foregroundStyle(.bvSecondary) }
        }
    }
    private func shortcut(_ action: ShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
            HStack {
                Text(action.title)
                Spacer()
                Text("⌃⌥").bvFont(.bodyStrong)
                Picker(action.title, selection: Binding(get: {
                    model.settings.shortcuts.letter(for: action)
                }, set: { letter in
                    if model.settings.shortcuts.setLetter(letter, for: action) { conflicts[action] = nil }
                    else if let other = ShortcutAction.allCases.first(where: { $0 != action && model.settings.shortcuts.letter(for: $0) == letter }) {
                        conflicts[action] = "Already used by \(other.title)."
                    }
                })) {
                    ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init), id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: store.scaled(72))
            }
            if let message = conflicts[action] { Text(message).bvFont(.footnote).foregroundStyle(.bvWarning) }
            if model.unavailableShortcutActions.contains(action) {
                Text("Another app uses this shortcut.").bvFont(.footnote).foregroundStyle(.bvWarning)
            }
        }
    }
}
