import AppKit
import SwiftUI
import VoiceCore

/// Seven tag colours, with a separate sRGB palette for each appearance.
enum TagColors {
    static func color(_ c: TagColor) -> Color {
        let pair: (Int, Int) = switch c {
        case .red: (0xc43e39, 0xf07973)
        case .orange: (0xad6019, 0xf0a050)
        case .yellow: (0x927212, 0xe6c65c)
        case .green: (0x29814b, 0x65c98a)
        case .teal: (0x247f8c, 0x68c4d0)
        case .blue: (0x3d6fd1, 0x82a5ff)
        case .purple: (0x8853bd, 0xbb92ed)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? pair.1 : pair.0
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }

    static func dot(_ c: TagColor) -> Image {
        let color = NSColor(color(c))
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        return Image(nsImage: image)
    }
}

private struct TagColorsKey: EnvironmentKey {
    static let defaultValue: [String: TagColor] = [:]
}

extension EnvironmentValues {
    var tagColors: [String: TagColor] {
        get { self[TagColorsKey.self] }
        set { self[TagColorsKey.self] = newValue }
    }
}

private struct TagColorsModifier: ViewModifier {
    let model: AppModel

    func body(content: Content) -> some View {
        content.environment(\.tagColors, model.tagColors)
    }
}

extension View {
    func tagColors(_ model: AppModel) -> some View {
        modifier(TagColorsModifier(model: model))
    }
}
