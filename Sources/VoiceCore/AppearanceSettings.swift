import Foundation

public enum AppFont: Equatable, Sendable, Codable {
    case system, rounded, serif, hyperlegible, monospaced
    case custom(String)

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "system": self = .system
        case "rounded": self = .rounded
        case "serif": self = .serif
        case "hyperlegible": self = .hyperlegible
        case "monospaced": self = .monospaced
        default:
            if value.hasPrefix("custom:") {
                self = .custom(String(value.dropFirst("custom:".count)))
            } else {
                self = .system
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encodedValue)
    }

    private var encodedValue: String {
        switch self {
        case .system: "system"
        case .rounded: "rounded"
        case .serif: "serif"
        case .hyperlegible: "hyperlegible"
        case .monospaced: "monospaced"
        case .custom(let family): "custom:\(family)"
        }
    }
}

public enum CodeFont: Equatable, Sendable, Codable {
    case sfMono, menlo
    case custom(String)

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "sfMono": self = .sfMono
        case "menlo": self = .menlo
        default:
            if value.hasPrefix("custom:") {
                self = .custom(String(value.dropFirst("custom:".count)))
            } else {
                self = .sfMono
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .sfMono: try container.encode("sfMono")
        case .menlo: try container.encode("menlo")
        case .custom(let family): try container.encode("custom:\(family)")
        }
    }
}

public enum LineSpacing: String, Codable, Equatable, Sendable {
    case normal, relaxed, loose

    public var multiple: Double {
        switch self {
        case .normal: 1.5
        case .relaxed: 1.65
        case .loose: 1.8
        }
    }
}

public enum ReadingWidth: String, Codable, Equatable, Sendable {
    case narrow, medium, wide

    public var points: Double {
        switch self {
        case .narrow: 620
        case .medium: 760
        case .wide: 980
        }
    }
}

public enum AppearanceMode: String, Codable, Equatable, Sendable {
    case light, dark, system
}

public enum HUDSize: String, Codable, Equatable, Sendable {
    case small, medium, large

    public var factor: Double {
        switch self {
        case .small: 0.85
        case .medium: 1.0
        case .large: 1.3
        }
    }
}

public enum ThemeID: String, Codable, CaseIterable, Equatable, Sendable {
    case highContrastDark = "hc-dark"
    case highContrastLight = "hc-light"
    case sepia
    case warmNight = "warm-dark"
    case bugVoiceDark = "bv-dark"
    case catppuccinMocha = "catppuccin-mocha"
    case nord
    case tokyoNight = "tokyo-night"
    case dracula
    case oneDark = "one-dark"
    case gruvboxDark = "gruvbox-dark"
    case everforestDark = "everforest"
    case solarizedDark = "solarized-dark"
    case bugVoiceLight = "bv-light"
    case githubLight = "github-light"
    case oneLight = "one-light"
    case catppuccinLatte = "catppuccin-latte"
    case rosePineDawn = "rose-pine-dawn"
    case gruvboxLight = "gruvbox-light"
    case solarizedLight = "solarized-light"
    case everforestLight = "everforest-light"
}

public enum LogoID: String, Codable, CaseIterable, Equatable, Sendable {
    case waveBug = "wave-bug"
    case antennaMic = "antenna-mic"
    case caretBubble = "caret-bubble"
    case waveB = "wave-b"
    case optionWave = "option-wave"
    case firefly
    case ladybugLevel = "ladybug-level"
    case beeBars = "bee-bars"
    case soundRings = "sound-rings"
    case hudPill = "hud-pill"
    case quoteWave = "quote-wave"
    case nonLa = "non-la"
    case keycapMic = "keycap-mic"
    case codeBug = "code-bug"
    case voiceV = "voice-v"

