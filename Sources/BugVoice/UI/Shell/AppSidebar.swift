import SwiftUI
import VoiceCore

struct AppSidebar: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @FocusState private var focused: Bool
    @State private var hovered: Page?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowButtonsSpace()
            HStack(spacing: LayoutTokens.spacing[1]) {
                if let icon = IconImages.appIcon(model.settings.appearance.appIcon) {
                    Image(nsImage: icon).resizable().frame(width: store.scaled(24), height: store.scaled(24))
                        .clipShape(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                }
                Text("BugVoice").bvFont(.title3)
            }.padding(LayoutTokens.spacing[3])
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                        ForEach(SidebarGroup.allCases.filter { $0 != .bottom }, id: \.self) { group in
                            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                                if let title = group.title {
                                    Text(title.uppercased()).bvFont(.caption).foregroundStyle(.bvSecondary)
                                        .padding(.horizontal, LayoutTokens.spacing[2])
                                        .padding(.top, LayoutTokens.spacing[2])
                                }
                                ForEach(group.pages) { row($0) }
                            }.accessibilityElement(children: .contain).accessibilityLabel(group.title ?? "")
                        }
                        Spacer(minLength: LayoutTokens.spacing[3])
                        ForEach(SidebarGroup.bottom.pages) { row($0) }
                    }
                    .padding(.horizontal, LayoutTokens.spacing[1])
                    .padding(.bottom, LayoutTokens.spacing[2])
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
            }
        }
        .background(.bvSidebar)
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
    }

    private func move(_ offset: Int) {
        let pages = SidebarGroup.allCases.flatMap(\.pages)
        guard let index = pages.firstIndex(of: model.page) else { return }
        model.page = pages[min(max(index + offset, 0), pages.count - 1)]
    }

    private func row(_ page: Page) -> some View {
        Button { model.page = page; focused = true } label: {
            HStack(spacing: LayoutTokens.spacing[1]) {
                Image(systemName: page.symbol).frame(width: store.scaled(20))
                Text(page.title).frame(maxWidth: .infinity, alignment: .leading)
                if page == .upload, let job = model.uploads?.active { UploadRing(progress: job.progress) }
            }
            .bvFont(model.page == page ? .bodyStrong : .body)
            .padding(.horizontal, LayoutTokens.spacing[2]).padding(.vertical, LayoutTokens.spacing[1])
            .background(model.page == page ? AnyShapeStyle(.bvAccentSoft) : hovered == page ? AnyShapeStyle(.bvHover) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).stroke(model.page == page ? store.theme.accent.opacity(0.55) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? page : nil }
        .accessibilityAddTraits(model.page == page ? .isSelected : [])
    }
}
