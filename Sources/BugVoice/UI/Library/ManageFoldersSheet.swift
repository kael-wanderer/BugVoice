import SwiftUI
import VoiceCore

struct ManageFoldersSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: FolderID?
    @State private var draft = ""
    @State private var error: String?
    @State private var pendingDelete: LibraryFolder?
    @State private var creating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Folders").font(.headline)
            if model.sortedFolders.isEmpty {
                Text("No folders yet.").foregroundStyle(.secondary)
            }
            ForEach(model.sortedFolders) { folder in
                HStack(spacing: 8) {
                    if editing == folder.id {
                        TextField("Folder name", text: $draft).onSubmit { save(folder.id) }
                    } else {
                        Label(folder.name, systemImage: "folder")
                    }
                    Spacer()
                    Text(countText(folder.id)).font(.caption).foregroundStyle(.secondary)
                    if editing == folder.id {
                        Button("Save") { save(folder.id) }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Rename") { editing = folder.id; draft = folder.name; error = nil }
                        Button("Delete", role: .destructive) { pendingDelete = folder }
                    }
                }
                .disabled(model.libraryReadOnly)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("+ New folder") { creating = true }.disabled(model.libraryReadOnly)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            Text("Deleting a folder moves its meetings and notes to Unfiled. Nothing is deleted, and files on disk never move.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 460)
        .sheet(isPresented: $creating) { NewFolderSheet(model: model) { _ in } }
        .confirmationDialog(
            "Delete folder \"\(pendingDelete?.name ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { folder in
            Button("Delete", role: .destructive) { Task { await model.deleteFolder(folder.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its meetings and notes move to Unfiled. No files are deleted.")
        }
    }

    private func countText(_ id: FolderID) -> String {
        let meetings = LibraryProjection.counts(model.meetingManifests, known: model.library.knownIDs).count(id)
        let notes = LibraryProjection.counts(model.notesController.notes, known: model.library.knownIDs).count(id)
        return "\(meetings) \(meetings == 1 ? "meeting" : "meetings") · \(notes) \(notes == 1 ? "note" : "notes")"
    }

    private func save(_ id: FolderID) {
        Task {
            if let failure = await model.renameFolder(id, to: draft) {
                error = failure.errorDescription
            } else {
                editing = nil
                error = nil
            }
        }
    }
}
