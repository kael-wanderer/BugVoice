import AppKit
import SwiftUI
import VoiceCore

struct BVTheme {
    let isDark: Bool
    let background: Color
    let backgroundNS: NSColor
    let sidebar: Color
    let sidebarNS: NSColor
    let card: Color
    let cardNS: NSColor
    let separator: Color
    let separatorNS: NSColor
    let text: Color
    let textNS: NSColor
    let secondaryText: Color
    let secondaryTextNS: NSColor
    let accent: Color
    let accentNS: NSColor
    let hover: Color
    let hoverNS: NSColor
    let accentSoft: Color
    let accentSoftNS: NSColor
    let onAccent: Color
    let onAccentNS: NSColor
    let recording: Color
    let recordingNS: NSColor
    let success: Color
    let successNS: NSColor
    let warning: Color
    let warningNS: NSColor
    init(_ spec: ThemeSpec) {
        isDark = spec.isDark
        let backgroundRGB = spec.colors.background
        backgroundNS = NSColor(srgbRed: backgroundRGB.r, green: backgroundRGB.g, blue: backgroundRGB.b, alpha: 1)
        background = Color(nsColor: backgroundNS)
        let sidebarRGB = spec.colors.sidebar
        sidebarNS = NSColor(srgbRed: sidebarRGB.r, green: sidebarRGB.g, blue: sidebarRGB.b, alpha: 1)
        sidebar = Color(nsColor: sidebarNS)
        let cardRGB = spec.colors.card
        cardNS = NSColor(srgbRed: cardRGB.r, green: cardRGB.g, blue: cardRGB.b, alpha: 1)
        card = Color(nsColor: cardNS)
        let separatorRGB = spec.colors.separator
        separatorNS = NSColor(srgbRed: separatorRGB.r, green: separatorRGB.g, blue: separatorRGB.b, alpha: 1)
        separator = Color(nsColor: separatorNS)
        let textRGB = spec.colors.text
        textNS = NSColor(srgbRed: textRGB.r, green: textRGB.g, blue: textRGB.b, alpha: 1)
        text = Color(nsColor: textNS)
        let secondaryTextRGB = spec.colors.secondaryText
        secondaryTextNS = NSColor(srgbRed: secondaryTextRGB.r, green: secondaryTextRGB.g, blue: secondaryTextRGB.b, alpha: 1)
        secondaryText = Color(nsColor: secondaryTextNS)
        let accentRGB = spec.colors.accent
        accentNS = NSColor(srgbRed: accentRGB.r, green: accentRGB.g, blue: accentRGB.b, alpha: 1)
        accent = Color(nsColor: accentNS)
        let hoverRGB = spec.colors.hover(isDark: spec.isDark)
        hoverNS = NSColor(srgbRed: hoverRGB.r, green: hoverRGB.g, blue: hoverRGB.b, alpha: 1)
        hover = Color(nsColor: hoverNS)
        let accentSoftRGB = spec.colors.accentSoft(isDark: spec.isDark)
        accentSoftNS = NSColor(srgbRed: accentSoftRGB.r, green: accentSoftRGB.g, blue: accentSoftRGB.b, alpha: 1)
        accentSoft = Color(nsColor: accentSoftNS)
        let onAccentRGB = spec.colors.onAccent
        onAccentNS = NSColor(srgbRed: onAccentRGB.r, green: onAccentRGB.g, blue: onAccentRGB.b, alpha: 1)
        onAccent = Color(nsColor: onAccentNS)
        let recordingRGB = spec.status.recording
        recordingNS = NSColor(srgbRed: recordingRGB.r, green: recordingRGB.g, blue: recordingRGB.b, alpha: 1)
        recording = Color(nsColor: recordingNS)
        let successRGB = spec.status.success
        successNS = NSColor(srgbRed: successRGB.r, green: successRGB.g, blue: successRGB.b, alpha: 1)
        success = Color(nsColor: successNS)
        let warningRGB = spec.status.warning
        warningNS = NSColor(srgbRed: warningRGB.r, green: warningRGB.g, blue: warningRGB.b, alpha: 1)
        warning = Color(nsColor: warningNS)
    }
}
