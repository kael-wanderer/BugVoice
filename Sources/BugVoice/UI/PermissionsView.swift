import AppKit
import BugVoiceMac
import SwiftUI
import VoiceCore

struct PermissionsView: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(.microphone, "Microphone", "To hear what you say.", "mic")
            Divider()
            row(.accessibility, "Accessibility", "To find the focused text field and paste into it.", "accessibility")
            Divider()
            row(.inputMonitoring, "Input Monitoring", "To notice when you hold the hotkey. Keys are watched, never recorded.", "keyboard")
            Divider()
            systemAudioRow
            Text("Nothing you say leaves this Mac unless you set a remote server in Settings → Models or Settings → Speech.")
                .bvFont(.footnote).foregroundStyle(.bvSecondary).padding(.top, LayoutTokens.spacing[2])
        }
        .padding(LayoutTokens.spacing[4])
        .frame(width: store.scaled(540))
    }

    private var systemAudioRow: some View {
        HStack(spacing: LayoutTokens.spacing[2]) {
            Image(systemName: "speaker.wave.2")
                .frame(width: 34, height: 34)
                .background(.bvHover, in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
            VStack(alignment: .leading) {
                Text("System Audio Recording").fontWeight(.semibold)
                Text(model.systemAudioPermissionFailed
                    ? "Allow BugVoice under Privacy & Security → Screen & System Audio Recording."
                    : "Requested when the first meeting starts")
                    .bvFont(.body).foregroundStyle(.bvSecondary)
            }
            Spacer()
            if model.systemAudioPermissionFailed {
                Button("Open System Settings") { Permissions.openSettings(.systemAudioRecording) }
                    .buttonStyle(.borderedProminent)
            } else if model.permissionStatus[.systemAudioRecording] == true {
                Text("Granted").foregroundStyle(.bvSuccess)
            }
        }
        .padding(.vertical, LayoutTokens.spacing[2])
    }

    @ViewBuilder
    func row(_ kind: PermissionKind, _ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(spacing: LayoutTokens.spacing[2]) {
            Image(systemName: symbol)
                .frame(width: 34, height: 34)
                .background(.bvHover, in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
            VStack(alignment: .leading) {
                Text(title).fontWeight(.semibold)
                Text(detail).bvFont(.body).foregroundStyle(.bvSecondary)
            }
            Spacer()
            if model.permissionStatus[kind] == true {
                if kind == .inputMonitoring, !model.hotkeyActive {
                    // The event tap cannot be created until the app restarts
                    // after the grant.
                    Button("Restart BugVoice") { relaunch() }
                } else {
                    Text("Granted").foregroundStyle(.bvSuccess)
                }
            } else {
                Button("Open System Settings") {
                    Task { await Permissions.request(kind) }
                    Permissions.openSettings(kind)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, LayoutTokens.spacing[2])
    }

    func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// Owns the Permissions window. Same shape as `MainWindowController`.
@MainActor
final class PermissionsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private var pollTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        startPolling()
    }

    /// Re-checks the grants once a second while the window is open. The
    /// window is kept alive after closing, so this task is owned here and
    /// cancelled in `windowWillClose`.
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
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Permissions"
        window.identifier = AppWindow.permissions
        window.contentViewController = NSHostingController(rootView: PermissionsView(model: model).bvTheme(model.appearance))
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
        AppWindow.didClose(notification.object as? NSWindow)
    }
}
