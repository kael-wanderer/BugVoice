import Testing
@testable import VoiceCore

struct LanguageRulesTests {
    @Test func defaultsMatchSpec() {
        #expect(AppLanguageRule.defaults.count == 9)
        #expect(AppLanguageRule.defaults.first { $0.id == "com.stablyai.orca" }?.language == .en)
        let web = AppLanguageRule.defaults.first { $0.id == "chatgpt.com" }
        #expect(web?.kind == .website)
        #expect(web?.language == .vi)
    }

    @Test func websiteBeatsApp() {
        var settings = SpeechSettings()
        settings.appLanguages = [
            AppLanguageRule(kind: .app, id: "com.google.Chrome", language: .en),
            AppLanguageRule(kind: .website, id: "chatgpt.com", language: .vi),
        ]
        let focus = FocusSnapshot(bundleID: "com.google.Chrome", url: "https://chatgpt.com/c/1")
        #expect(LanguageResolver(settings: settings).language(for: focus) == .vi)
    }

    @Test func subdomainMatches() {
        var settings = SpeechSettings()
        settings.appLanguages = [AppLanguageRule(kind: .website, id: "chatgpt.com", language: .vi)]
        let resolver = LanguageResolver(settings: settings)
        #expect(resolver.language(for: FocusSnapshot(url: "https://www.chatgpt.com/")) == .vi)
        #expect(resolver.language(for: FocusSnapshot(url: "https://notchatgpt.com/")) == .auto)
    }

    @Test func terminalPanelOnlyInPanel() {
        var settings = SpeechSettings()
        settings.appLanguages = [AppLanguageRule(kind: .terminalPanel, id: "com.microsoft.VSCode", language: .en)]
        let resolver = LanguageResolver(settings: settings)
        #expect(resolver.language(for: FocusSnapshot(bundleID: "com.microsoft.VSCode", isTerminalPanel: true)) == .en)
        #expect(resolver.language(for: FocusSnapshot(bundleID: "com.microsoft.VSCode", isTerminalPanel: false)) == .auto)
    }

    @Test func switchBeatsRules() {
        var settings = SpeechSettings()
        settings.language = .vi
        settings.appLanguages = [AppLanguageRule(kind: .app, id: "com.stablyai.orca", language: .en)]
        #expect(LanguageResolver(settings: settings).language(for: FocusSnapshot(bundleID: "com.stablyai.orca")) == .vi)
    }

    @Test func keyBeatsSwitch() {
        var settings = SpeechSettings()
        settings.language = .vi
        let resolver = LanguageResolver(settings: settings)
        #expect(resolver.language(for: .unknown, keyChoice: .en) == .en)
        #expect(resolver.language(for: .unknown, keyChoice: .auto) == .auto)
    }

    @Test func unlistedAppIsAuto() {
        #expect(LanguageResolver(settings: SpeechSettings()).language(for: FocusSnapshot(bundleID: "notion.id")) == .auto)
    }
}
