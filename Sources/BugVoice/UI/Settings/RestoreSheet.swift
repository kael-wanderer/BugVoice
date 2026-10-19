import SwiftUI
import VoiceCore

struct RestoreSheet: View {
    let model: AppModel
    let archive: URL
    @Environment(\.dismiss) private var dismiss
    @State private var manifest: BackupManifest?
    @State private var failure: BackupError?
    @State private var inspecting = true
    @State private var preparing = false
    @State private var restoreFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
            Text(restoreFailed ? "Restore did not finish" : "Restore this backup?").bvFont(.title3)
            if let manifest {
                Grid(alignment: .leading, horizontalSpacing: LayoutTokens.spacing[3], verticalSpacing: LayoutTokens.spacing[1]) {
                    fact("Made", manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
                    fact("From", "BugVoice \(manifest.appVersion) (\(manifest.build))")
                    fact("Notes", "\(manifest.counts.notes)")
                    fact("Meetings", "\(manifest.counts.meetings)")
                    fact("Dictations", "\(manifest.counts.dictations)")
                    fact("Dictionary", "\(manifest.counts.dictionaryWords) words")
                    fact("Folders, tags", "\(manifest.counts.folders) \(manifest.counts.folders == 1 ? "folder" : "folders"), \(manifest.counts.tags) \(manifest.counts.tags == 1 ? "tag" : "tags")")
                }.padding(LayoutTokens.spacing[2]).bvCard()
            }
            if let failure {
                callout(failure.localizedDescription, error: true)
            } else if inspecting {
                ProgressView("Reading backup…")
            } else {
                callout("This replaces all notes, meetings, dictation history, Dictionary, folders and tags, and settings in BugVoice. Your current library is kept as a safety copy.")
                callout("API keys are not in backups. Enter them again in Settings › Models.")
            }
            if preparing { ProgressView("Preparing…") }
            Divider()
            HStack {
                Spacer()
                if failure != nil {
                    Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(preparing)
                    Button("Restore and relaunch") {
                        preparing = true
                        Task {
                            if let error = await model.backup.restoreAndRelaunch(archive) {
                                failure = error
                                if case .damaged = error { restoreFailed = true }
                                if case .failed = error { restoreFailed = true }
                                preparing = false
                            } else {
                                // BugVoice is quitting to finish the restore.
                                preparing = false
                                dismiss()
                            }
                        }
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(inspecting || preparing)
                }
            }
        }
        .padding(LayoutTokens.spacing[4])
        .frame(minWidth: 400, idealWidth: 460, maxWidth: 560)
        .interactiveDismissDisabled(preparing)
        .onChange(of: model.backup.relaunchError) { _, error in
            guard preparing, let error else { return }
            preparing = false
            failure = error
            restoreFailed = true
        }
        .task {
            switch await model.backup.inspect(archive) {
            case .success(let value): manifest = value
            case .failure(let error): failure = error
            }
            inspecting = false
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.bvSecondary)
            Text(value).bvFont(.bodyStrong)
        }
    }

    private func callout(_ message: String, error: Bool = false) -> some View {
        Text(message).bvFont(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            .padding(LayoutTokens.spacing[2]).bvCard()
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(error ? Color.red : Color.clear))
    }
}
