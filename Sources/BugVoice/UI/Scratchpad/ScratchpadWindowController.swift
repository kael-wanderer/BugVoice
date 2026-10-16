import AppKit
import SwiftUI
import VoiceCore

/// Owns the floating Scratchpad window. It stays on top of other apps
/// (also full-screen ones) while Keep on top is on, remembers the app that
/// was in front when it opened, and goes back to it after Copy and close.
@MainActor
final class ScratchpadWindowController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 720, height: 560)
    static let compactWidth: CGFloat = 440

    private let model: AppModel
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?
    /// The width before Smaller, so Larger can restore it.
    private var widthBeforeCompact: CGFloat?

    init(model: AppModel) {
        self.model = model
    }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        let window = self.window ?? makeWindow()
        self.window = window
        applyLayout()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        model.scratchpadWindowIsVisible = true
        model.notesFocusRequest &+= 1
    }

    /// Saves every open note, then hides the window.
    func close(returnToPreviousApp: Bool) {
        window?.close()
        if returnToPreviousApp { previousApp?.activate() }
    }

    /// Keep on top and Smaller/Larger, from settings.
    func applyLayout() {
        guard let window else { return }
        let settings = model.settings.scratchpad
        window.level = settings.keepOnTop ? .floating : .normal
        var frame = window.frame
        if settings.compact, frame.width > Self.compactWidth {
            widthBeforeCompact = frame.width
            frame.size.width = Self.compactWidth
            window.setFrame(frame, display: true, animate: window.isVisible)
        } else if !settings.compact, let width = widthBeforeCompact {
            widthBeforeCompact = nil
            frame.size.width = width
            window.setFrame(frame, display: true, animate: window.isVisible)
        }
    }

    private func makeWindow() -> NSPanel {
        let window = ScratchpadPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = "Scratchpad"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isMovableByWindowBackground = true
        window.identifier = AppWindow.scratchpad
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentMinSize = NSSize(width: 420, height: 360)
        window.contentViewController = NSHostingController(rootView: ScratchpadWindowView(model: model))
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.delegate = self
        if !window.setFrameUsingName("ScratchpadWindow") {
            window.setContentSize(Self.defaultSize)
            centerOnMouseScreen(window)
        }
        window.setFrameAutosaveName("ScratchpadWindow")
        AppWindow.placeForDevelopment(window)
        return window
    }

    private func centerOnMouseScreen(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.scratchpadWindowIsKey = true
    }

    func windowDidResignKey(_ notification: Notification) {
        model.scratchpadWindowIsKey = false
    }

    func windowWillClose(_ notification: Notification) {
        model.scratchpadWindowIsVisible = false
        model.scratchpadWindowIsKey = false
        if model.notesIsListening { model.dictation?.toggleNotesRecording() }
        Task { await model.scratchpadWindowClosed() }
    }
}

/// BugVoice is a menu bar app, and macOS does not always let it come to the
/// front: neither activate() nor a click on its window is enough. A panel
/// that does not activate the app still takes the keyboard, the way
/// Spotlight does.
private final class ScratchpadPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
