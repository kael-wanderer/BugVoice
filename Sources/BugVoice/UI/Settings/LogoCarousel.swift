import SwiftUI
import VoiceCore

struct LogoCarousel: View {
    enum Kind { case app, menuBar }
    @Binding var selection: LogoID
    let kind: Kind
    @Environment(AppearanceStore.self) private var store

    var body: some View {
        VStack(spacing: LayoutTokens.spacing[1]) {
            HStack(spacing: LayoutTokens.spacing[2]) {
                Button("‹") { step(-1) }.accessibilityLabel("Previous icon")
                Group {
                    if kind == .app, let image = IconImages.appIcon(selection) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 112, height: 112)
                    } else {
                        VStack(spacing: LayoutTokens.spacing[1]) {
                            glyph(dark: false)
                            glyph(dark: true)
                        }.frame(width: 112)
                    }
                }
                Button("›") { step(1) }.accessibilityLabel("Next icon")
            }
            Text(selection.displayName).bvFont(.bodyStrong)
            HStack(spacing: LayoutTokens.spacing[0]) {
                ForEach(LogoID.allCases, id: \.self) { id in
                    Circle().fill(id == selection ? AnyShapeStyle(.bvAccent) : AnyShapeStyle(.bvSeparator))
                        .frame(width: 6, height: 6)
                }
            }
        }.bvFont(.body)
    }
    private func glyph(dark: Bool) -> some View {
        let theme = BVTheme(ThemeCatalog.spec(dark ? .bugVoiceDark : .bugVoiceLight))
        return Image(nsImage: BrandImages.menuBar(logo: selection, badge: false))
            .renderingMode(.template).foregroundStyle(theme.text)
            .frame(maxWidth: .infinity).padding(LayoutTokens.spacing[3])
            .background(theme.background, in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
    }
    private func step(_ delta: Int) {
        let all = LogoID.allCases
        selection = all[(selection.symbolNumber - 1 + delta + all.count) % all.count]
    }
}
