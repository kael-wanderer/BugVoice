import Foundation
import Testing
@testable import VoiceCore

struct AppearanceSettingsTests {
    @Test func defaults() {
        let settings = AppearanceSettings()
        #expect(settings.textScale == 100)
        #expect(settings.font == .system)
        #expect(settings.codeFont == .sfMono)
        #expect(settings.lineSpacing == .normal)
        #expect(settings.readingWidth == .medium)
        #expect(settings.mode == .dark)
        #expect(settings.theme == .bugVoiceDark)
        #expect(settings.lightTheme == .bugVoiceLight)
        #expect(settings.darkTheme == .bugVoiceDark)
        #expect(settings.hudSize == .medium)
        #expect(settings.appIcon == .antennaMic)
        #expect(settings.menuBarIcon == .antennaMic)
    }

    @Test func roundTrip() throws {
        let value = AppearanceSettings(textScale: 130, font: .custom("Inter"), codeFont: .menlo, mode: .system)
        let data = try JSONEncoder().encode(value)
        #expect(String(decoding: data, as: UTF8.self).contains("custom:Inter"))
        #expect(try JSONDecoder().decode(AppearanceSettings.self, from: data) == value)
    }

    @Test func missingAppearanceKeyLoadsDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"hotkey":"rightOption"}"#.utf8))
        #expect(settings.appearance == AppearanceSettings())
        #expect(settings.hotkey == .rightOption)
    }

    @Test func unknownThemeFallsBackPerField() throws {
        let settings = try JSONDecoder().decode(AppearanceSettings.self, from: Data(#"{"theme":"neon","darkTheme":"nord","textScale":130}"#.utf8))
        #expect(settings.theme == .bugVoiceDark)
        #expect(settings.darkTheme == .nord)
        #expect(settings.textScale == 130)
    }

    @Test func unknownFontFallsBack() throws {
        let settings = try JSONDecoder().decode(AppearanceSettings.self, from: Data(#"{"font":"comic"}"#.utf8))
        #expect(settings.font == .system)
    }

    @Test func scaleIsClampedAndStepped() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(AppearanceSettings.self, from: Data(#"{"textScale":85}"#.utf8)).textScale == 90)
        #expect(try decoder.decode(AppearanceSettings.self, from: Data(#"{"textScale":163}"#.utf8)).textScale == 160)
        #expect(try decoder.decode(AppearanceSettings.self, from: Data(#"{"textScale":102}"#.utf8)).textScale == 100)
        #expect(AppearanceSettings.normalizedScale(117) == 115)
    }

    @Test func stepTextScale() {
        var settings = AppearanceSettings()
        settings.stepTextScale(by: 10)
        #expect(settings.textScale == 110)
        settings.textScale = 155
        settings.stepTextScale(by: 10)
        #expect(settings.textScale == 160)
        settings.textScale = 95
        settings.stepTextScale(by: -10)
        #expect(settings.textScale == 90)
        settings.textScale = 160
        settings.stepTextScale(by: 10)
        #expect(settings.textScale == 160)
        settings.resetTextScale()
        #expect(settings.textScale == 100)
    }

    @Test func resolvedTheme() {
        var settings = AppearanceSettings(mode: .dark, theme: .nord)
        #expect(settings.resolvedTheme(systemIsDark: false) == .nord)
        #expect(settings.resolvedTheme(systemIsDark: true) == .nord)
        settings.mode = .light
        settings.theme = .sepia
        #expect(settings.resolvedTheme(systemIsDark: false) == .sepia)
        settings.mode = .system
        #expect(settings.resolvedTheme(systemIsDark: true) == settings.darkTheme)
        #expect(settings.resolvedTheme(systemIsDark: false) == settings.lightTheme)
    }

    @Test func resetEditingKeepsTheme() {
        var settings = AppearanceSettings()
        settings.textScale = 130
        settings.theme = .nord
        settings.resetEditing()
        #expect(settings.textScale == 100)
        #expect(settings.theme == .nord)
    }

    @Test func logoOrder() {
        #expect(LogoID.allCases.count == 15)
        #expect(LogoID.waveBug.symbolNumber == 1)
        #expect(LogoID.voiceV.symbolNumber == 15)
        #expect(LogoID.nonLa.displayName == "Nón Lá")
    }
}
