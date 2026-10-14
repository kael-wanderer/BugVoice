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
    private lazy var permissionsWindow = PermissionsWindowController(model: model)
    private var meetingRecorderPanel: MeetingRecorderPanel?
    private var sleepObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.presentMainWindow = { [weak self] in self?.mainWindow.show() }
        model.presentPermissionsWindow = { [weak self] in self?.permissionsWindow.show() }
        installEditMenu()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.model.meetings?.pauseForSleep() }
        }
        Task {
            await model.bootstrap()
            guard let controller = model.meetings else { return }
            let panel = MeetingRecorderPanel(controller: controller)
            meetingRecorderPanel = panel
            controller.onRecordingStarted = { [weak panel] in panel?.show() }
            controller.onRecordingStopped = { [weak panel] in panel?.hide() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let meetings = model.meetings
        let meetingIsActive = meetings?.isRecording == true || meetings?.isPaused == true
        if meetingIsActive {
            let alert = NSAlert()
            alert.messageText = "A meeting is recording"
            alert.informativeText = "Stop the recording and keep the audio before quitting? The transcript can finish later."
            alert.addButton(withTitle: "Stop and keep")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        } else if !model.notesController.hasUnsavedChanges {
            return .terminateNow
        }

        Task { [weak self] in
            guard let self else {
                NSApp.reply(toApplicationShouldTerminate: false)
                return
            }
            do {
                guard await model.notesController.flushAll() else {
                    model.saveError = "Could not save notes before quitting. Resolve the note changes and try again."
                    NSApp.reply(toApplicationShouldTerminate: false)
                    return
                }
                if meetingIsActive, let meetings { try await meetings.stopAndKeepForQuit() }
                NSApp.reply(toApplicationShouldTerminate: true)
            } catch {
                model.saveError = meetingIsActive
                    ? "Could not checkpoint the meeting before quitting: \(error.localizedDescription)"
                    : "Could not save notes before quitting: \(error.localizedDescription)"
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}
