import AppKit
import SwiftUI

/// The six speaker colours from proposal-meeting-speakers.html, adapting to appearance.
enum SpeakerColors {
    static func color(_ index: Int) -> Color {
        let light = [0x3a6ff0, 0x8a57d6, 0xd0731c, 0x1f9a5a, 0xc2407a, 0x2a8fa8]
        let dark = [0x6e93ff, 0xb48cf0, 0xf0a050, 0x4cc98a, 0xf07aae, 0x5cc4dc]
        let slot = ((index % light.count) + light.count) % light.count
        return Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark[slot] : light[slot]
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

extension SpeakerColors {
    /// A filled dot as an image, so menus keep its colour.
    static func dot(_ index: Int) -> Image {
        let color = NSColor(color(index))
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        return Image(nsImage: image)
    }
}

