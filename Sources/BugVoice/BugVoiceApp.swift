import AppKit
import SwiftUI

@main
struct BugVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: delegate.model)
        } label: {
            MenuBarIcon(model: delegate.model)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Start-up and the main window live here, not on a SwiftUI view: the menu
/// bar label is not guaranteed to appear (or run `.task`) at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private lazy var mainWindow = MainWindowController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.presentMainWindow = { [weak self] in self?.mainWindow.show() }
        Task { await model.bootstrap() }
    }

    /// Clicking the Dock icon (shown while the main window is open, or when
    /// launched from Finder again) brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.openMainWindow()
        return false
    }
}
