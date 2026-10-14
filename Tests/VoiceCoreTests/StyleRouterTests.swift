import Testing
@testable import VoiceCore

struct StyleRouterTests {
    let router = StyleRouter()

    @Test(arguments: [
        ("com.apple.Terminal", Style.terminal),
        ("com.googlecode.iterm2", .terminal),
        ("dev.warp.Warp-Stable", .terminal),
        ("com.mitchellh.ghostty", .terminal),
        ("notion.id", .document),
        ("md.obsidian", .document),
        ("com.tinyspeck.slackmacgap", .chat),
        ("com.apple.mail", .email),
        ("com.example.unknown", .other),
    ])
    func defaultApps(bundleID: String, expected: Style) {
        #expect(router.style(for: FocusSnapshot(bundleID: bundleID)) == expected)
    }

    @Test func vsCodeTerminalPanelIsTerminalButEditorIsOther() {
        #expect(router.style(for: FocusSnapshot(bundleID: "com.microsoft.VSCode", isTerminalPanel: true)) == .terminal)
        #expect(router.style(for: FocusSnapshot(bundleID: "com.microsoft.VSCode")) == .other)
    }

    @Test func browserURLDecidesStyle() {
        let chrome = "com.google.Chrome"
        #expect(router.style(for: FocusSnapshot(bundleID: chrome, url: "https://docs.google.com/document/d/1")) == .document)
        #expect(router.style(for: FocusSnapshot(bundleID: chrome, url: "https://mail.google.com/mail/u/0")) == .email)
        #expect(router.style(for: FocusSnapshot(bundleID: chrome, url: "https://www.notion.so/page")) == .document)
        #expect(router.style(for: FocusSnapshot(bundleID: chrome, url: "https://example.com")) == .other)
    }

    @Test func overrideBeatsEverything() {
        let r = StyleRouter(overrides: ["com.apple.Terminal": .document])
        #expect(r.style(for: FocusSnapshot(bundleID: "com.apple.Terminal")) == .document)
    }

    @Test func unknownFocusIsOther() {
        #expect(router.style(for: .unknown) == .other)
    }
}
