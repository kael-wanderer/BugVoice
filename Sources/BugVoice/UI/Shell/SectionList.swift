import SwiftUI
import VoiceCore

struct SectionList<Value: Hashable>: View {
    struct Group { var title: String?; var items: [(Value, String)] }
    @Environment(AppearanceStore.self) private var store
    let label: String
    let groups: [Group]
    @Binding var selection: Value
    @State private var hovered: Value?

    init(_ label: String, groups: [Group], selection: Binding<Value>) {
        self.label = label; self.groups = groups; self._selection = selection
    }
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
            ForEach(groups.indices, id: \.self) { index in
                if let title = groups[index].title {
                    Text(title.uppercased()).bvFont(.caption).foregroundStyle(.bvSecondary)
                        .padding(.horizontal, LayoutTokens.spacing[2]).padding(.top, LayoutTokens.spacing[3])
                }
                ForEach(groups[index].items, id: \.0) { value, title in
                    Button { selection = value } label: {
                        Text(title).bvFont(value == selection ? .bodyStrong : .body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, LayoutTokens.spacing[2]).padding(.vertical, LayoutTokens.spacing[1])
                            .background(value == selection ? AnyShapeStyle(.bvAccentSoft) : value == hovered ? AnyShapeStyle(.bvHover) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                            .overlay(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).stroke(value == selection ? store.theme.accent.opacity(0.55) : .clear))
                    }
                    .buttonStyle(.plain).onHover { hovered = $0 ? value : nil }
                    .accessibilityAddTraits(value == selection ? .isSelected : [])
                }
            }
        }
        .frame(width: ShellLayout.sectionListWidth(scale: store.settings.textScale), alignment: .leading)
        .accessibilityElement(children: .contain).accessibilityLabel(label)
    }
}
