import AppKit
import SwiftUI

struct MainWindow: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $model.page) { page in
                Label(page.title, systemImage: page.symbol).tag(page)
            }
            .safeAreaInset(edge: .top) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                    Text("BugVoice").font(.headline)
                    Text("Local")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            switch model.page {
            case .dictation: DictationHistoryView(model: model)
            case .settings: SettingsView(model: model)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .alert("Could not save", isPresented: Binding(
            get: { model.saveError != nil },
            set: { if !$0 { model.saveError = nil } }
        )) {
            Button("OK") { model.saveError = nil }
        } message: {
            Text(model.saveError ?? "")
        }
    }
}

/// Owns the main window. AppKit-managed rather than a SwiftUI `Window` scene
/// so that app code (menu, global shortcut ⌃⌥B, Dock click) can open it
/// without a SwiftUI view having to relay `openWindow`.
///
/// The app is `LSUIElement`; while this window is open it switches to a
/// regular app so it has a Dock icon and a ⌘-Tab entry, and back when it
/// closes.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "BugVoice"
        window.contentViewController = NSHostingController(rootView: MainWindow(model: model))
        window.isReleasedWhenClosed = false
        window.delegate = self
        if !window.setFrameUsingName("BugVoiceMain") {
            window.setContentSize(NSSize(width: 1000, height: 680))
            window.center()
        }
        window.setFrameAutosaveName("BugVoiceMain")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
