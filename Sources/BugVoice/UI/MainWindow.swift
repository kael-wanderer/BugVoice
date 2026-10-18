import AppKit
import SwiftUI
import VoiceCore

struct MainWindow: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            if !model.sidebarHidden {
                AppSidebar(model: model).frame(width: model.sidebarWidth)
                ResizeHandle(width: model.sidebarWidth, range: ShellLayout.sidebarRange) { model.sidebarDraggedWidth = $0 }
            }
            VStack(spacing: 0) {
                TitleBar(model: model, title: model.page.title) { PageActions(model: model) }.zIndex(1)
                Rectangle().fill(.bvSeparator).frame(height: 1)
                pageContent.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(.bvBackground)
        }
        .ignoresSafeArea(.container, edges: .top)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { model.mainContentHeight = $0 }
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { value in
            if !model.searchFieldFrame.contains(value.location) && !model.searchResultsFrame.contains(value.location) {
                model.searchIsPresented = false
            }
        })
        .onChange(of: model.page) { _, _ in model.searchIsPresented = false }
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                Text(notice)
                    .bvFont(.body)
                    .padding(.horizontal, LayoutTokens.spacing[2])
                    .padding(.vertical, LayoutTokens.spacing[1])
                    .background(.bvCard, in: Capsule())
                    .overlay(Capsule().stroke(store.theme.secondaryText.opacity(0.25)))
                    .padding(.bottom, LayoutTokens.spacing[5])
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.notice)
        .alert(
            "Could not save",
            isPresented: Binding(
                get: { model.saveError != nil && !model.scratchpadWindowIsKey },
                set: { if !$0 { model.saveError = nil } }
            )
        ) {
            Button("OK") { model.saveError = nil }
        } message: {
            Text(model.saveError ?? "")
        }
    }
    @ViewBuilder private var pageContent: some View {
            switch model.page {
            case .dictation: DictationHistoryView(model: model)
            case .insights: InsightsPage(model: model)
            case .dictionary: DictionaryPage(model: model)
            case .style: StylePage(model: model)
            case .meetings: MeetingsPage(model: model)
            case .upload: UploadPage(model: model)
            case .notes: NotesPage(model: model)
            case .integrations: ComingSoonPage(page: .integrations, model: model)
            case .settings: SettingsView(model: model)
            case .help: ComingSoonPage(page: .help, model: model)
            }
    }

}

