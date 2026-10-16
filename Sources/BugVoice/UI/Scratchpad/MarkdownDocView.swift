import SwiftUI
import VoiceCore

/// Doc view: the note rendered, read only. Task boxes can be ticked.
struct MarkdownDocView: View {
    let text: String
    let onToggleTask: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else { return .discarded }
            return .systemAction(url)
        })
    }

    @ViewBuilder private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text).font(level == 1 ? .system(size: 22, weight: .bold) : level == 2 ? .system(size: 18, weight: .bold) : .system(size: 15, weight: .semibold))
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            inline(text)
        case .bullet(let indent, let text):
            item(indent: indent, marker: Text("•"), text: text)
        case .numbered(let indent, let number, let text):
            item(indent: indent, marker: Text(number).monospacedDigit(), text: text)
        case .task(let indent, let checked, let text, let line):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button { onToggleTask(line) } label: {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(checked ? "Untick task" : "Tick task")
                inline(text)
                    .strikethrough(checked)
                    .foregroundStyle(checked ? .secondary : .primary)
            }
            .padding(.leading, CGFloat(indent) * 20)
        case .quote(let text):
            HStack(spacing: 10) {
                Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                inline(text).italic().foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let text):
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        case .rule:
            Divider()
        }
    }

    private func item(indent: Int, marker: Text, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker.foregroundStyle(.secondary)
            inline(text)
        }
        .padding(.leading, CGFloat(indent) * 20)
    }

    /// Inline Markdown through Foundation; raw text when it does not parse.
    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: text, options: options) { return Text(attributed) }
        return Text(text)
    }
}
