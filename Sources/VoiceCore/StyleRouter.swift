import Foundation

public struct StyleRouter: Sendable {
    public static let defaultApps: [String: Style] = [
        "com.apple.Terminal": .terminal,
        "com.googlecode.iterm2": .terminal,
        "dev.warp.Warp-Stable": .terminal,
        "com.mitchellh.ghostty": .terminal,
        "notion.id": .document,
        "md.obsidian": .document,
        "com.apple.iWork.Pages": .document,
        "com.microsoft.Word": .document,
        "com.apple.TextEdit": .document,
        "com.tinyspeck.slackmacgap": .chat,
        "com.apple.MobileSMS": .chat,
        "com.hnc.Discord": .chat,
        "ru.keepcoder.Telegram": .chat,
        "com.vng.zalo": .chat,
        "com.apple.mail": .email,
        "com.microsoft.Outlook": .email,
    ]

    /// Editors whose integrated terminal should route as `.terminal`.
    public static let editorsWithTerminalPanel: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92", // Cursor
    ]

    static let urlRules: [(host: String, style: Style)] = [
        ("docs.google.com", .document),
        ("notion.so", .document),
        ("mail.google.com", .email),
        ("outlook.office.com", .email),
        ("app.slack.com", .chat),
    ]

    public var overrides: [String: Style]

    public init(overrides: [String: Style] = [:]) {
        self.overrides = overrides
    }

    public func style(for focus: FocusSnapshot) -> Style {
        if let id = focus.bundleID, let style = overrides[id] { return style }
        if let id = focus.bundleID, Self.editorsWithTerminalPanel.contains(id), focus.isTerminalPanel {
            return .terminal
        }
        if let raw = focus.url, let host = URL(string: raw)?.host?.lowercased() {
            for rule in Self.urlRules where host == rule.host || host.hasSuffix("." + rule.host) {
                return rule.style
            }
        }
        if let id = focus.bundleID, let style = Self.defaultApps[id] { return style }
        return .other
    }
}
