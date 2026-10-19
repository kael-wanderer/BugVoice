import AppKit
import BugVoiceMac
import SwiftUI
import VoiceCore

@main
struct BugVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Hidden: the menu bar icon and popover are `MenuPanelController`.
        // The scene stays only to carry the View menu commands.
        MenuBarExtra("BugVoice", isInserted: .constant(false)) { EmptyView() }
            .commands { delegate.installViewMenu() }
    }
}

/// Start-up, the menu bar popover and the main window live here, not on a
/// SwiftUI view.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private lazy var mainWindow = MainWindowController(model: model)
    private lazy var permissionsWindow = PermissionsWindowController(model: model)
    private lazy var scratchpadWindow = ScratchpadWindowController(model: model)
    private var meetingWindow: MeetingWindowController?
    private var menuPanel: MenuPanelController?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var textSizeAlternateMonitor: Any?
    private var launchReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice("launch \(Log.appVersion, privacy: .public) on \(Log.systemVersion, privacy: .public)")
        Task { @MainActor in
            // Return from the delegate callback so Workspace can notify the old
            // instance, then wait until its final saves and termination finish.
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--restore-after-process"),
               arguments.indices.contains(index + 1), let pid = Int32(arguments[index + 1]),
               pid != ProcessInfo.processInfo.processIdentifier {
                let ready = VoiceCore.RestoreApplier.pendingDirectory(for: model.paths.root).appendingPathComponent("ready")
                while let previous = NSRunningApplication(processIdentifier: pid), !previous.isTerminated {
                    guard FileManager.default.fileExists(atPath: ready.path) else {
                        NSApp.terminate(nil)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            model.restoreMessage = BackupController.applyPendingRestore(root: model.paths.root)
            finishLaunching()
        }
    }

    private func finishLaunching() {
        launchReady = true
        FontRegistry.registerBundledFonts()
        menuPanel = MenuPanelController(model: model)
        model.presentMainWindow = { [weak self] in
            self?.mainWindow.show()
        }
        model.presentPermissionsWindow = { [weak self] in
            self?.permissionsWindow.show()
        }
        model.scratchpadWindow = scratchpadWindow
        installEditMenu()
        installTextSizeAlternate()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model.uploads?.setSleeping(true)
                await self?.model.meetings?.pauseForSleep()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.model.uploads?.setSleeping(false) }
        }
        Task {
            await model.bootstrap()
            guard let controller = model.meetings else { return }
            let window = MeetingWindowController(model: model, controller: controller)
            meetingWindow = window
            controller.onShowWindow = { [weak window] in window?.show() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard launchReady else { return }
        Task { @MainActor in
            await model.notesController.refreshAll(trigger: .appActivation)
        }
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
        edit.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = edit
        main.addItem(item)
        NSApp.mainMenu = main
    }

    /// SwiftUI hides the alternate menu item without enabling hidden key equivalents.
    /// Local key events also reach the floating panels and their AppKit editors.
    private func installTextSizeAlternate() {
        guard textSizeAlternateMonitor == nil else { return }
        textSizeAlternateMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
                  event.charactersIgnoringModifiers == "=" else { return event }
            let handled = MainActor.assumeIsolated {
                guard let self else { return false }
                self.model.settings.appearance.stepTextScale(by: 10)
                return true
            }
            return handled ? nil : event
        }
    }

    func installViewMenu() -> some Commands {
        CommandGroup(before: .toolbar) {
            Button(model.sidebarHidden ? "Show Sidebar" : "Hide Sidebar") { self.model.toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .disabled(!model.mainWindowIsKey)
            Button("Search") {
                self.model.openMainWindow()
                self.model.searchFocusRequest &+= 1
            }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(NSApp.keyWindow != nil && !model.mainWindowIsKey)
            Divider()
            Button("Bigger Text") { self.model.settings.appearance.stepTextScale(by: 10) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Bigger Text") { self.model.settings.appearance.stepTextScale(by: 10) }
                .keyboardShortcut("=", modifiers: .command)
                .hidden()
            Button("Smaller Text") { self.model.settings.appearance.stepTextScale(by: -10) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { self.model.settings.appearance.resetTextScale() }
                .keyboardShortcut("0", modifiers: .command)
        }
    }

    /// Clicking the Dock icon (shown while the main window is open, or when
    /// launched from Finder again) brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
    {
        guard launchReady else { return false }
        model.openMainWindow()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.mcp.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Log.app.notice("quit requested")
        let meetings = model.meetings
        let meetingIsActive = meetings?.isRecording == true || meetings?.isPaused == true
        if meetingIsActive {
            let alert = NSAlert()
            alert.messageText = "A meeting is recording"
            alert.informativeText =
                "Stop the recording and keep the audio before quitting? The transcript can finish later."
            alert.addButton(withTitle: "Stop and keep")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                model.backup.cancelPendingRelaunch()
                return .terminateCancel
            }
        } else if !model.notesController.hasUnsavedChanges && model.uploads?.isBusy != true {
            return .terminateNow
        }
        let backup = model.backup
        Task { [weak self] in
            guard let self else {
                backup.cancelPendingRelaunch()
                NSApp.reply(toApplicationShouldTerminate: false)
                return
            }
            do {
                guard await model.notesController.flushAll() else {
                    model.saveError =
                        "Could not save notes before quitting. Resolve the note changes and try again."
                    model.backup.cancelPendingRelaunch()
                    NSApp.reply(toApplicationShouldTerminate: false)
                    return
                }
                if meetingIsActive, let meetings { try await meetings.stopAndKeepForQuit() }
                await model.uploads?.quiesceForQuit()
                NSApp.reply(toApplicationShouldTerminate: true)
            } catch {
                model.saveError =
                    meetingIsActive
                    ? "Could not checkpoint the meeting before quitting: \(error.localizedDescription)"
                    : "Could not save notes before quitting: \(error.localizedDescription)"
                model.backup.cancelPendingRelaunch()
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}
