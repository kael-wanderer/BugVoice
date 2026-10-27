import BugVoiceMac
import SwiftUI
import VoiceCore

struct GeneralTab: View {
    @Bindable var model: AppModel

    @State private var librarySheet: LibrarySheetTab?

    var body: some View {
        SettingsScroll {
            SettingsCard {
                SettingsRow(title: "Hotkey") {
                    Picker("Hotkey", selection: $model.settings.hotkey) {
                        ForEach(HotkeyKey.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                Text("Hold to talk. Pressing another key cancels.").bvFont(.footnote).foregroundStyle(.bvSecondary)
                Divider()
                SettingsRow(title: "Command key") {
                    Picker("Command key", selection: Binding(get: { model.settings.effectiveCommandKey }, set: { model.settings.commandKey = $0 })) {
                        ForEach(CommandKey.allCases.filter { $0.hotkeyKey != model.settings.hotkey }, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }.labelsHidden().fixedSize()
                }
                Text("Select text, hold the command key and say what to change. With nothing selected, say what to write.")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
                Divider()
                SettingsToggle(title: "Hands-free: double-tap the hotkey to start, tap once to stop", isOn: $model.settings.handsFreeEnabled)
                Divider()
                SettingsRow(title: "Hands-free limit") {
                    Picker("Hands-free limit", selection: $model.settings.handsFreeLimitMinutes) {
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("20 minutes").tag(20)
                    }
                    .labelsHidden().fixedSize()
                }
            }
            SettingsCard(title: "Folders and tags") {
                SettingsRow(title: "\(counted(model.library.folders.count, "folder")) · \(counted(model.tagRows.count, "tag"))") {
                    Button("Manage…") { librarySheet = .folders }
                }
            }
            SettingsCard {
                SettingsToggle(title: "Start and stop sounds", isOn: $model.settings.soundsEnabled)
                Divider()
                SettingsToggle(title: "Put the previous clipboard back after pasting", isOn: $model.settings.restoreClipboard)
                Divider()
                SettingsToggle(title: "Launch at login", isOn: $model.settings.launchAtLogin)
            }
            UpdatesCard(model: model)
        }
        .sheet(item: $librarySheet) { ManageLibrarySheet(model: model, tab: $0) }
    }
}

/// Settings › General › Updates: the running build, a check against the
/// published feed, and the launch-and-daily switch. An offer opens the release
/// page in the browser; BugVoice never downloads or installs itself.
private struct UpdatesCard: View {
    @Bindable var model: AppModel

    private enum CheckState: Equatable {
        case checking
        case failed(UpdateFeedFailure)
        case upToDate(String)
        case offer(UpdateAvailable)
    }

    @State private var state: CheckState = .checking

    var body: some View {
        SettingsCard(title: "Updates") {
            SettingsRow(title: "Version") {
                Text(Log.appVersion).monospacedDigit().foregroundStyle(.bvSecondary)
            }
            Divider()
            SettingsRow(title: "Check for updates") {
                Button(label) {
                    if case .offer(let update) = state {
                        NSWorkspace.shared.open(update.releaseURL)
                    } else {
                        Task { await check() }
                    }
                }
                .disabled(state == .checking)
            }
            Text(note).bvFont(.footnote).foregroundStyle(isFailure ? .bvWarning : .bvSecondary)
            Divider()
            SettingsToggle(title: "Check at launch and daily, and show new versions in the menu", isOn: $model.settings.updateNotify)
        }
        // One check per visit to the tab, not per render, and again on Check for Updates….
        .task(id: model.updateCheckRequest) { await check() }
    }

    private func check() async {
        state = .checking
        let result = await UpdateFeed.fetch()
        switch result {
        case .unavailable(let failure):
            state = .failed(failure)
        case .success(let feed):
            let update = UpdateSelection.pick(feed, currentVersion: AppFeedVersion.string())
            if model.settings.updateNotify { model.availableUpdate = update }
            state = update.map(CheckState.offer) ?? .upToDate(feed.version)
        }
    }

    private var isFailure: Bool {
        if case .failed = state { return true }
        return false
    }

    /// A failure says Retry, never "up to date": a check that did not happen
    /// must not read as one that succeeded.
    private var label: String {
        switch state {
        case .checking: "Checking…"
        case .failed: "Retry"
        case .upToDate: "Check again"
        case .offer(let update): "Open \(update.version)"
        }
    }

    private var note: String {
        switch state {
        case .checking: "Comparing this build with the newest published release."
        case .failed(.timeout), .failed(.transport): "BugVoice could not reach the update feed. Check your connection."
        case .failed(.notFound), .failed(.serverError): "The update feed is not answering right now. Try again later."
        case .failed(.malformed): "The update feed could not be read, so no version was compared."
        case .upToDate(let latest): "Up to date. The newest release is \(latest)."
        case .offer(let update): "BugVoice \(update.version) is available. Open shows its release page in your browser."
        }
    }
}
