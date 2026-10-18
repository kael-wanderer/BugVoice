import AppKit
import SwiftUI

/// Hosting view that reports intrinsic size changes to its owner.
private final class SizingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeChange?()
    }
}

/// Floating, non-activating pill at the bottom-center of the screen with the
/// mouse. It never takes focus, so the paste lands in the user's app.
@MainActor
final class HUDController {
    let model = HUDModel()
    var levelSource: (() -> Float)?
    private let panel: NSPanel
    private let hosting: SizingHostingView<AnyView>
    private var hideTask: Task<Void, Never>?
    private var meterTimer: Timer?

    init(appearance: AppearanceStore) {
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
        hosting = SizingHostingView(rootView: AnyView(HUDView(model: model).bvTheme(appearance)))
        hosting.sizingOptions = [.intrinsicContentSize]
        appearance.attach(panel)
        panel.contentView = hosting
        hosting.onSizeChange = { [weak self] in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    func show(_ state: HUDState) {
        hideTask?.cancel()
        model.state = state
        if case .listening = state { startMeter() } else { stopMeter() }
        hosting.layoutSubtreeIfNeeded()
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
        guard model.state != nil else { return }
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + 40, width: size.width, height: size.height), display: true)
    }

    private func startMeter() {
        stopMeter()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.level = self.levelSource?() ?? 0
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
        model.level = 0
    }
}