/// Owns the main window. AppKit-managed rather than a SwiftUI `Window` scene
/// so that app code (menu, global shortcut ⌃⌥B, Dock click) can open it
/// without a SwiftUI view having to relay `openWindow`.
///
/// The app is `LSUIElement`; while this window is open it switches to a
/// regular app so it has a Dock icon and a ⌘-Tab entry, and back when it
/// closes.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    /// Smallest frame size for the current text size (see `updateMinimum`).
    private var minimumFrameSize = NSSize(width: ShellLayout.baseMinimumWindowWidth, height: ShellLayout.minimumWindowHeight)

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "BugVoice"
        // Title stays for the Window menu and Mission Control but is not drawn;
        // the sidebar runs under the transparent title bar.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.identifier = AppWindow.main
        let hosting = NSHostingController(rootView: MainWindow(model: model).bvTheme(model.appearance))
        // The window's minimum comes from `updateMinimum`, which follows text
        // size; by default the hosting controller would overwrite it with the
        // SwiftUI content's own minimum.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        model.appearance.attach(window)
        window.isReleasedWhenClosed = false
        window.delegate = self
        if !window.setFrameUsingName("BugVoiceMain") {
            window.setContentSize(NSSize(width: 1000, height: 680))
            window.center()
        }
        window.setFrameAutosaveName("BugVoiceMain")
        AppWindow.placeForDevelopment(window)
        updateMinimum(window)
        observeScale()
        return window
    }

    private func observeScale() {
        withObservationTracking {
            _ = model.settings.appearance.textScale
            _ = model.settings.appearance.font
            _ = model.sidebarWidth
            _ = model.listPaneWidth
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let window = self.window { self.updateMinimum(window) }
                self.observeScale()
            }
        }
    }

    /// The widest pill row on any page, kept on one line at the window's minimum.
    private var widestPillRow: CGFloat {
        let font = model.appearance.type.nsFont(.bodyStrong)
        return [
            SettingsTab.allCases.map(\.title),
            Style.allCases.map(\.title),
            ["All"] + Style.allCases.map { $0.rawValue.capitalized },
        ].map { RoundPills<Int>.singleRowWidth($0, font: font) }.max() ?? 0
    }

    private func updateMinimum(_ window: NSWindow) {
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        let scale = model.settings.appearance.textScale
        let width = ShellLayout.minimumWindowWidth(
            sidebar: model.sidebarWidth, listPane: model.listPaneWidth, content: widestPillRow, screenWidth: visible.width)
        window.contentMinSize = NSSize(width: width, height: ShellLayout.minimumWindowHeight)
        minimumFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: window.contentMinSize)).size
        if ShellLayout.sidebarMustHide(scale: scale, screenWidth: visible.width) { model.sidebarHidden = true }
        var frame = window.frame
        frame.size.width = max(frame.width, width)
        let height = max(frame.height, ShellLayout.minimumWindowHeight)
        frame.origin.y -= height - frame.height // keep the top edge in place
        frame.size.height = height
        frame.origin.y = max(visible.minY, frame.origin.y)
        frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
        window.setFrame(frame, display: true)
    }

    /// `contentMinSize` alone does not hold here (the SwiftUI content view
    /// still lets AppKit shrink the window), so clamp every resize.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, minimumFrameSize.width), height: max(frameSize.height, minimumFrameSize.height))
    }

    func windowDidBecomeKey(_ notification: Notification) { model.mainWindowIsKey = true }
    func windowDidResignKey(_ notification: Notification) {
        model.mainWindowIsKey = false
    }
    func windowWillClose(_ notification: Notification) {
        AppWindow.didClose(notification.object as? NSWindow)
    }
}

/// Identifiers for BugVoice's own windows, and the shared rule for the
/// activation policy: regular while any of them is visible, accessory after
/// the last one closes.
@MainActor
enum AppWindow {
    static let main = NSUserInterfaceItemIdentifier("BugVoiceMain")
    static let permissions = NSUserInterfaceItemIdentifier("BugVoicePermissions")
    static let scratchpad = NSUserInterfaceItemIdentifier("BugVoiceScratchpad")
    static let meeting = NSUserInterfaceItemIdentifier("BugVoiceMeeting")

    static func didClose(_ closing: NSWindow?) {
        let ours: Set<NSUserInterfaceItemIdentifier> = [main, permissions]
        let otherVisible = NSApp.windows.contains {
            $0 !== closing && ($0.isVisible || $0.isMiniaturized)
                && ($0.identifier.map(ours.contains) ?? false)
        }
        if !otherVisible { NSApp.setActivationPolicy(.accessory) }
    }

    /// Development runs only (see `DevScreen`): the display new windows open
    /// on. Nil on a normal launch or with one display.
    static func developmentScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let displays = screens.map { DevScreen.Display(x: $0.frame.minX, y: $0.frame.minY) }
        // NSScreen.screens[0] is the display with the menu bar.
        let setting = ProcessInfo.processInfo.environment[DevScreen.environmentKey]
        guard let index = DevScreen.choose(displays, primary: displays.first, setting: setting) else { return nil }
        return screens[index]
    }

    /// Development runs only (see `DevScreen`): centers a new window on a
    /// display that is not primary. Does nothing on a normal launch or with
    /// one display.
    static func placeForDevelopment(_ window: NSWindow) {
        guard let screen = developmentScreen() else { return }
        let visible = screen.visibleFrame
        let size = NSSize(
            width: min(window.frame.width, visible.width),
            height: min(window.frame.height, visible.height))
        window.setFrame(
            NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height),
            display: false)
    }
}
