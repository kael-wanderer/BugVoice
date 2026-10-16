import AppKit
import SwiftUI

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
        if model.settings.meetings.windowCollapsed {
            window.contentMinSize = NSSize(width: Self.minWidth, height: Self.topBarHeight)
            guard frame.height > Self.topBarHeight + 1 else { return }
            expandedHeight = frame.height
            frame.origin.y += frame.height - Self.topBarHeight
            frame.size.height = Self.topBarHeight
        } else {
            window.contentMinSize = NSSize(width: Self.minWidth, height: Self.minHeight)
            guard frame.height < Self.minHeight else { return }
            let screen = window.screen ?? NSScreen.main
            let height = expandedHeight ?? screen.map { Self.defaultFrame(on: $0).height } ?? 700
            frame.origin.y -= height - frame.height
            if let visible = screen?.visibleFrame, frame.minY < visible.minY { frame.origin.y = visible.minY }
            frame.size.height = height
        }
        window.setFrame(frame, display: true, animate: animate)
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
            )
        )
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
