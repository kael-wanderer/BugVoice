import AppKit

@MainActor enum FontRegistry {
    static var families: [String] { NSFontManager.shared.availableFontFamilies.sorted() }
    static var hyperlegibleAvailable: Bool { NSFont(name: "Atkinson Hyperlegible Next", size: 15) != nil }
}
