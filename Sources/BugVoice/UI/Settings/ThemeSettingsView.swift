import SwiftUI
import VoiceCore

struct ThemeSettingsView: View {
    @Bindable var model: AppModel
    @Environment(AppearanceStore.self) private var store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
                AppearanceCard(title: "Theme") {
                    RoundPills(items: [(.light,"Light"),(.dark,"Dark"),(.system,"Match macOS")], selection: $model.settings.appearance.mode)
                        .onChange(of: model.settings.appearance.mode) { _, mode in
                            if mode == .light && store.theme.isDark { model.settings.appearance.theme = model.settings.appearance.lightTheme }
                            if mode == .dark && !store.theme.isDark { model.settings.appearance.theme = model.settings.appearance.darkTheme }
                        }
                    if model.settings.appearance.mode == .system {
                        themePicker("Light theme", dark: false, selection: $model.settings.appearance.lightTheme)
                        themePicker("Dark theme", dark: true, selection: $model.settings.appearance.darkTheme)
                    }
                    ForEach([ThemeGroup.comfort, .dark, .light], id: \.self) { group in
                        Text(group == .comfort ? "Eye comfort" : group == .dark ? "Dark" : "Light").bvFont(.bodyStrong)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: store.scaled(150)))], spacing: LayoutTokens.spacing[1]) {
                            ForEach(ThemeCatalog.all.filter { $0.group == group }, id: \.id) { spec in tile(spec) }
                        }
                    }
                }
                AppearanceCard(title: "Recording pill") {
                    RoundPills(items: [(.small,"Small"),(.medium,"Medium"),(.large,"Large")], selection: $model.settings.appearance.hudSize)
                    HStack(spacing: LayoutTokens.spacing[2]) {
                        hudPreview(dark: false)
                        hudPreview(dark: true)
                    }
                }
                AppearanceCard(title: "Icons") {
                    HStack { Text("App icon"); Spacer(); LogoCarousel(selection: $model.settings.appearance.appIcon, kind: .app) }
                    Divider().overlay(.bvSeparator)
                    HStack { Text("Menu-bar icon"); Spacer(); LogoCarousel(selection: $model.settings.appearance.menuBarIcon, kind: .menuBar) }
                }
                Button("Reset theme and icons") { model.settings.appearance.resetThemeAndIcons() }
            }.bvFont(.body).padding(LayoutTokens.spacing[0])
        }
    }
    private func themePicker(_ title: String, dark: Bool, selection: Binding<ThemeID>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ThemeCatalog.all.filter { $0.isDark == dark }, id: \.id) { Text($0.name).tag($0.id) }
        }
    }
    private func tile(_ spec: ThemeSpec) -> some View {
        let colors = BVTheme(spec)
        let selected = model.settings.appearance.mode == .system
            ? (spec.isDark ? model.settings.appearance.darkTheme : model.settings.appearance.lightTheme) == spec.id
            : model.settings.appearance.theme == spec.id
        return Button {
            if model.settings.appearance.mode == .system {
                if spec.isDark { model.settings.appearance.darkTheme = spec.id }
                else { model.settings.appearance.lightTheme = spec.id }
            } else {
                model.settings.appearance.theme = spec.id
                model.settings.appearance.mode = spec.isDark ? .dark : .light
            }
        } label: {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                HStack(spacing: LayoutTokens.spacing[1]) {
                    VStack(spacing: LayoutTokens.spacing[0]) {
                        RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).fill(colors.accent).frame(height: 8)
                        RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).fill(colors.secondaryText).frame(height: 4)
                    }.padding(LayoutTokens.spacing[1]).frame(width: 48).background(colors.sidebar)
                    VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                        RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).fill(colors.text).frame(height: 4)
                        RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).fill(colors.secondaryText).frame(height: 4)
                        RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).fill(colors.accent).frame(width: 24, height: 8)
                    }.padding(LayoutTokens.spacing[1])
                }.frame(height: 62).background(colors.background)
                Text(spec.name).bvFont(.footnote).multilineTextAlignment(.leading)
                Text(String(format: "%.1f:1", Contrast.ratio(spec.colors.secondaryText, spec.colors.background))).bvFont(.caption).foregroundStyle(.bvSecondary)
            }.padding(LayoutTokens.spacing[1]).bvCard()
                .overlay(RoundedRectangle(cornerRadius: LayoutTokens.cardRadius).stroke(selected ? AnyShapeStyle(.bvAccent) : AnyShapeStyle(.bvSeparator)))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func hudPreview(dark: Bool) -> some View {
        let stage = BVTheme(ThemeCatalog.spec(dark ? .bugVoiceDark : .bugVoiceLight))
        return HStack(spacing: LayoutTokens.spacing[1]) {
            Circle().fill(.bvRecording).frame(width: 8, height: 8)
            Text("Listening").bvFont(.body)
        }
        .padding(LayoutTokens.spacing[2] * model.settings.appearance.hudSize.factor)
        .background(.bvCard, in: Capsule()).overlay(Capsule().stroke(.bvSeparator))
        .frame(maxWidth: .infinity).padding(LayoutTokens.spacing[3])
        .background(stage.background, in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
    }
}
