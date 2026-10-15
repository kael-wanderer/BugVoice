import SwiftUI
import VoiceCore

/// List-header menu: All, Unfiled, each folder with counts, New folder…, Manage folders….
struct FolderFilterMenu: View {
    let model: AppModel
    @Binding var filter: FolderFilter
    let counts: FolderCounts
    let allTitle: String
    let onManage: () -> Void
    @State private var creating = false

    var body: some View {
        Menu {
            Button { filter = .all } label: { menuLabel(allTitle, count: counts.all, on: filter == .all) }
            Button { filter = .unfiled } label: { menuLabel("Unfiled", count: counts.unfiled, on: filter == .unfiled) }
            Divider()
            ForEach(model.sortedFolders) { folder in
                Button { filter = .folder(folder.id) } label: {
                    menuLabel(folder.name, count: counts.count(folder.id), on: filter == .folder(folder.id))
                }
            }
            Divider()
            Button("New folder…") { creating = true }.disabled(model.libraryReadOnly)
            Button("Manage folders…", action: onManage)
        } label: {
            Label(title, systemImage: "folder")
        }
        .fixedSize()
        .sheet(isPresented: $creating) {
            NewFolderSheet(model: model) { folder in filter = .folder(folder.id) }
        }
    }

    private var title: String {
        switch filter {
        case .all: allTitle
        case .unfiled: "Unfiled"
        case .folder(let id): model.folderName(id) ?? allTitle
        }
    }

    private func menuLabel(_ name: String, count: Int, on: Bool) -> some View {
        HStack {
            if on { Image(systemName: "checkmark") }
            Text("\(name)  \(count)")
        }
    }
}

/// Tags menu plus removable chips. Several chips mean all must match.
struct TagFilterBar: View {
    let catalog: [TagCount]
    @Binding var selected: [String]

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                if catalog.isEmpty { Text("No tags yet") }
                ForEach(catalog) { tag in
                    Button("#\(tag.name)  \(tag.count)") {
                        if !selected.contains(tag.name) { selected.append(tag.name) }
                    }
                }
            } label: {
                Label("Tags", systemImage: "tag")
            }
            .fixedSize()
            ForEach(selected, id: \.self) { tag in
                TagChip(name: tag) { selected.removeAll { $0 == tag } }
            }
        }
    }
}

struct TagChip: View {
    let name: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(name)").font(.caption)
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark").font(.caption2) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove tag \(name)")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}

/// Folder button for a single item: Unfiled, each folder, New folder….
struct FolderPicker: View {
    let model: AppModel
    let folderID: FolderID?
    let onChange: (FolderID?) -> Void
    @State private var creating = false

    var body: some View {
        Menu {
            Button { onChange(nil) } label: { row("Unfiled", on: model.folderName(folderID) == nil) }
            Divider()
            ForEach(model.sortedFolders) { folder in
                Button { onChange(folder.id) } label: { row(folder.name, on: folder.id == folderID) }
            }
            Divider()
            Button("New folder…") { creating = true }.disabled(model.libraryReadOnly)
        } label: {
            Label(model.folderName(folderID) ?? "Unfiled", systemImage: "folder")
        }
        .fixedSize()
        .sheet(isPresented: $creating) {
            NewFolderSheet(model: model) { folder in onChange(folder.id) }
        }
    }

    private func row(_ name: String, on: Bool) -> some View {
        HStack {
            if on { Image(systemName: "checkmark") }
            Text(name)
        }
    }
}

struct NewFolderSheet: View {
    let model: AppModel
    let onCreated: (LibraryFolder) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New folder").font(.headline)
            TextField("Folder name", text: $name)
                .onSubmit(create)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create", action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func create() {
        Task {
            switch await model.createFolder(name) {
            case .success(let folder):
                onCreated(folder)
                dismiss()
            case .failure(let failure):
                error = failure.errorDescription
            }
        }
    }
}
