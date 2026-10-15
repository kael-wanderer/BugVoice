import Testing
@testable import VoiceCore

struct StyleRouterTests {
    let router = StyleRouter()

    @Test(arguments: [
        ("com.apple.Terminal", Style.terminal), ("com.googlecode.iterm2", .terminal),
        ("dev.warp.Warp-Stable", .terminal), ("com.mitchellh.ghostty", .terminal),
        ("notion.id", .document), ("md.obsidian", .document),
        ("com.apple.MobileSMS", .personal), ("com.vng.zalo", .personal),
        ("net.whatsapp.WhatsApp", .personal), ("ru.keepcoder.Telegram", .personal),
        ("com.hnc.Discord", .personal), ("com.facebook.archon", .personal),
        ("com.tinyspeck.slackmacgap", .work), ("com.microsoft.teams2", .work),
        ("com.microsoft.teams", .work), ("com.electron.lark", .work),
        ("com.apple.mail", .email), ("com.example.unknown", .other),
    ])
    func defaultApps(bundleID: String, expected: Style) {
        #expect(router.style(for: FocusSnapshot(bundleID: bundleID)) == expected)
    }

    @Test func vsCodeTerminalPanelIsTerminalButEditorIsOther() {
        #expect(router.style(for: FocusSnapshot(bundleID: "com.microsoft.VSCode", isTerminalPanel: true)) == .terminal)
        #expect(router.style(for: FocusSnapshot(bundleID: "com.microsoft.VSCode")) == .other)
    }

    @Test(arguments: [
        ("https://docs.google.com/document/d/1", Style.document), ("https://mail.google.com/mail/u/0", .email),
        ("https://web.whatsapp.com/", .personal), ("https://www.messenger.com/t/1", .personal),
        ("https://discord.com/channels/1", .personal), ("https://web.telegram.org/a/", .personal),
        ("https://chat.zalo.me/", .personal), ("https://app.slack.com/client/T1", .work),
        ("https://teams.microsoft.com/v2/", .work), ("https://teams.live.com/v2/", .work),
        ("https://chat.google.com/room/1", .work), ("https://example.com/", .other),
    ])
    func browserURLDecidesStyle(url: String, expected: Style) {
        #expect(router.style(for: FocusSnapshot(bundleID: "com.google.Chrome", url: url)) == expected)
    }

    @Test func overrideStillWins() {
        let r = StyleRouter(overrides: ["ru.keepcoder.Telegram": .work])
        #expect(r.style(for: FocusSnapshot(bundleID: "ru.keepcoder.Telegram")) == .work)
    }

    @Test func unknownFocusIsOther() {
        #expect(router.style(for: .unknown) == .other)
    }

    @Test func builtInAppsAndWebsitesPerStyle() {
        #expect(StyleRouter.builtInApps(for: .work) == [
            "com.electron.lark", "com.microsoft.teams", "com.microsoft.teams2", "com.tinyspeck.slackmacgap",
        ])
        #expect(StyleRouter.builtInApps(for: .other).isEmpty)
        #expect(StyleRouter.websites(for: .personal) == [
            "web.whatsapp.com", "messenger.com", "discord.com", "web.telegram.org", "chat.zalo.me",
        ])
        #expect(StyleRouter.websites(for: .terminal).isEmpty)
    }
}
