import SwiftUI
import VoiceCore

struct EditingSettingsView: View {
    @Bindable var model: AppModel
    @Environment(AppearanceStore.self) private var store
    @State private var previewToggle = true
    @State private var pickingCode = false
    @State private var showFonts = false
    @State private var family = ""
    private var fonts: [(AppFont, String)] {
        var items: [(AppFont, String)] = [(.system,"System"),(.rounded,"SF Rounded"),(.serif,"New York")]
        if FontRegistry.hyperlegibleAvailable { items.append((.hyperlegible,"Atkinson Hyperlegible Next")) }
        items.append((.monospaced,"SF Mono"))
        if case .custom(let name) = model.settings.appearance.font { items.append((.custom(name),name)) }
        return items
    }
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
                AppearanceCard(title: "Preview") {
                    Text("Product review").bvFont(.title2)
                    Text("One text size for every screen.\nTiếng Việt có dấu: ẩ ữ ộ đ ơ ư").bvFont(.reading)
                        .lineSpacing(store.type.nsFont(.reading).pointSize * (store.lineSpacingMultiple - 1))
                    Text("swift test --filter ThemeCatalogTests").bvCode(.footnote)
                    HStack(spacing: LayoutTokens.spacing[1]) {
                        Button("Save") {}.buttonStyle(.borderedProminent)
                        Button("Cancel") {}
                        Toggle("Preview", isOn: $previewToggle)
                        Text("Work style").bvFont(.footnote).padding(LayoutTokens.spacing[0]).background(.bvAccentSoft, in: Capsule())
                    }
                }
                AppearanceCard(title: "Text") {
                    Text("Text size").bvFont(.bodyStrong)
                    HStack(spacing: LayoutTokens.spacing[1]) {
                        Button("A−") { model.settings.appearance.stepTextScale(by: -10) }
                        Slider(value: Binding(get: { Double(model.settings.appearance.textScale) }, set: { model.settings.appearance.textScale = Int($0) }), in: 90...160, step: 5).accessibilityLabel("Text size")
                        Button("A+") { model.settings.appearance.stepTextScale(by: 10) }
                        Text("\(model.settings.appearance.textScale)%").bvFont(.bodyStrong).frame(width: store.scaled(52))
                    }
                    Text("Font").bvFont(.bodyStrong)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: store.scaled(165)))], spacing: LayoutTokens.spacing[1]) {
                        ForEach(fonts, id: \.1) { font, title in
                            Button { model.settings.appearance.font = font } label: {
                                VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                                    Text("Aa").bvFont(.stat)
                                    Text("Chữ Việt rõ ràng").bvFont(.body)
                                    Text(title).bvFont(.footnote).foregroundStyle(.bvSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(LayoutTokens.spacing[2])
                                .background(.bvBackground, in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
                                .overlay(RoundedRectangle(cornerRadius: LayoutTokens.cardRadius).stroke(font == model.settings.appearance.font ? AnyShapeStyle(.bvAccent) : AnyShapeStyle(.bvSeparator)))
                                .environment(AppearanceStore.preview(settings: model.settings.appearance, font: font))
                            }.buttonStyle(.plain)
                        }
                        Button("Other font…") { pickingCode = false; showFonts = true }
                    }
                    Picker("Code font", selection: Binding(get: {
                        switch model.settings.appearance.codeFont {
                        case .sfMono: "sfMono"
                        case .menlo: "menlo"
                        case .custom(let name): name
                        }
                    }, set: { value in
                        model.settings.appearance.codeFont = value == "sfMono" ? .sfMono : value == "menlo" ? .menlo : .custom(value)
                    })) {
                        Text("SF Mono").tag("sfMono")
                        Text("Menlo").tag("menlo")
                        if case .custom(let name) = model.settings.appearance.codeFont { Text(name).tag(name) }
                    }
                    Button("Other code font…") { pickingCode = true; showFonts = true }
                    Text("Line spacing").bvFont(.bodyStrong)
                    Picker("Line spacing", selection: $model.settings.appearance.lineSpacing) {
                        Text("Normal").tag(LineSpacing.normal)
                        Text("Relaxed").tag(LineSpacing.relaxed)
                        Text("Loose").tag(LineSpacing.loose)
                    }.pickerStyle(.segmented)
                    Text("Reading width").bvFont(.bodyStrong)
                    Picker("Reading width", selection: $model.settings.appearance.readingWidth) {
                        Text("Narrow").tag(ReadingWidth.narrow)
                        Text("Medium").tag(ReadingWidth.medium)
                        Text("Wide").tag(ReadingWidth.wide)
                    }.pickerStyle(.segmented)
                }
                Button("Reset editing") { model.settings.appearance.resetEditing() }
            }.bvFont(.body).padding(LayoutTokens.spacing[0])
        }
        .sheet(isPresented: $showFonts) {
            VStack(spacing: LayoutTokens.spacing[3]) {
                Text("Choose a font family").bvFont(.title2)
                Picker("Font", selection: $family) {
                    Text("Choose…").tag("")
                    ForEach(FontRegistry.families, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Button("Cancel") { showFonts = false }
                    Button("Choose") {
                        if pickingCode { model.settings.appearance.codeFont = .custom(family) }
                        else { model.settings.appearance.font = .custom(family) }
                        showFonts = false
                    }.disabled(family.isEmpty)
                }
            }.bvFont(.body).padding(LayoutTokens.spacing[4]).frame(width: store.scaled(360))
        }
    }
}

extension AppearanceStore {
    static func preview(settings: AppearanceSettings, font: AppFont) -> AppearanceStore {
        let store = AppearanceStore()
        var copy = settings
        copy.font = font
        store.apply(copy)
        return store
    }
}
