import AppKit
import VoiceCore

/// Images drawn from the BugVoice logo ("Antenna Mic", App/Icon/AppIcon.svg).
enum BrandImages {
    /// The menu-bar glyph: a microphone with bug antennae, as a template image
    /// so macOS tints it for light and dark menu bars. `badge` adds a dot that
    /// marks a missing permission.
    static func menuBar(logo: LogoID, badge: Bool) -> NSImage {
        if let glyph = IconImages.menuGlyph(logo) {
            guard badge else { return glyph }
            let image = NSImage(size: glyph.size, flipped: true) { rect in
                glyph.draw(in: rect)
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12.9, y: 0.9, width: 4.2, height: 4.2)).fill()
                return true
            }
            image.isTemplate = true
            image.accessibilityDescription = "BugVoice, permission missing"
            return image
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            // Drawn on the 24-unit grid of the SVG glyph, scaled to 18 pt.
            let transform = NSAffineTransform()
            transform.scale(by: 0.75)
            transform.concat()
            NSColor.black.set()

            let stroke = NSBezierPath()
            stroke.lineWidth = 1.7
            stroke.lineCapStyle = .round
            stroke.lineJoinStyle = .round
            stroke.append(NSBezierPath(roundedRect: NSRect(x: 9, y: 5.2, width: 6, height: 10), xRadius: 3, yRadius: 3))
            stroke.move(to: NSPoint(x: 10.2, y: 5.4)); stroke.line(to: NSPoint(x: 8.6, y: 2.8))
            stroke.move(to: NSPoint(x: 13.8, y: 5.4)); stroke.line(to: NSPoint(x: 15.4, y: 2.8))
            stroke.move(to: NSPoint(x: 6.3, y: 11.2))
            stroke.curve(to: NSPoint(x: 12, y: 16.9), controlPoint1: NSPoint(x: 6.3, y: 14.35), controlPoint2: NSPoint(x: 8.85, y: 16.9))
            stroke.curve(to: NSPoint(x: 17.7, y: 11.2), controlPoint1: NSPoint(x: 15.15, y: 16.9), controlPoint2: NSPoint(x: 17.7, y: 14.35))
            stroke.move(to: NSPoint(x: 12, y: 17)); stroke.line(to: NSPoint(x: 12, y: 20))
            stroke.move(to: NSPoint(x: 9.4, y: 20.2)); stroke.line(to: NSPoint(x: 14.6, y: 20.2))
            stroke.stroke()

            if badge {
                NSBezierPath(ovalIn: NSRect(x: 17.2, y: 1.2, width: 5.6, height: 5.6)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = badge ? "BugVoice, permission missing" : "BugVoice"
        return image
    }
}
