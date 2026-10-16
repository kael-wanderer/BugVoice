import SwiftUI
import VoiceCore

/// What a toolbar button asks the editor to do.
enum MarkdownToolbarCommand {
    case inline(InlineMarker)
    case line(LineFormat)
    case link
}

/// H1 H2 · B I S · lists · quote code link. Each button is one edit.
struct MarkdownToolbar: View {
    let run: (MarkdownToolbarCommand) -> Void

    var body: some View {
        HStack(spacing: 2) {
            button("H1", help: "Heading 1") { run(.line(.heading(1))) }
            button("H2", help: "Heading 2") { run(.line(.heading(2))) }
            Divider().frame(height: 16).padding(.horizontal, 4)
            symbol("bold", help: "Bold (⌘B)") { run(.inline(.bold)) }
                .keyboardShortcut("b", modifiers: .command)
            symbol("italic", help: "Italic (⌘I)") { run(.inline(.italic)) }
                .keyboardShortcut("i", modifiers: .command)
            symbol("strikethrough", help: "Strikethrough") { run(.inline(.strike)) }
            Divider().frame(height: 16).padding(.horizontal, 4)
            symbol("list.bullet", help: "Bulleted list") { run(.line(.bullet)) }
            symbol("list.number", help: "Numbered list") { run(.line(.numbered)) }
            symbol("checklist", help: "Checklist") { run(.line(.task)) }
            Divider().frame(height: 16).padding(.horizontal, 4)
            symbol("text.quote", help: "Quote") { run(.line(.quote)) }
            symbol("chevron.left.forwardslash.chevron.right", help: "Code") { run(.inline(.code)) }
            symbol("link", help: "Link (⌘K)") { run(.link) }
                .keyboardShortcut("k", modifiers: .command)
        }
        .buttonStyle(.borderless)
    }

    private func button(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 24)
        }
        .help(help)
        .accessibilityLabel(help)
    }

    private func symbol(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).frame(width: 26, height: 24)
        }
        .help(help)
        .accessibilityLabel(help)
    }
}
