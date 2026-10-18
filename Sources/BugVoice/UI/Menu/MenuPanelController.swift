import AppKit
import Observation
import SwiftUI

/// Hosting view that reports intrinsic size changes to its owner.
private final class MenuHostingView: NSHostingView<AnyView> {
    var onSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeChange?()
    }
}

/// Borderless panel that takes keyboard focus without activating BugVoice,
/// so the app the owner works in stays frontmost.
private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the menu bar icon and the popover panel under it.
@MainActor
final class MenuPanelController: NSObject {
    private let model: AppModel
    /// The popover's own appearance: the app's theme at 100% in the system
    /// font, so text size and font family settings do not change it.
    private let menuAppearance = AppearanceStore()
    private let statusItem: NSStatusItem
    private let panel: MenuPanel
    private let hosting: MenuHostingView
    private var mouseMonitor: Any?
    /// App-activation and Space-change observers, installed while open.
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Opened, but waiting for a non-zero fitted size before it shows.
    private var waitingForSize = false
    private var resignObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        panel = MenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        hosting = MenuHostingView(rootView: AnyView(EmptyView()))
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusButtonClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.setAccessibilityLabel("BugVoice")
        }
        updateIcon()

        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        menuAppearance.attach(panel)
        syncAppearance()
        hosting.onSizeChange = { [weak self] in
            MainActor.assumeIsolated { self?.sizeChanged() }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelResignedKey() }
        }
    }

    @objc private func statusButtonClicked() { toggle() }

    func toggle() {
        if panel.isVisible || waitingForSize { close() } else { open() }
    }

    func close() {
        waitingForSize = false
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers = []
    }

    private var openCount = 0

    private func open() {
        model.refreshPermissions()
        Task { await model.refreshSpeechState() }
        // A new identity each open makes SwiftUI drop the old @State, which
        // resets the submenu, the highlight and the measured height.
        openCount += 1
        let popover = MenuPopover(model: model, maxHeight: maxHeight) { [weak self] in self?.close() }
        hosting.rootView = AnyView(popover.id(openCount).bvTheme(menuAppearance, fillsBackground: false))
        hosting.layoutSubtreeIfNeeded()
        // Never show a frame at a stale or zero size and position.
        waitingForSize = !layout()
        if !waitingForSize { show() }
    }

    private func sizeChanged() {
        guard layout(), waitingForSize else { return }
        waitingForSize = false
        show()
    }

    private func show() {
        panel.makeKeyAndOrderFront(nil)
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // A global event's location is already in screen coordinates.
            let location = event.locationInWindow
            MainActor.assumeIsolated {
                guard let self else { return }
                if let frame = self.buttonScreenFrame, NSMouseInRect(location, frame, false) { return }
                self.close()
            }
        }
        // ⌘Tab, a Space swipe or Mission Control make no mouse event and leave
        // BugVoice without a key window, so they are watched separately.
        let center = NSWorkspace.shared.notificationCenter
        let ownPID = ProcessInfo.processInfo.processIdentifier
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.processIdentifier != ownPID else { return }
                MainActor.assumeIsolated { self?.close() }
            },
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            },
        ]
    }

    /// Losing key closes the panel only when another BugVoice window took it,
    /// for example after an action opened the main window. Key going back to
    /// the frontmost app or the status bar must not close it; outside clicks
    /// close it through the mouse monitor.
    private func panelResignedKey() {
        guard let key = NSApp.keyWindow, key !== panel else { return }
        close()
    }

    /// Mirrors the app's appearance with text scale 100 and the system font.
    private func syncAppearance() {
        withObservationTracking {
            var settings = model.appearance.settings
            settings.textScale = 100
            settings.font = .system
            menuAppearance.apply(settings)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.syncAppearance() }
        }
    }

    // MARK: Layout

    private var buttonScreenFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private var screen: NSScreen? {
        statusItem.button?.window?.screen ?? NSScreen.main
    }

    /// The screen's visible height below the menu bar, less a margin.
    private var maxHeight: CGFloat {
        max(0, (screen?.visibleFrame.height ?? 600) - 16)
    }

    /// Top edge 4 pt below the icon, centred on it, kept 8 pt inside the screen.
    @discardableResult private func layout() -> Bool {
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0, let visible = screen?.visibleFrame else { return false }
        let anchor = buttonScreenFrame ?? NSRect(x: visible.midX, y: visible.maxY, width: 0, height: 0)
        let margin: CGFloat = 8
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - margin - size.width)
        let top = min(anchor.minY - 4, visible.maxY)
        let y = max(top - size.height, visible.minY + margin)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
        return true
    }

    // MARK: Icon

    private func updateIcon() {
        withObservationTracking {
            statusItem.button?.image = BrandImages.menuBar(
                logo: model.settings.appearance.menuBarIcon, badge: !model.permissionsGranted)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.updateIcon() }
        }
    }
}
