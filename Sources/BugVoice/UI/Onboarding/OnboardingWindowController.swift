import AppKit
import SwiftUI
import VoiceCore

/// Owns the onboarding window. Same shape as `PermissionsWindowController`:
/// the window is kept, the activation policy is regular while it shows, and
/// permissions are polled once a second only while it is open. Closing the
/// window counts as skipping setup.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private var pollTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
    }

    func show(at step: OnboardingStep = .welcome) {
        let window = self.window ?? makeWindow()
        self.window = window
        // A fresh root view each time, so the window starts at `step`.
        window.contentViewController = NSHostingController(
            rootView: OnboardingView(model: model, start: step) { [weak self] in self?.window?.close() }
                .bvTheme(model.appearance))
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [model] in
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Setup"
        window.identifier = AppWindow.onboarding
        model.appearance.attach(window)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        AppWindow.placeForDevelopment(window)
        return window
    }

    func windowWillClose(_ notification: Notification) {
        pollTask?.cancel()
        pollTask = nil
        model.finishOnboarding()
        // Drop the view so its work (the 5b download follow-up, the self-test) stops.
        // `show` makes a fresh root view anyway.
        (notification.object as? NSWindow)?.contentViewController = nil
        AppWindow.didClose(notification.object as? NSWindow)
    }
}
