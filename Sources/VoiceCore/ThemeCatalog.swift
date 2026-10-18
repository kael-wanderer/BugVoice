import Foundation

public struct RGB: Equatable, Sendable {
    public let r: Double
    public let g: Double
    public let b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init?(hex: String) {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        r = Double((number >> 16) & 0xff) / 255
        g = Double((number >> 8) & 0xff) / 255
        b = Double(number & 0xff) / 255
    }

    public static let black = RGB(r: 0, g: 0, b: 0)
    public static let white = RGB(r: 1, g: 1, b: 1)

    public func mixed(with other: RGB, amount: Double) -> RGB {
        RGB(
            r: r * (1 - amount) + other.r * amount,
            g: g * (1 - amount) + other.g * amount,
            b: b * (1 - amount) + other.b * amount
        )
    }

    public var hex: String {
        let red = Int((r * 255).rounded()).clamped(to: 0...255)
        let green = Int((g * 255).rounded()).clamped(to: 0...255)
        let blue = Int((b * 255).rounded()).clamped(to: 0...255)
        return String(format: "#%02x%02x%02x", red, green, blue)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

public enum Contrast {
    public static func luminance(_ color: RGB) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }

    public static func ratio(_ a: RGB, _ b: RGB) -> Double {
        let first = luminance(a)
        let second = luminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}

public enum ThemeGroup: String, Sendable {
    case comfort, dark, light
}

public struct ThemeColors: Equatable, Sendable {
    public let background: RGB
    public let sidebar: RGB
    public let card: RGB
    public let separator: RGB
    public let text: RGB
    public let secondaryText: RGB
    public let accent: RGB

    public init(background: RGB, sidebar: RGB, card: RGB, separator: RGB, text: RGB, secondaryText: RGB, accent: RGB) {
        self.background = background
        self.sidebar = sidebar
        self.card = card
        self.separator = separator
        self.text = text
        self.secondaryText = secondaryText
        self.accent = accent
    }

    public func hover(isDark: Bool) -> RGB {
        card.mixed(with: text, amount: isDark ? 0.08 : 0.06)
    }

    public func accentSoft(isDark: Bool) -> RGB {
        background.mixed(with: accent, amount: isDark ? 0.24 : 0.14)
    }

    public var onAccent: RGB {
        Contrast.ratio(.black, accent) >= Contrast.ratio(.white, accent) ? .black : .white
    }
}

public struct StatusColors: Sendable {
    public let recording: RGB
    public let success: RGB
    public let warning: RGB

    public init(recording: RGB, success: RGB, warning: RGB) {
        self.recording = recording
        self.success = success
        self.warning = warning
    }

    public static let dark = StatusColors(
        recording: RGB(hex: "#ff6b6b")!,
        success: RGB(hex: "#4cc38a")!,
        warning: RGB(hex: "#ffa94d")!
    )

    public static let light = StatusColors(
        recording: RGB(hex: "#c62828")!,
        success: RGB(hex: "#1e7a3c")!,
        warning: RGB(hex: "#b45309")!
    )
}

public struct ThemeSpec: Sendable {
    public let id: ThemeID
    public let name: String
    public let group: ThemeGroup
    public let isDark: Bool
    public let colors: ThemeColors

    public init(id: ThemeID, name: String, group: ThemeGroup, isDark: Bool, colors: ThemeColors) {
        self.id = id
        self.name = name
        self.group = group
        self.isDark = isDark
        self.colors = colors
    }

    public var status: StatusColors { isDark ? .dark : .light }
}

public enum ThemeCatalog {
    private static func color(_ hex: String) -> RGB { RGB(hex: hex)! }

    private static func spec(
        _ id: ThemeID,
        _ name: String,
        _ group: ThemeGroup,
        _ isDark: Bool,
        _ background: String,
        _ sidebar: String,
        _ card: String,
        _ separator: String,
        _ text: String,
        _ secondaryText: String,
        _ accent: String
    ) -> ThemeSpec {
        ThemeSpec(
            id: id, name: name, group: group, isDark: isDark,
            colors: ThemeColors(
                background: color(background), sidebar: color(sidebar), card: color(card),
                separator: color(separator), text: color(text), secondaryText: color(secondaryText), accent: color(accent)
            )
        )
    }

    public static let all: [ThemeSpec] = [
        spec(.highContrastDark, "High contrast dark", .comfort, true, "#000000", "#0b0b0b", "#121212", "#8a8a8a", "#ffffff", "#d6d6d6", "#6cb6ff"),
        spec(.highContrastLight, "High contrast light", .comfort, false, "#ffffff", "#f2f2f2", "#ffffff", "#5c5c5c", "#000000", "#2e2e2e", "#0040b0"),
        spec(.sepia, "Sepia paper", .comfort, false, "#f3ead8", "#eadfc8", "#f8f1e2", "#cdbb98", "#33281c", "#5a4b3a", "#8a4b12"),
        spec(.warmNight, "Warm night", .comfort, true, "#1e1a16", "#18150f", "#272219", "#463d31", "#ece1d0", "#bcae98", "#e8a85a"),
        spec(.bugVoiceDark, "BugVoice Dark", .dark, true, "#202225", "#1b1d20", "#272a2e", "#393d43", "#eeeff1", "#a4aab3", "#88aaff"),
        spec(.catppuccinMocha, "Catppuccin Mocha", .dark, true, "#1e1e2e", "#181825", "#262637", "#45475a", "#cdd6f4", "#a6adc8", "#cba6f7"),
        spec(.nord, "Nord", .dark, true, "#2e3440", "#292e39", "#3b4252", "#4c566a", "#eceff4", "#aeb8c5", "#88c0d0"),
        spec(.tokyoNight, "Tokyo Night", .dark, true, "#1a1b26", "#16161e", "#222433", "#3b4261", "#c0caf5", "#9aa5ce", "#7aa2f7"),
        spec(.dracula, "Dracula", .dark, true, "#282a36", "#21222c", "#343746", "#4d5066", "#f8f8f2", "#a4a6b8", "#bd93f9"),
        spec(.oneDark, "One Dark", .dark, true, "#282c34", "#21252b", "#2f343e", "#3e4451", "#bdc3cd", "#999da5", "#61afef"),
        spec(.gruvboxDark, "Gruvbox Dark", .dark, true, "#282828", "#1d2021", "#32302f", "#504945", "#ebdbb2", "#a89984", "#d79921"),
        spec(.everforestDark, "Everforest Dark", .dark, true, "#2d353b", "#272e33", "#343f44", "#4a555b", "#dacfb7", "#9faba2", "#a7c080"),
        spec(.solarizedDark, "Solarized Dark", .dark, true, "#002b36", "#00252e", "#073642", "#1f4f5a", "#b7c0c0", "#8c9b9d", "#268bd2"),
        spec(.bugVoiceLight, "BugVoice Light", .light, false, "#fafbfc", "#f0f1f4", "#ffffff", "#dce0e7", "#222833", "#646d7b", "#315fc8"),
        spec(.githubLight, "GitHub Light", .light, false, "#ffffff", "#f6f8fa", "#ffffff", "#d1d9e0", "#1f2328", "#59636e", "#0969da"),
        spec(.oneLight, "One Light", .light, false, "#fafafa", "#f0f0f1", "#ffffff", "#d3d3d5", "#383a42", "#696c77", "#4078f2"),
        spec(.catppuccinLatte, "Catppuccin Latte", .light, false, "#eff1f5", "#e6e9ef", "#f7f8fa", "#bcc0cc", "#4c4f69", "#6a6d82", "#8839ef"),
        spec(.rosePineDawn, "Rosé Pine Dawn", .light, false, "#faf4ed", "#f2e9e1", "#fffaf3", "#dfdad9", "#534e73", "#716d89", "#907aa9"),
        spec(.gruvboxLight, "Gruvbox Light", .light, false, "#fbf1c7", "#f2e5bc", "#fdf6d8", "#d5c4a1", "#3c3836", "#776b60", "#b57614"),
        spec(.solarizedLight, "Solarized Light", .light, false, "#fdf6e3", "#eee8d5", "#fffbf0", "#d8d0b6", "#46575c", "#667373", "#268bd2"),
        spec(.everforestLight, "Everforest Light", .light, false, "#fdf6e3", "#f4f0d9", "#fffbef", "#e0dcc7", "#4a555b", "#687467", "#859701"),
    ]

    public static func spec(_ id: ThemeID) -> ThemeSpec {
        all.first { $0.id == id }!
    }
}
