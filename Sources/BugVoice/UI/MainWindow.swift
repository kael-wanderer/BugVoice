import AppKit
import SwiftUI

struct MainWindow: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $model.page) { page in
                HStack {
                    Label(page.title, systemImage: page.symbol)
                    Spacer()
                    if page == .upload, let job = model.uploads?.active {
                        UploadRing(progress: job.progress)
                    }
                }
                .tag(page)
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            switch model.page {
            case .dictation: DictationHistoryView(model: model)
            case .insights: InsightsPage(model: model)
            case .dictionary: DictionaryPage(model: model)
            case .style: StylePage(model: model)
            case .meetings: MeetingsPage(model: model)
            case .upload: UploadPage(model: model)
            case .notes: NotesPage(model: model)
            case .settings: SettingsView(model: model)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .alert(
            "Could not save",
            isPresented: Binding(
                get: { model.saveError != nil },
                set: { if !$0 { model.saveError = nil } }
            )
        ) {
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
        // Title stays for the Window menu and Mission Control but is not drawn;
        // the sidebar runs under the transparent title bar.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.identifier = AppWindow.main
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
        AppWindow.didClose(notification.object as? NSWindow)
    }
}

/// Identifiers for BugVoice's own windows, and the shared rule for the
/// activation policy: regular while any of them is visible, accessory after
/// the last one closes.
@MainActor
enum AppWindow {
    static let main = NSUserInterfaceItemIdentifier("BugVoiceMain")
    static let permissions = NSUserInterfaceItemIdentifier("BugVoicePermissions")

    static func didClose(_ closing: NSWindow?) {
        let ours: Set<NSUserInterfaceItemIdentifier> = [main, permissions]
        let otherVisible = NSApp.windows.contains {
            $0 !== closing && ($0.isVisible || $0.isMiniaturized)
                && ($0.identifier.map(ours.contains) ?? false)
        }
        if !otherVisible { NSApp.setActivationPolicy(.accessory) }
    }
}
