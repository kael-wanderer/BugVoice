import AppKit
import SwiftUI
import VoiceCore

struct StorageTab: View {
    @Bindable var model: AppModel
    @State private var sizes: [String: Int64] = [:]
    @State private var confirmClear = false
    @State private var confirmDontSave = false

    var body: some View {
        Form {
            LabeledContent("Data folder") {
                HStack {
                    Text(model.paths.root.path).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.paths.root]) }
                }
            }
            LabeledContent("Disk used", value: format(sizes.values.reduce(0, +)))
            Section {
                row("Speech models", path: model.paths.models, detail: model.settings.speech.whisperModel) {
                    Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([model.paths.models]) }
                }
                row("Dictation history", path: model.paths.history, detail: "\(model.history.count) entries") {
                    Button("Clear…") { confirmClear = true }
                }
                row("Last recording (last.wav)", path: model.paths.lastRecording, detail: "1 file") { EmptyView() }
                if FileManager.default.fileExists(atPath: model.paths.meetings.path) {
                    row("Meetings", path: model.paths.meetings, detail: "") { EmptyView() }
                }
                if FileManager.default.fileExists(atPath: model.paths.notes.path) {
                    row("Notes", path: model.paths.notes, detail: "") { EmptyView() }
                }
            }
            Picker("Keep dictation history", selection: retentionBinding) {
                Text("Forever").tag(Retention.forever)
                Text("30 days").tag(Retention.days30)
                Text("7 days").tag(Retention.days7)
                Text("Don't save").tag(Retention.off)
            }
        }
        .formStyle(.grouped)
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
        HStack {
            Text(title)
            Spacer()
            Text(detail).foregroundStyle(.secondary)
            Text(format(sizes[path.path] ?? 0)).monospacedDigit().frame(width: 90, alignment: .trailing)
            action()
        }
    }

    func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func measure() async {
        let urls = [model.paths.models, model.paths.history, model.paths.lastRecording, model.paths.meetings, model.paths.notes]
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
