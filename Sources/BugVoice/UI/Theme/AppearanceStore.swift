import AppKit
import Observation
import VoiceCore

@MainActor @Observable final class AppearanceStore {
    private(set) var settings = AppearanceSettings()
    private(set) var systemIsDark = false
    var theme: BVTheme { BVTheme(ThemeCatalog.spec(settings.resolvedTheme(systemIsDark: systemIsDark))) }
    var type: BVTypography { BVTypography(settings: settings) }
    var readingWidth: CGFloat { scaled(settings.readingWidth.points) }
    var lineSpacingMultiple: CGFloat { settings.lineSpacing.multiple }
    var nsAppearance: NSAppearance { NSAppearance(named: theme.isDark ? .darkAqua : .aqua)! }
    @ObservationIgnored private var windows = NSHashTable<NSWindow>.weakObjects()
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                self.updateWindows()
            }
        }
    }
    func apply(_ settings: AppearanceSettings) {
        self.settings = settings
        updateWindows()
    }
    func scaled(_ points: CGFloat) -> CGFloat { TypeScale.scaled(points, scale: settings.textScale) }
    func attach(_ window: NSWindow) {
        windows.add(window)
        window.appearance = nsAppearance
    }
    private func updateWindows() {
        for window in windows.allObjects { window.appearance = nsAppearance }
    }
}
