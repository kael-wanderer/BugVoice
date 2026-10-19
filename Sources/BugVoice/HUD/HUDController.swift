import AppKit
import SwiftUI
import Observation

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
    private let appearance: AppearanceStore
    private let panel: NSPanel
    private let hosting: SizingHostingView<AnyView>
    private var hideTask: Task<Void, Never>?
    private var meterTimer: Timer?
    private var pillHeight: CGFloat = 0

    init(appearance: AppearanceStore) {
        self.appearance = appearance
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
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hosting = SizingHostingView(rootView: AnyView(EmptyView()))
        hosting.rootView = AnyView(HUDView(model: model, onPillHeightChange: { [weak self] height in
            guard let self, self.pillHeight != height else { return }
            self.pillHeight = height
            self.layout()
        }).bvTheme(appearance, fillsBackground: false))
        hosting.sizingOptions = [.intrinsicContentSize]
        appearance.attach(panel)
        panel.contentView = hosting
        hosting.onSizeChange = { [weak self] in
            MainActor.assumeIsolated { self?.layout() }
        }
        observeAppearance()
    }

    private func observeAppearance() {
        withObservationTracking {
            _ = appearance.settings
            _ = appearance.systemIsDark
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.hosting.layoutSubtreeIfNeeded()
                self?.layout()
                self?.observeAppearance()
            }
        }
    }

    func show(_ state: HUDState) {
        hideTask?.cancel()
        switch state {
        case .done, .warning, .failure, .message, .nothingHeard: model.preview = nil
        default: break
        }
        model.state = state
        switch state {
        case .listening, .commandListening: startMeter()
        default: stopMeter()
        }
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

    func setPreview(_ text: String?) {
        model.preview = text
        hosting.layoutSubtreeIfNeeded()
        layout()
    }

    func hide() {
        hideTask?.cancel()
        stopMeter()
        model.preview = nil
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
        // The original pill had 8 pt of outer padding on both sides. Grow
        // downward by the card and gap to keep the pill in place. With an
        // auto-hidden Dock, lift only enough to keep the card on the display.
        let extra = model.preview == nil ? 0 : max(0, size.height - pillHeight - 16)
        let bottom = max(screen?.frame.minY ?? frame.minY, frame.minY + 40 - extra)
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: bottom,
            width: size.width, height: size.height), display: true)
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
