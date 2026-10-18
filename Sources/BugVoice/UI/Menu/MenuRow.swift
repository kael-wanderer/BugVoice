import SwiftUI
import VoiceCore

/// Shared look of a full-width popover row: hover fill when highlighted.
private struct MenuRowChrome: ViewModifier {
    let highlighted: Bool
    let onHover: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, LayoutTokens.spacing[1])
            .padding(.vertical, LayoutTokens.spacing[0])
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? AnyShapeStyle(.bvHover) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
            .contentShape(Rectangle())
            .onHover(perform: onHover)
    }
}

/// Plain row: optional SF Symbol, title, optional right-aligned hint.
struct MenuRow: View {
    @Environment(AppearanceStore.self) private var store
    var icon: String?
    let title: String
    var hint: String?
    let highlighted: Bool
    let onHover: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: LayoutTokens.spacing[1]) {
                Group {
                    if let icon { Image(systemName: icon) } else { Color.clear }
                }
                .foregroundStyle(.bvSecondary)
                .frame(width: store.scaled(16))
                Text(title).bvFont(.body)
                Spacer(minLength: LayoutTokens.spacing[1])
                if let hint { Text(hint).bvFont(.footnote).foregroundStyle(.bvSecondary) }
            }
            .modifier(MenuRowChrome(highlighted: highlighted, onHover: onHover))
        }
        .buttonStyle(.plain)
    }
}

/// Row that opens a submenu in place; shows › on the right.
struct MenuSubmenuRow: View {
    var icon: String?
    let title: String
    let highlighted: Bool
    let onHover: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        MenuRow(icon: icon, title: title, hint: "›", highlighted: highlighted, onHover: onHover, action: action)
    }
}

/// Row with a switch on the right.
struct MenuSwitchRow: View {
    let title: String
    @Binding var isOn: Bool
    let highlighted: Bool
    let onHover: (Bool) -> Void

    var body: some View {
        Toggle(isOn: $isOn) { Text(title).bvFont(.body) }
            .toggleStyle(.switch)
            .modifier(MenuRowChrome(highlighted: highlighted, onHover: onHover))
    }
}

/// One choice in a group; a check mark marks the selected one.
struct MenuCheckRow: View {
    @Environment(AppearanceStore.self) private var store
    let title: String
    let checked: Bool
    let highlighted: Bool
    let onHover: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: LayoutTokens.spacing[1]) {
                Group {
                    if checked { Image(systemName: "checkmark") } else { Color.clear }
                }
                .frame(width: store.scaled(16))
                Text(title).bvFont(.body)
                Spacer(minLength: 0)
            }
            .modifier(MenuRowChrome(highlighted: highlighted, onHover: onHover))
        }
        .buttonStyle(.plain)
    }
}

/// Small uppercase label above a group of check rows.
struct MenuGroupHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .bvFont(.caption)
            .foregroundStyle(.bvSecondary)
            .padding(.horizontal, LayoutTokens.spacing[1])
            .padding(.top, LayoutTokens.spacing[1])
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Thin line between groups of rows.
struct MenuSeparator: View {
    var body: some View {
        Rectangle().fill(.bvSeparator).frame(height: 1)
            .padding(.horizontal, LayoutTokens.spacing[0])
            .padding(.vertical, LayoutTokens.spacing[0])
    }
}

/// Bordered button used in the grid, the meeting strip and the last dictation block.
/// Highlighted shows a 2 pt accent outline.
struct MenuButton<Label: View>: View {
    var small = false
    var primary = false
    var fillsWidth = false
    let highlighted: Bool
    let onHover: (Bool) -> Void
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            label()
                .bvFont(small ? .footnote : .body)
                .fontWeight(primary ? .semibold : nil)
                .lineLimit(1)
                .padding(.horizontal, small ? LayoutTokens.spacing[1] : LayoutTokens.spacing[2])
                .padding(.vertical, small ? LayoutTokens.spacing[0] : LayoutTokens.spacing[1])
                .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
                .foregroundStyle(primary ? AnyShapeStyle(.bvOnAccent) : AnyShapeStyle(.bvText))
                .background(primary ? AnyShapeStyle(.bvAccent) : AnyShapeStyle(.bvBackground),
                            in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius)
                    .stroke(primary ? AnyShapeStyle(.bvAccent) : AnyShapeStyle(.bvSeparator), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius + 1)
                    .stroke(.bvAccent, lineWidth: 2).padding(-2).opacity(highlighted ? 1 : 0))
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
    }
}
