import SwiftUI
import VoiceCore

/// Every logo as a tile; click one to choose it.
struct LogoGrid: View {
    enum Kind { case app, menuBar }
    @Binding var selection: LogoID
    let kind: Kind
    @Environment(AppearanceStore.self) private var store

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: store.scaled(110)))], spacing: LayoutTokens.spacing[1]) {
            ForEach(LogoID.allCases, id: \.self) { tile($0) }
        }
    }

    private func tile(_ id: LogoID) -> some View {
        let selected = id == selection
        return Button { selection = id } label: {
            VStack(spacing: LayoutTokens.spacing[1]) {
                preview(id).frame(height: kind == .app ? 56 : 32)
                Text(id.displayName).bvFont(.footnote).fontWeight(selected ? .semibold : .regular)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(LayoutTokens.spacing[1])
            .background(selected ? AnyShapeStyle(.bvAccentSoft) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: LayoutTokens.cardRadius)
                .stroke(selected ? AnyShapeStyle(.bvAccent) : AnyShapeStyle(.bvSeparator), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(id.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func preview(_ id: LogoID) -> some View {
        if kind == .app, let image = IconImages.appIcon(id) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(nsImage: BrandImages.menuBar(logo: id, badge: false))
                .renderingMode(.template).foregroundStyle(.bvText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.bvBackground, in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
        }
    }
}
