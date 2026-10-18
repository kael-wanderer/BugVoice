import SwiftUI
import VoiceCore

/// Doc view: the note rendered, read only. Task boxes can be ticked.
struct MarkdownDocView: View {
    @Environment(AppearanceStore.self) private var store
    let text: String
    let onToggleTask: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: store.readingWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LayoutTokens.spacing[4])
            .padding(.vertical, LayoutTokens.spacing[3])
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else { return .discarded }
            return .systemAction(url)
        })
    }

    @ViewBuilder private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text).bvFont(level == 1 ? .title1 : level == 2 ? .title2 : .title3)
                .padding(.top, LayoutTokens.spacing[0])
        case .paragraph(let text):
            inline(text)
        case .bullet(let indent, let text):
            item(indent: indent, marker: Text("•"), text: text)
        case .numbered(let indent, let number, let text):
            item(indent: indent, marker: Text(number).monospacedDigit(), text: text)
        case .task(let indent, let checked, let text, let line):
            HStack(alignment: .firstTextBaseline, spacing: LayoutTokens.spacing[1]) {
                Button { onToggleTask(line) } label: {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? store.theme.accent : store.theme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(checked ? "Untick task" : "Tick task")
                inline(text)
                    .strikethrough(checked)
                    .foregroundStyle(checked ? store.theme.secondaryText : store.theme.text)
            }
            .padding(.leading, CGFloat(indent) * LayoutTokens.spacing[3])
        case .quote(let text):
            HStack(spacing: LayoutTokens.spacing[1]) {
                Rectangle().fill(store.theme.secondaryText.opacity(0.4)).frame(width: 3)
                inline(text).italic().foregroundStyle(.bvSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let text):
            Text(text)
                .bvCode(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(LayoutTokens.spacing[1])
                .background(store.theme.secondaryText.opacity(0.1), in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
        case .rule:
            Divider()
        case .table(let header, let rows):
            table(header: header, rows: rows)
        }
    }

    private func table(header: [String], rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                    tableCell(cell).fontWeight(.semibold)
                }
            }
            .background(store.theme.secondaryText.opacity(0.08))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in tableCell(cell) }
                }
            }
        }
        .overlay(Rectangle().stroke(store.theme.secondaryText.opacity(0.3)))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tableCell(_ text: String) -> some View {
        inline(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LayoutTokens.spacing[1])
            .padding(.vertical, LayoutTokens.spacing[0])
            .overlay(Rectangle().stroke(store.theme.secondaryText.opacity(0.2)))
    }

    private func item(indent: Int, marker: Text, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LayoutTokens.spacing[1]) {
            marker.foregroundStyle(.bvSecondary)
            inline(text)
        }
        .padding(.leading, CGFloat(indent) * LayoutTokens.spacing[3])
    }

    /// Inline Markdown through Foundation; raw text when it does not parse.
    /// `<u>`…`</u>` is underlined; the tags are not shown.
    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var result = AttributedString()
        for (index, piece) in text.components(separatedBy: "<u>").enumerated() {
            let parts = index == 0 ? [piece] : piece.components(separatedBy: "</u>")
            for (offset, part) in parts.enumerated() where !part.isEmpty {
                var attributed = (try? AttributedString(markdown: part, options: options)) ?? AttributedString(part)
                if index > 0, offset == 0, parts.count > 1 { attributed.underlineStyle = .single }
                result += attributed
            }
        }
        return Text(result)
    }
}
