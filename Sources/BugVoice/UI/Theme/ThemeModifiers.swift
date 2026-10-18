import SwiftUI
import VoiceCore

private struct BVThemeKey: EnvironmentKey {
    static let defaultValue = BVTheme(ThemeCatalog.spec(.bugVoiceDark))
}
extension EnvironmentValues {
    var bvTheme: BVTheme {
        get { self[BVThemeKey.self] }
        set { self[BVThemeKey.self] = newValue }
    }
}
struct BVColorStyle: ShapeStyle {
    let key: KeyPath<BVTheme, Color> & Sendable
    func resolve(in environment: EnvironmentValues) -> Color { environment.bvTheme[keyPath: key] }
}
extension ShapeStyle where Self == BVColorStyle {
    static var bvBackground: BVColorStyle { BVColorStyle(key: \.background) }
    static var bvSidebar: BVColorStyle { BVColorStyle(key: \.sidebar) }
    static var bvCard: BVColorStyle { BVColorStyle(key: \.card) }
    static var bvSeparator: BVColorStyle { BVColorStyle(key: \.separator) }
    static var bvText: BVColorStyle { BVColorStyle(key: \.text) }
    static var bvSecondary: BVColorStyle { BVColorStyle(key: \.secondaryText) }
    static var bvAccent: BVColorStyle { BVColorStyle(key: \.accent) }
    static var bvHover: BVColorStyle { BVColorStyle(key: \.hover) }
    static var bvAccentSoft: BVColorStyle { BVColorStyle(key: \.accentSoft) }
    static var bvOnAccent: BVColorStyle { BVColorStyle(key: \.onAccent) }
    static var bvRecording: BVColorStyle { BVColorStyle(key: \.recording) }
    static var bvSuccess: BVColorStyle { BVColorStyle(key: \.success) }
    static var bvWarning: BVColorStyle { BVColorStyle(key: \.warning) }
}
private struct BVFontModifier: ViewModifier {
    @Environment(AppearanceStore.self) private var store
    let token: TextToken
    var code = false
    func body(content: Content) -> some View {
        content.font(code ? store.type.codeFont(token) : store.type.font(token))
    }
}
extension View {
    func bvFont(_ token: TextToken) -> some View { modifier(BVFontModifier(token: token)) }
    func bvCode(_ token: TextToken) -> some View { modifier(BVFontModifier(token: token, code: true)) }
    func bvCard(radius: CGFloat = LayoutTokens.cardRadius) -> some View {
        background(.bvCard, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(.bvSeparator, lineWidth: 1))
    }
    func bvTheme(_ store: AppearanceStore) -> some View {
        modifier(BVThemeModifier(store: store))
    }
}

private struct BVThemeModifier: ViewModifier {
    let store: AppearanceStore
    func body(content: Content) -> some View {
        content.environment(store).environment(\.bvTheme, store.theme)
            .font(store.type.font(.body))
            .tint(store.theme.accent)
            .preferredColorScheme(store.theme.isDark ? .dark : .light)
            .controlSize(LayoutTokens.usesLargeControls(scale: store.settings.textScale) ? .large : .regular)
            .foregroundStyle(store.theme.text)
            .background(store.theme.background)
    }
}
