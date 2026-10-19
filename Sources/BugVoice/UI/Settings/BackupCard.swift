import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoiceCore

struct BackupCard: View {
    @Bindable var model: AppModel
    @State private var lastFolder: URL?
    @State private var restoreFile: URL?
    @State private var showingRestore = false
    @State private var confirmDelete = false
    @State private var panel: NSSavePanel?

    private var controller: BackupController { model.backup }
    private var busy: Bool {
        if case .backingUp = controller.activity { return true }
        return false
    }
    private var backupType: UTType { UTType(filenameExtension: BackupNaming.fileExtension) ?? .data }

    var body: some View {
        SettingsCard(title: "Backup") {
            Text("Back up notes, meetings, history, Dictionary, folders and tags, and settings to one file.")
            if case let .backingUp(done, total) = controller.activity {
                SettingsRow(title: "Backing up… \(done) of \(total) files") {
                    Button("Cancel") { controller.cancel() }
                }
                ProgressView(value: Double(done), total: Double(max(1, total)))
            }
            FlowLayout(spacing: LayoutTokens.spacing[1]) {
                Button("Back up now…", action: saveBackup).buttonStyle(.borderedProminent).disabled(busy)
                Button("Restore…", action: chooseRestore).disabled(busy)
            }
            switch controller.activity {
            case let .done(message, file, note):
                Text(message).foregroundStyle(.green)
                Button("Show in Finder") { reveal(file) }
                if let note { Text(note).bvFont(.footnote).foregroundStyle(.bvSecondary) }
            case let .failed(message): Text(message).foregroundStyle(.red)
            default: EmptyView()
            }
            Divider()
            SettingsRow(title: "Back up automatically") {
                Picker("Back up automatically", selection: frequency) {
                    Text("Off").tag(BackupFrequency.off)
                    Text("Daily").tag(BackupFrequency.daily)
                    Text("Weekly").tag(BackupFrequency.weekly)
                }.labelsHidden().fixedSize()
            }
            if let folder = controller.backupFolder {
                Text(folder.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .bvCode(.footnote).lineLimit(1).truncationMode(.middle).help(folder.path)
                FlowLayout(spacing: LayoutTokens.spacing[1]) {
                    Button("Change…") { chooseFolder(enabling: nil) }
                    Button("Show in Finder") { reveal(folder) }
                }
                if controller.folderMissing {
                    Text("The backup folder is missing. Connect the drive or choose another folder.")
                        .bvFont(.footnote).foregroundStyle(.bvSecondary)
                } else {
                    Text("Last backup: \(controller.lastBackup.map { relative($0.date) } ?? "Never") · \(controller.lastBackup.map { size($0.bytes) } ?? "0 bytes") · Next: \(controller.nextBackup.map(relative) ?? "Off"). Keeps the newest 5.")
                        .bvFont(.footnote).foregroundStyle(.bvSecondary)
                }
            } else if controller.folderMissing {
                Text("The backup folder is missing. Connect the drive or choose another folder.")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
                Button("Change…") { chooseFolder(enabling: nil) }
            }
            Text("API keys and speech models are not included.").bvFont(.footnote).foregroundStyle(.bvSecondary)
            if let safety = controller.safetyCopy {
                Divider()
                Text("Safety copy from before the restore on \(safety.date.formatted(date: .abbreviated, time: .shortened)) · \(size(safety.bytes))")
                FlowLayout(spacing: LayoutTokens.spacing[1]) {
                    Button("Show in Finder") { reveal(safety.url) }
                    Button("Delete…", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .sheet(isPresented: $showingRestore) {
            if let restoreFile { RestoreSheet(model: model, archive: restoreFile) }
        }
        .confirmationDialog("Delete the safety copy?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { controller.deleteSafetyCopy() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var frequency: Binding<BackupFrequency> {
        Binding(get: { model.settings.backup.frequency }, set: { choice in
            if choice != .off, controller.backupFolder == nil {
                chooseFolder(enabling: choice)
            } else { model.settings.backup.frequency = choice }
        })
    }

    private func saveBackup() {
        let save = NSSavePanel()
        save.allowedContentTypes = [backupType]
        save.directoryURL = lastFolder ?? controller.backupFolder
        save.nameFieldStringValue = BackupNaming.fileName(at: .now, timeZone: .current, taken: [])
        panel = save
        save.begin { response in
            defer { panel = nil }
            guard response == .OK, let url = save.url else { return }
            lastFolder = url.deletingLastPathComponent()
            Task { await controller.backUpNow(to: url) }
        }
    }

    private func chooseRestore() {
        let open = NSOpenPanel()
        open.allowedContentTypes = [backupType]
        open.allowsOtherFileTypes = false
        open.allowsMultipleSelection = false
        open.directoryURL = lastFolder ?? controller.backupFolder
        panel = open
        open.begin { response in
            defer { panel = nil }
            guard response == .OK, let url = open.url else { return }
            lastFolder = url.deletingLastPathComponent()
            restoreFile = url
            showingRestore = true
        }
    }

    private func chooseFolder(enabling choice: BackupFrequency?) {
        let open = NSOpenPanel()
        open.canChooseFiles = false
        open.canChooseDirectories = true
        open.canCreateDirectories = true
        open.allowsMultipleSelection = false
        let initial = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/BugVoice Backups", isDirectory: true)
        do { try FileManager.default.createDirectory(at: initial, withIntermediateDirectories: true) }
        catch { model.saveError = "Could not create the backup folder: \(error.localizedDescription)"; return }
        open.directoryURL = controller.backupFolder ?? initial
        panel = open
        open.begin { response in
            defer { panel = nil }
            guard response == .OK, let url = open.url else {
                if choice != nil { model.settings.backup.frequency = .off }
                return
            }
            controller.setBackupFolder(url)
            if let choice, controller.backupFolder != nil { model.settings.backup.frequency = choice }
        }
    }

    private func relative(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    private func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
