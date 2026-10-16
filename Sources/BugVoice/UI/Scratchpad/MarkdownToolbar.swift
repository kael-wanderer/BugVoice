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
    let run: (MarkdownToolbarCommand) -> Void
    @State private var pickingTable = false

    var body: some View {
        HStack(spacing: 2) {
            button("H1", help: "Heading 1") { run(.line(.heading(1))) }
            button("H2", help: "Heading 2") { run(.line(.heading(2))) }
            divider
            symbol("bold", help: "Bold (⌘B)") { run(.inline(.bold)) }
                .keyboardShortcut("b", modifiers: .command)
            symbol("italic", help: "Italic (⌘I)") { run(.inline(.italic)) }
                .keyboardShortcut("i", modifiers: .command)
            symbol("underline", help: "Underline (⌘U)") { run(.underline) }
                .keyboardShortcut("u", modifiers: .command)
            symbol("strikethrough", help: "Strikethrough") { run(.inline(.strike)) }
            symbol("chevron.left.forwardslash.chevron.right", help: "Code") { run(.inline(.code)) }
            divider
            symbol("list.bullet", help: "Bulleted list") { run(.line(.bullet)) }
            symbol("list.number", help: "Numbered list") { run(.line(.numbered)) }
            symbol("checklist", help: "Checklist") { run(.line(.task)) }
            divider
            symbol("text.quote", help: "Quote") { run(.line(.quote)) }
            symbol("increase.indent", help: "Indent (Shift-click to outdent)") {
                run(.indent(outdent: NSEvent.modifierFlags.contains(.shift)))
            }
            divider
            symbol("link", help: "Link (⌘K)") { run(.link) }
                .keyboardShortcut("k", modifiers: .command)
            symbol("tablecells", help: "Table") { pickingTable = true }
                .popover(isPresented: $pickingTable, arrowEdge: .top) {
                    TableSizePicker { columns, rows in
                        pickingTable = false
                        run(.table(columns: columns, rows: rows))
                    }
                }
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Divider().frame(height: 16).padding(.horizontal, 4)
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

/// An 8 × 8 grid: hover picks columns × rows, click inserts.
struct TableSizePicker: View {
    static let size = 8
    let pick: (_ columns: Int, _ rows: Int) -> Void
    @State private var hovered = (columns: 1, rows: 1)

    var body: some View {
        VStack(spacing: 8) {
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(1...Self.size, id: \.self) { row in
                    GridRow {
                        ForEach(1...Self.size, id: \.self) { column in
                            let on = column <= hovered.columns && row <= hovered.rows
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(on ? Color.primary : Color.secondary.opacity(0.35), lineWidth: on ? 1.5 : 1)
                                .background(on ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 3))
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                                .onHover { inside in if inside { hovered = (column, row) } }
                                .onTapGesture { pick(column, row) }
                        }
                    }
                }
            }
            Text("\(hovered.columns) × \(hovered.rows)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Table size, \(hovered.columns) columns by \(hovered.rows) rows")
        .accessibilityAction { pick(hovered.columns, hovered.rows) }
    }
}
