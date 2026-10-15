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

/// A secret field for the saved key `account`. Edits stay in local state;
/// the key is written once, on Return, when the field loses focus or
/// when it goes away. Callers key the view by `account` (`.id(account)`) so a
/// pending edit is committed to the old account before the account changes.
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
            .onAppear { text = model.credentials.read(account) ?? "" }
            .onDisappear(perform: commit)
    }

    private func commit() {
        guard text != (model.credentials.read(account) ?? "") else { return }
        if model.saveKey(text, account: account) { onCommit() }
    }
}

/// A panel of setting rows, the same card the Style, Dictionary and Insights
/// pages use, so every page lines up at full width.
struct SettingsCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline) }
            content
        }
        .insightsCard()
    }
}

/// A label on the left and its control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 16)
            control
        }
    }
}

/// A switch with its label on the left, like a grouped Form toggle.
struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

/// A scrolling column of cards, the body of every Settings tab.
struct SettingsScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(.vertical, 4)
        }
    }
}
