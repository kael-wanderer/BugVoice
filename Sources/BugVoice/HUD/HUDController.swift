import AppKit
import SwiftUI

/// Floating, non-activating pill at the bottom-center of the screen with the
/// mouse. It never takes focus, so the paste lands in the user's app.
@MainActor
final class HUDController {
    let model = HUDModel()
    var levelSource: (() -> Float)?
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?
    private var meterTimer: Timer?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 60),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
    }

    func show(_ state: HUDState) {
        hideTask?.cancel()
        model.state = state
        if case .listening = state { startMeter() } else { stopMeter() }
        layout()
        panel.orderFrontRegardless()
        if let delay = state.autoHideAfter {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        stopMeter()
        model.state = nil
        panel.orderOut(nil)
    }

    private func layout() {
        guard let view = panel.contentView else { return }
        let size = view.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + 40, width: size.width, height: size.height), display: true)
    }

    private func startMeter() {
        stopMeter()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.level = self.levelSource?() ?? 0
            }
        }
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
        model.level = 0
    }
}
