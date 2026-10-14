import AppKit
import SwiftUI

private final class NonKeyMeetingHostingView: NSHostingView<MeetingRecorderView> {
    override var acceptsFirstResponder: Bool { false }
}

@MainActor
final class MeetingRecorderPanel {
    private let controller: MeetingController
    private let panel: NSPanel
    private var screenObserver: NSObjectProtocol?

    init(controller: MeetingController) {
        self.controller = controller
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 190),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NonKeyMeetingHostingView(rootView: MeetingRecorderView(controller: controller))
        panel.setAccessibilityLabel("Meeting recorder")
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.position() }
        }
    }

    func show() {
        position()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func position() {
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        guard !frame.isEmpty else { return }
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 72))
    }
}
