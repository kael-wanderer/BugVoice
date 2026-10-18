import AppKit
import SwiftUI
import VoiceCore

/// What a formatting button asks the editor to do.
enum MarkdownToolbarCommand {
    case inline(InlineMarker)
    case underline
    case line(LineFormat)
    case indent(outdent: Bool)
    case link
    case table(columns: Int, rows: Int)
}

/// The Formatting bar: H1 H2 · B I U S code · lists · quote indent · link table.
/// Every button writes Markdown and is one edit.
struct MarkdownToolbar: View {
    @Environment(AppearanceStore.self) private var store
    let run: (MarkdownToolbarCommand) -> Void
    @State private var pickingTable = false

    var body: some View {
        // The compact 440 pt window cannot fit the full row: buttons narrow first, then the bar takes two rows.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: LayoutTokens.spacing[0]) { headings(26); divider(4); inline(26); divider(4); lists(26); divider(4); blocks(26) }
            HStack(spacing: LayoutTokens.spacing[0]) { headings(22); divider(2); inline(22); divider(2); lists(22); divider(2); blocks(22) }
            VStack(spacing: LayoutTokens.spacing[0]) {
                HStack(spacing: LayoutTokens.spacing[0]) { headings(26); divider(4); inline(26) }
                HStack(spacing: LayoutTokens.spacing[0]) { lists(26); divider(4); blocks(26) }
            }
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func headings(_ width: CGFloat) -> some View {
        button("H1", help: "Heading 1", width: width) { run(.line(.heading(1))) }
        button("H2", help: "Heading 2", width: width) { run(.line(.heading(2))) }
    }

    @ViewBuilder private func inline(_ width: CGFloat) -> some View {
        symbol("bold", help: "Bold (⌘B)", width: width) { run(.inline(.bold)) }
            .keyboardShortcut("b", modifiers: .command)
        symbol("italic", help: "Italic (⌘I)", width: width) { run(.inline(.italic)) }
            .keyboardShortcut("i", modifiers: .command)
        symbol("underline", help: "Underline (⌘U)", width: width) { run(.underline) }
            .keyboardShortcut("u", modifiers: .command)
        symbol("strikethrough", help: "Strikethrough", width: width) { run(.inline(.strike)) }
        symbol("chevron.left.forwardslash.chevron.right", help: "Code", width: width) { run(.inline(.code)) }
    }

    @ViewBuilder private func lists(_ width: CGFloat) -> some View {
        symbol("list.bullet", help: "Bulleted list", width: width) { run(.line(.bullet)) }
        symbol("list.number", help: "Numbered list", width: width) { run(.line(.numbered)) }
        symbol("checklist", help: "Checklist", width: width) { run(.line(.task)) }
    }

    @ViewBuilder private func blocks(_ width: CGFloat) -> some View {
        symbol("text.quote", help: "Quote", width: width) { run(.line(.quote)) }
        symbol("increase.indent", help: "Indent (Shift-click to outdent)", width: width) {
            run(.indent(outdent: NSEvent.modifierFlags.contains(.shift)))
        }
        divider(width < 26 ? 2 : 4)
        symbol("link", help: "Link (⌘K)", width: width) { run(.link) }
            .keyboardShortcut("k", modifiers: .command)
        symbol("tablecells", help: "Table", width: width) { pickingTable = true }
            .popover(isPresented: $pickingTable, arrowEdge: .top) {
                TableSizePicker { columns, rows in
                    pickingTable = false
                    run(.table(columns: columns, rows: rows))
                }
            }
    }

    private func divider(_ padding: CGFloat) -> some View {
        Divider().frame(height: 16).padding(.horizontal, padding)
    }

    private func button(_ title: String, help: String, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).bvFont(.footnote).frame(width: width, height: 24)
        }
        .help(help)
        .accessibilityLabel(help)
    }

    private func symbol(_ name: String, help: String, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).frame(width: width, height: 24)
        }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// An 8 × 8 grid: hover picks columns × rows, click inserts.
struct TableSizePicker: View {
    @Environment(AppearanceStore.self) private var store
    static let size = 8
    let pick: (_ columns: Int, _ rows: Int) -> Void
    @State private var hovered = (columns: 1, rows: 1)

    var body: some View {
        VStack(spacing: LayoutTokens.spacing[1]) {
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(1...Self.size, id: \.self) { row in
                    GridRow {
                        ForEach(1...Self.size, id: \.self) { column in
                            let on = column <= hovered.columns && row <= hovered.rows
                            RoundedRectangle(cornerRadius: LayoutTokens.controlRadius)
                                .stroke(on ? store.theme.text : store.theme.secondaryText.opacity(0.35), lineWidth: on ? 1.5 : 1)
                                .background(on ? store.theme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                                .onHover { inside in if inside { hovered = (column, row) } }
                                .onTapGesture { pick(column, row) }
                        }
                    }
                }
            }
            Text("\(hovered.columns) × \(hovered.rows)")
                .bvFont(.footnote)
                .foregroundStyle(.bvSecondary)
                .monospacedDigit()
        }
        .padding(LayoutTokens.spacing[2])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Table size, \(hovered.columns) columns by \(hovered.rows) rows")
        .accessibilityAction { pick(hovered.columns, hovered.rows) }
    }
}
