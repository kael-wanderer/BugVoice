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
        installEditMenu()
        Task { await model.bootstrap() }
    }

    /// The app has no document scenes, so SwiftUI builds no Edit menu. Without
    /// one, ⌘C / ⌘V / ⌘X / ⌘A do nothing in Settings text fields.
    private func installEditMenu() {
        let main = NSApp.mainMenu ?? NSMenu()
        guard !main.items.contains(where: { $0.title == "Edit" }) else { return }
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = edit
        main.addItem(item)
        NSApp.mainMenu = main
    }

    /// Clicking the Dock icon (shown while the main window is open, or when
    /// launched from Finder again) brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.openMainWindow()
        return false
    }
}
