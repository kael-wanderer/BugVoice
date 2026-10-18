import Testing
@testable import VoiceCore

struct ThemeCatalogTests {
    @Test func hexParses() {
        #expect(abs(RGB(hex: "#202225")!.r - 32.0 / 255.0) < 0.001)
        #expect(RGB(hex: "zz") == nil)
        #expect(RGB(hex: "88aaff")?.hex == "#88aaff")
    }

    @Test func blackOnWhiteIs21() {
        #expect(abs(Contrast.ratio(.white, .black) - 21) < 0.01)
    }

    @Test func catalogShape() {
        #expect(ThemeCatalog.all.count == 21)
        #expect(ThemeCatalog.all.filter { $0.group == .comfort }.count == 4)
        #expect(ThemeCatalog.all.filter { $0.group == .dark }.count == 9)
        #expect(ThemeCatalog.all.filter { $0.group == .light }.count == 8)
        #expect(Set(ThemeCatalog.all.map(\.id)).count == ThemeCatalog.all.count)
        #expect(ThemeID.allCases.allSatisfy { id in ThemeCatalog.all.filter { $0.id == id }.count == 1 })
        #expect(ThemeCatalog.all.filter(\.isDark).map(\.id) == [
            .highContrastDark, .warmNight, .bugVoiceDark, .catppuccinMocha, .nord,
            .tokyoNight, .dracula, .oneDark, .gruvboxDark, .everforestDark, .solarizedDark,
        ])
    }

    @Test func textContrast() {
        for theme in ThemeCatalog.all {
            #expect(Contrast.ratio(theme.colors.text, theme.colors.background) >= 7, "\(theme.name) text on background")
            #expect(Contrast.ratio(theme.colors.text, theme.colors.card) >= 7, "\(theme.name) text on card")
        }
    }

    @Test func secondaryContrast() {
        for theme in ThemeCatalog.all {
            let minimum = theme.group == .comfort ? 7.0 : 4.5
            #expect(Contrast.ratio(theme.colors.secondaryText, theme.colors.background) >= minimum, "\(theme.name) secondary on background")
            #expect(Contrast.ratio(theme.colors.secondaryText, theme.colors.card) >= minimum, "\(theme.name) secondary on card")
        }
    }

    @Test func accentContrast() {
        for theme in ThemeCatalog.all {
            #expect(Contrast.ratio(theme.colors.accent, theme.colors.background) >= 3, "\(theme.name) accent on background")
        }
    }

    @Test func onAccentContrast() {
        for theme in ThemeCatalog.all {
            #expect(Contrast.ratio(theme.colors.onAccent, theme.colors.accent) >= 4.5, "\(theme.name) on accent")
        }
    }

    @Test func statusContrast() {
        for theme in ThemeCatalog.all {
            let status = theme.status
            for color in [status.recording, status.success, status.warning] {
                #expect(Contrast.ratio(color, theme.colors.background) >= 3, "\(theme.name) status on background")
                #expect(Contrast.ratio(color, theme.colors.card) >= 3, "\(theme.name) status on card")
            }
        }
    }

    @Test func onAccentPicksBlackForLightAccent() {
        #expect(ThemeCatalog.spec(.bugVoiceDark).colors.onAccent == .black)
        #expect(ThemeCatalog.spec(.bugVoiceLight).colors.onAccent == .white)
    }
}
