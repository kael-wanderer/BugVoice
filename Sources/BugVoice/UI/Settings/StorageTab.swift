import AppKit
import BugVoiceMac
import SwiftUI
import VoiceCore

struct StorageTab: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @State private var sizes: [String: Int64] = [:]
    @State private var confirmClear = false
    @State private var confirmDontSave = false
    @State private var confirmResetInsights = false
    @State private var diagnosticsCopied = false

    var body: some View {
        SettingsScroll {
            SettingsCard {
                VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                    Text("Data folder")
                    Text(model.paths.root.path).bvCode(.body).textSelection(.enabled)
                        .lineLimit(1).truncationMode(.middle).help(model.paths.root.path)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([model.paths.root]) }
                }
                Divider()
                SettingsRow(title: "Disk used") {
                    Text(format(sizes.values.reduce(0, +))).foregroundStyle(.bvSecondary)
                }
            }
            SettingsCard {
                row("Speech models", path: model.paths.models, detail: model.settings.speech.whisperModel) {
                    Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([model.paths.models]) }
                }
                Divider()
                row("Dictation history", path: model.paths.history, detail: "\(model.history.count) entries") {
                    Button("Clear…") { confirmClear = true }
                }
                Divider()
                row("Insights", path: model.paths.insights, detail: "\(model.insights.days.count) \(model.insights.days.count == 1 ? "day" : "days")") {
                    Button("Reset…") { confirmResetInsights = true }
                        .disabled(model.insightsReadOnly)
                }
                Divider()
                row("Last recording (last.wav)", path: model.paths.lastRecording, detail: "1 file") { EmptyView() }
                Divider()
                row("Failed recordings", path: model.paths.failedDictations, detail: "\(model.failedDictations.count) \(model.failedDictations.count == 1 ? "file" : "files")") {
                    Button("Clear") { model.clearFailedDictations() }
                        .disabled(model.failedDictations.isEmpty)
                }
                if FileManager.default.fileExists(atPath: model.paths.meetings.path) {
                    Divider()
                    row("Meetings", path: model.paths.meetings, detail: "\(model.meetingManifests.count) meetings") {
                        Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([model.paths.meetings]) }
                    }
                }
                Divider()
                row("Notes", path: model.paths.notes, detail: "\(model.notesController.notes.count) notes") {
                    Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([model.paths.notes]) }
                }
            }
            SettingsCard {
                SettingsRow(title: "Keep dictation history") {
                    Picker("Keep dictation history", selection: retentionBinding) {
                        Text("Forever").tag(Retention.forever)
                        Text("30 days").tag(Retention.days30)
                        Text("7 days").tag(Retention.days7)
                        Text("Don't save").tag(Retention.off)
                    }
                    .labelsHidden().fixedSize()
                }
            }
            BackupCard(model: model)
            SettingsCard {
                SettingsRow(title: "Diagnostics") {
                    Button(diagnosticsCopied ? "Copied" : "Copy diagnostics") { copyDiagnostics() }
                }
                Text("Copies the app version, engine and model names, and this launch's log. Dictated text is never logged.")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
        }
        .task { await measure() }
        .confirmationDialog("Delete all dictation history?", isPresented: $confirmClear) {
            Button("Delete", role: .destructive) { Task { await model.clearHistory(); await measure() } }
        }
        .confirmationDialog("Delete saved dictation history?", isPresented: $confirmDontSave) {
            Button("Delete and stop saving", role: .destructive) {
                model.settings.historyRetention = .off
                Task { await model.clearHistory(); await measure() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choosing Don't save deletes every saved dictation.")
        }
        .confirmationDialog("Reset insights?", isPresented: $confirmResetInsights) {
            Button("Reset", role: .destructive) { Task { await model.resetInsights(); await measure() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Words, streak and activity go back to zero. Dictation history is not affected.")
        }
    }

    /// Choosing Don't save waits for confirmation; Cancel keeps the old value.
    var retentionBinding: Binding<Retention> {
        Binding(
            get: { model.settings.historyRetention },
            set: { choice in
                if choice == .off, model.settings.historyRetention != .off {
                    confirmDontSave = true
                } else {
                    model.settings.historyRetention = choice
                }
            }
        )
    }

    func row(_ title: String, path: URL, detail: String, @ViewBuilder action: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: LayoutTokens.spacing[2]) {
                    Text(title).fixedSize()
                    Spacer(minLength: LayoutTokens.spacing[1])
                    Text(detail).foregroundStyle(.bvSecondary).fixedSize()
                    Text(format(sizes[path.path] ?? 0)).monospacedDigit().fixedSize()
                }
                VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                    Text(title)
                    Text(detail).foregroundStyle(.bvSecondary)
                    Text(format(sizes[path.path] ?? 0)).monospacedDigit()
                }
            }
            Text(path.path).bvCode(.footnote).lineLimit(1).truncationMode(.middle).help(path.path)
                .frame(maxWidth: .infinity, alignment: .leading)
            FlowLayout(spacing: LayoutTokens.spacing[1]) {
                action()
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([path]) }
            }
        }
    }

    func copyDiagnostics() {
        let report = Diagnostics.report(
            appVersion: Log.appVersion, system: Log.systemVersion, hardware: Log.hardware,
            facts: Diagnostics.facts(model.settings), entries: Log.entriesThisLaunch()
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        diagnosticsCopied = true
    }

    func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func measure() async {
        let urls = [model.paths.models, model.paths.history, model.paths.insights, model.paths.lastRecording, model.paths.failedDictations, model.paths.meetings, model.paths.notes]
        sizes = await Task.detached {
            var out: [String: Int64] = [:]
            for url in urls { out[url.path] = Self.size(of: url) }
            return out
        }.value
    }

    nonisolated static func size(of url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? 0
        }
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        for case let file as URL in FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) ?? .init() {
            let values = try? file.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }
}
