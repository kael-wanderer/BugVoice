import AppKit
import SwiftUI
import VoiceCore

/// Owns the meeting window: docked to the right third of the screen, above
/// other windows on every Space. Buttons and tabs do not take the keyboard
/// from the meeting app; the notes editor and the Ask box do.
@MainActor
final class MeetingWindowController: NSObject, NSWindowDelegate {
    static let autosaveName = "MeetingWindow"
    static let minWidth: CGFloat = 360
    static let minHeight: CGFloat = 420
    static let topBarHeight: CGFloat = 44
    static let inset: CGFloat = 12

    private let model: AppModel
    private let controller: MeetingController
    private var window: MeetingPanel?
    /// The height before Collapse, so expanding restores it.
    private var expandedHeight: CGFloat?
    /// A check is waiting for the mouse button to come up after a drag.
    private var dragCheckPending = false

    init(model: AppModel, controller: MeetingController) {
        self.model = model
        self.controller = controller
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        applyCollapsed(animate: false)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func toggleCollapsed() {
        model.settings.meetings.windowCollapsed.toggle()
        applyCollapsed(animate: true)
    }

    /// Right third of the visible frame, full height, 12 pt in from the edges.
    static func defaultFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame.insetBy(dx: inset, dy: inset)
        let width = max(minWidth, (visible.width / 3).rounded())
        return NSRect(x: visible.maxX - width, y: visible.minY, width: width, height: visible.height)
    }

    private func applyCollapsed(animate: Bool) {
        guard let window else { return }
        var frame = window.frame
        let screen = window.screen ?? NSScreen.main
        if model.settings.meetings.windowCollapsed {
            window.contentMinSize = NSSize(width: Self.minWidth, height: Self.topBarHeight)
            // Keeps window tiling from stretching the bar into a tall empty window.
            window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: Self.topBarHeight)
            if frame.height > Self.topBarHeight + 1 {
                expandedHeight = frame.height
                frame.origin.y += frame.height - Self.topBarHeight
                frame.size.height = Self.topBarHeight
            }
        } else {
            window.contentMinSize = NSSize(width: Self.minWidth, height: Self.minHeight)
            window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            if frame.height < Self.minHeight {
                let height = expandedHeight ?? screen.map { Self.defaultFrame(on: $0).height } ?? 700
                frame.origin.y -= height - frame.height
                frame.size.height = height
            }
        }
        if let screen { frame = Self.onScreen(frame, screen: screen) }
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true, animate: animate)
    }

    /// A window dragged past a display edge would hide the bar's buttons.
    private static func onScreen(_ frame: NSRect, screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let placed = WindowPlacement.onScreen(
            .init(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
            visible: .init(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height)
        )
        return NSRect(x: placed.x, y: placed.y, width: placed.width, height: placed.height)
    }

    func windowDidMove(_ notification: Notification) {
        keepOnScreenAfterDrag()
    }

    /// Moves the window back inside its display once the drag ends.
    private func keepOnScreenAfterDrag() {
        guard !dragCheckPending, let window else { return }
        guard NSEvent.pressedMouseButtons == 0 else {
            dragCheckPending = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                self?.dragCheckPending = false
                self?.keepOnScreenAfterDrag()
            }
            return
        }
        guard let screen = window.screen ?? NSScreen.main else { return }
        let frame = Self.onScreen(window.frame, screen: screen)
        if frame != window.frame { window.setFrame(frame, display: true, animate: true) }
    }

    private func makeWindow() -> MeetingPanel {
        let window = MeetingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 700),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = "Meeting"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.identifier = AppWindow.meeting
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        // Clicks on buttons and tabs leave the keyboard with the meeting app.
        window.becomesKeyOnlyIfNeeded = true
        window.delegate = self
        let hosting = NSHostingController(
            rootView: MeetingWindowView(
                model: model,
                controller: controller,
                onToggleCollapse: { [weak self] in self?.toggleCollapsed() },
                onClose: { [weak self] in
                    guard let self else { return }
                    self.hide()
                    Task { await self.controller.closeWindow() }
                }
            ).bvTheme(model.appearance)
        )
        model.appearance.attach(window)
        // The window's frame comes from the user and autosave, not the content.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        let restored = window.setFrameUsingName(Self.autosaveName)
        // Setting the autosave name applies the saved frame again, so place the window after it.
        window.setFrameAutosaveName(Self.autosaveName)
        if let screen = AppWindow.developmentScreen() {
            // Development runs always open on the display that is not primary.
            window.setFrame(Self.defaultFrame(on: screen), display: false)
        } else if !restored || !Self.fitsAScreen(window.frame) {
            let screen = MeetingDetectionController.frontmostWindowScreen() ?? NSScreen.main
            if let screen { window.setFrame(Self.defaultFrame(on: screen), display: false) }
        }
        return window
    }

    /// True when most of the frame is on a connected display.
    static func fitsAScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(frame)
            return overlap.width * overlap.height >= frame.width * frame.height * 0.5
        }
    }
}

/// Takes the keyboard without activating BugVoice, like the Scratchpad window.
final class MeetingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
