import AppKit
import CoreText

@MainActor enum FontRegistry {
    static var families: [String] { NSFontManager.shared.availableFontFamilies.sorted() }
    // Version 2.001 failed the Vietnamese gate. Keep this off even if installed locally.
    static let hyperlegibleAvailable = false

    static func registerBundledFonts() {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for url in files where ["otf", "ttf"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
