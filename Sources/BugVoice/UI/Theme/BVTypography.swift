import AppKit
import SwiftUI
import VoiceCore

struct BVTypography {
    var settings: AppearanceSettings
    func font(_ token: TextToken) -> Font {
        switch settings.font {
        case .custom:
            let resolved = nsFont(token)
            return .custom(resolved.fontName, fixedSize: resolved.pointSize)
        default: return Font(nsFont(token))
        }
    }
    func codeFont(_ token: TextToken) -> Font {
        let resolved = nsCodeFont(token)
        return .custom(resolved.fontName, fixedSize: resolved.pointSize)
    }
    func nsFont(_ token: TextToken) -> NSFont {
        let size = TypeScale.size(token, scale: settings.textScale)
        let weight = weight(token)
        switch settings.font {
        case .system: return .systemFont(ofSize: size, weight: weight)
        case .rounded: return designed(.rounded, size: size, weight: weight)
        case .serif: return designed(.serif, size: size, weight: weight)
        case .monospaced: return .monospacedSystemFont(ofSize: size, weight: weight)
        case .hyperlegible: return .systemFont(ofSize: size, weight: weight)
        case .custom(let name): return custom(name, size: size, weight: weight)
        }
    }
    func nsCodeFont(_ token: TextToken) -> NSFont {
        let size = TypeScale.size(token, scale: settings.textScale)
        switch settings.codeFont {
        case .sfMono: return .monospacedSystemFont(ofSize: size, weight: weight(token))
        case .menlo: return custom("Menlo", size: size, weight: weight(token))
        case .custom(let name): return custom(name, size: size, weight: weight(token))
        }
    }
    private func weight(_ token: TextToken) -> NSFont.Weight {
        switch token.weight { case .regular: .regular; case .semibold: .semibold; case .bold: .bold }
    }
    private func designed(_ design: NSFontDescriptor.SystemDesign, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        return base.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }
    private func custom(_ name: String, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        guard let font = NSFont(name: name, size: size) else { return .systemFont(ofSize: size, weight: weight) }
        return NSFontManager.shared.convert(font, toHaveTrait: weight == .regular ? [] : .boldFontMask)
    }
}