    public var displayName: String {
        switch self {
        case .waveBug: "Wave Bug"
        case .antennaMic: "Antenna Mic"
        case .caretBubble: "Caret Bubble"
        case .waveB: "Wave B"
        case .optionWave: "Option Wave"
        case .firefly: "Firefly"
        case .ladybugLevel: "Ladybug Level"
        case .beeBars: "Bee Bars"
        case .soundRings: "Sound Rings"
        case .hudPill: "HUD Pill"
        case .quoteWave: "Quote Wave"
        case .nonLa: "Nón Lá"
        case .keycapMic: "Keycap Mic"
        case .codeBug: "Code Bug"
        case .voiceV: "Voice V"
        }
    }

    public var symbolNumber: Int {
        Self.allCases.firstIndex(of: self)! + 1
    }
}

public struct AppearanceSettings: Codable, Equatable, Sendable {
    public static let textScaleRange = 90...160

    public var textScale: Int
    public var font: AppFont
    public var codeFont: CodeFont
    public var lineSpacing: LineSpacing
    public var readingWidth: ReadingWidth
    public var mode: AppearanceMode
    public var theme: ThemeID
    public var lightTheme: ThemeID
    public var darkTheme: ThemeID
    public var hudSize: HUDSize
    public var appIcon: LogoID
    public var menuBarIcon: LogoID

    public init(
        textScale: Int = 100,
        font: AppFont = .system,
        codeFont: CodeFont = .sfMono,
        lineSpacing: LineSpacing = .normal,
        readingWidth: ReadingWidth = .medium,
        mode: AppearanceMode = .dark,
        theme: ThemeID = .bugVoiceDark,
        lightTheme: ThemeID = .bugVoiceLight,
        darkTheme: ThemeID = .bugVoiceDark,
        hudSize: HUDSize = .medium,
        appIcon: LogoID = .antennaMic,
        menuBarIcon: LogoID = .antennaMic
    ) {
        self.textScale = Self.normalizedScale(textScale)
        self.font = font
        self.codeFont = codeFont
        self.lineSpacing = lineSpacing
        self.readingWidth = readingWidth
        self.mode = mode
        self.theme = theme
        self.lightTheme = lightTheme
        self.darkTheme = darkTheme
        self.hudSize = hudSize
        self.appIcon = appIcon
        self.menuBarIcon = menuBarIcon
    }

    private enum CodingKeys: String, CodingKey {
        case textScale, font, codeFont, lineSpacing, readingWidth, mode
        case theme, lightTheme, darkTheme, hudSize, appIcon, menuBarIcon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            textScale: container.value(.textScale, default: 100),
            font: container.value(.font, default: .system),
            codeFont: container.value(.codeFont, default: .sfMono),
            lineSpacing: container.value(.lineSpacing, default: .normal),
            readingWidth: container.value(.readingWidth, default: .medium),
            mode: container.value(.mode, default: .dark),
            theme: container.value(.theme, default: .bugVoiceDark),
            lightTheme: container.value(.lightTheme, default: .bugVoiceLight),
            darkTheme: container.value(.darkTheme, default: .bugVoiceDark),
            hudSize: container.value(.hudSize, default: .medium),
            appIcon: container.value(.appIcon, default: .antennaMic),
            menuBarIcon: container.value(.menuBarIcon, default: .antennaMic)
        )
    }

    public static func normalizedScale(_ value: Int) -> Int {
        let clamped = min(max(value, textScaleRange.lowerBound), textScaleRange.upperBound)
        return ((clamped + 2) / 5) * 5
    }

    public mutating func stepTextScale(by delta: Int) {
        textScale = Self.normalizedScale(textScale + delta)
    }

    public mutating func resetTextScale() {
        textScale = 100
    }

    public mutating func resetEditing() {
        textScale = 100
        font = .system
        codeFont = .sfMono
        lineSpacing = .normal
        readingWidth = .medium
    }

    public mutating func resetThemeAndIcons() {
        mode = .dark
        theme = .bugVoiceDark
        lightTheme = .bugVoiceLight
        darkTheme = .bugVoiceDark
        hudSize = .medium
        appIcon = .antennaMic
        menuBarIcon = .antennaMic
    }

    public func resolvedTheme(systemIsDark: Bool) -> ThemeID {
        switch mode {
        case .light, .dark: theme
        case .system: systemIsDark ? darkTheme : lightTheme
        }
    }
}
