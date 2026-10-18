import AppKit
import VoiceCore

enum IconImages {
    static func appIcon(_ id: LogoID) -> NSImage? {
        guard let root = Bundle.main.resourceURL else { return nil }
        return NSImage(contentsOf: root.appendingPathComponent("Icons/\(id.rawValue).png"))
    }
    static func menuGlyph(_ id: LogoID) -> NSImage? {
        guard let root = Bundle.main.resourceURL else { return nil }
        let image = NSImage(size: NSSize(width: 18, height: 18))
        for suffix in ["", "@2x"] {
            let url = root.appendingPathComponent("MenuBarIcons/\(id.rawValue)\(suffix).png")
            if let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) {
                rep.size = image.size
                image.addRepresentation(rep)
            }
        }
        guard !image.representations.isEmpty else { return nil }
        image.isTemplate = true
        return image
    }
}
