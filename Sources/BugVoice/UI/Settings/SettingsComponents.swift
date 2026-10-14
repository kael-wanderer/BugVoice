import SwiftUI
import VoiceCore

extension HotkeyKey {
    /// The one label for a hotkey, used in Settings and the menu.
    var displayName: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .rightCommand: "Right ⌘"
        case .fn: "Fn"
        case .f13: "F13"
        case .f14: "F14"
        case .f15: "F15"
        case .f16: "F16"
        case .f17: "F17"
        case .f18: "F18"
        case .f19: "F19"
        }
    }
}

/// A secret field for the Keychain item `account`. Edits stay in local state;
/// the Keychain is written once, on Return or when the field loses focus.
struct KeyField: View {
    let model: AppModel
    let title: String
    let account: String
    var onCommit: () -> Void = {}
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        SecureField(title, text: $text)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onChange(of: account) { _, _ in text = model.keychain.read(account) ?? "" }
            .onAppear { text = model.keychain.read(account) ?? "" }
            .onDisappear(perform: commit)
    }

    private func commit() {
        guard text != (model.keychain.read(account) ?? "") else { return }
        if model.saveKey(text, account: account) { onCommit() }
    }
}
