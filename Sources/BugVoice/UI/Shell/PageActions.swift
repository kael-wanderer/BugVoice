import AppKit
import BugVoiceMac
import SwiftUI
import UniformTypeIdentifiers
import VoiceCore

struct PageActions: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    var body: some View {
        Group {
            switch model.page {
            case .dictation:
                Button { if !model.permissionsGranted { model.openPermissionsWindow() } } label: {
                    HStack(spacing: LayoutTokens.spacing[1]) {
                        Circle().fill(model.permissionsGranted ? store.theme.success : store.theme.warning)
                            .frame(width: store.scaled(6), height: store.scaled(6))
                        Text(model.permissionsGranted ? "Hold \(model.settings.hotkey.spokenName) to speak" : "Permissions needed")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .bvFont(.footnote)
                    .padding(.horizontal, LayoutTokens.spacing[2]).padding(.vertical, LayoutTokens.spacing[1])
                    .background(.bvHover, in: Capsule())
                }.buttonStyle(.plain)
            case .insights:
                RoundPills("Range", items: [InsightsPeriod.days7, .days30, .all].map { ($0, $0.title) }, selection: $model.insightsPeriod, size: .small)
            case .meetings:
                if model.meetings?.isRecording == true || model.meetings?.isPaused == true {
                    Button("Stop") { Task { await model.meetings?.stop(); await model.reloadMeetings() } }
                        .buttonStyle(.borderedProminent)
                } else if model.meetings?.isTranscribing == true {
                    Label("Transcribing…", systemImage: "hourglass").bvFont(.body)
                } else {
                    SplitButton("Record meeting", systemImage: "record.circle", action: startMeeting) {
                        Button("Record meeting", action: startMeeting).keyboardShortcut("m", modifiers: [.control, .option])
                        Button("Upload a recording…") { model.page = .upload }
                    }
                }
            case .notes:
                SplitButton("New note", systemImage: "plus", action: newNote) {
                    Button("Note", action: newNote).keyboardShortcut("n", modifiers: .command)
                    Button("Floating scratchpad") { Task { await model.openScratchpadWindow(newNote: false) } }
                        .keyboardShortcut("n", modifiers: [.control, .option])
                    Divider()
                    Button("Ask AI about my notes") { Task { await model.openScratchpadAsk() } }
                    Divider()
                    Button("Manage folders and tags…") { model.librarySheet = .folders }
                }
            case .upload:
                Button("Choose files…") { model.chooseUploadFiles() }.buttonStyle(.borderedProminent)
                    .disabled(model.uploads?.accepting != true)
            case .dictionary:
                SplitButton("Add", systemImage: "plus", action: { model.requestDictionaryAdd() }) {
                    Button("Word") { model.requestDictionaryAdd(.words) }
                    Button("Snippet") { model.requestDictionaryAdd(.snippets) }
                }.disabled(model.dictionaryReadOnly)
            default: EmptyView()
            }
        }.bvFont(.body)
    }
    private func newNote() { Task { await model.openScratchpadWindow(newNote: true) } }
    private func startMeeting() { Task { await model.meetings?.start() } }
}

extension AppModel {
    func chooseUploadFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MediaAudioDecoder.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        Task { await uploads?.choose(panel.urls) }
    }
}
