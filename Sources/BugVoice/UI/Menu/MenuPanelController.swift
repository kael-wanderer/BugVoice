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
    private let statusItem: NSStatusItem
    private let panel: MenuPanel
    private let hosting: MenuHostingView
    private var mouseMonitor: Any?
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
        model.appearance.attach(panel)
        hosting.onSizeChange = { [weak self] in
            MainActor.assumeIsolated { self?.layout() }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelResignedKey() }
        }
    }

    @objc private func statusButtonClicked() { toggle() }

    func toggle() {
        if panel.isVisible { close() } else { open() }
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    private func open() {
        model.refreshPermissions()
        Task { await model.refreshSpeechState() }
        // A fresh view each time resets the submenu and the highlight.
        let popover = MenuPopover(model: model, maxHeight: maxHeight) { [weak self] in self?.close() }
        hosting.rootView = AnyView(popover.bvTheme(model.appearance, fillsBackground: false))
        hosting.layoutSubtreeIfNeeded()
        layout()
        panel.makeKeyAndOrderFront(nil)
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let frame = self.buttonScreenFrame, NSMouseInRect(NSEvent.mouseLocation, frame, false) { return }
                self.close()
            }
        }
    }

    /// Losing key closes the panel, except while the status button is being
    /// pressed: its own action toggles the panel, so it must not reopen.
    private func panelResignedKey() {
        if NSEvent.pressedMouseButtons != 0, let frame = buttonScreenFrame,
           NSMouseInRect(NSEvent.mouseLocation, frame, false) { return }
        close()
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
    private func layout() {
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0, let visible = screen?.visibleFrame else { return }
        let anchor = buttonScreenFrame ?? NSRect(x: visible.midX, y: visible.maxY, width: 0, height: 0)
        let margin: CGFloat = 8
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - margin - size.width)
        let top = min(anchor.minY - 4, visible.maxY)
        let y = max(top - size.height, visible.minY + margin)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
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
