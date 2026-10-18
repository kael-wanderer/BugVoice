import SwiftUI
import VoiceCore

/// List-header menu: All, Unfiled, each folder with counts, New folder…, Manage folders….
struct FolderFilterMenu: View {
    @Environment(AppearanceStore.self) private var store
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

/// Tags menu; several selected tags mean all must match.
struct TagFilterBar: View {
    @Environment(\.tagColors) private var tagColors
    let catalog: [TagCount]
    @Binding var selected: [String]
    let onManage: () -> Void

    var body: some View {
        Menu {
            ForEach(catalog) { tag in
                Toggle(isOn: Binding(
                    get: { selected.contains(tag.name) },
                    set: { on in
                        if on {
                            if !selected.contains(tag.name) { selected.append(tag.name) }
                        } else {
                            selected.removeAll { $0 == tag.name }
                        }
                    }
                )) {
                    HStack {
                        if let color = tagColors[tag.name] { TagColors.dot(color) }
                        Text("#\(tag.name)  \(tag.count)")
                    }
                }
            }
            if catalog.isEmpty { Text("No tags yet") }
            Divider()
            Button("Clear tags") { selected = [] }.disabled(selected.isEmpty)
            Button("Manage tags…", action: onManage)
        } label: {
            HStack(spacing: LayoutTokens.spacing[0]) {
                Label("Tags", systemImage: "tag")
                if !selected.isEmpty {
                    Text("\(selected.count)").bvFont(.caption)
                        .foregroundStyle(.bvOnAccent)
                        .padding(.horizontal, LayoutTokens.spacing[1])
                        .background(.bvAccent, in: Capsule())
                }
            }
        }
        .fixedSize()
        .accessibilityLabel("Tags, \(selected.count) selected")
    }
}

struct TagChip: View {
    @Environment(\.tagColors) private var tagColors
    @Environment(AppearanceStore.self) private var store
    let name: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: LayoutTokens.spacing[0]) {
            if let c = tagColors[name] {
                Circle().fill(TagColors.color(c)).frame(width: store.scaled(8), height: store.scaled(8))
            }
            Text("#\(name)").bvFont(.footnote)
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark").bvFont(.caption) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove tag \(name)")
            }
        }
        .padding(.horizontal, LayoutTokens.spacing[1])
        .padding(.vertical, LayoutTokens.spacing[0])
        .background(store.theme.secondaryText.opacity(0.15), in: Capsule())
    }
}

/// Folder button for a single item: Unfiled, each folder, New folder….
struct FolderPicker: View {
    @Environment(AppearanceStore.self) private var store
    let model: AppModel
    let folderID: FolderID?
    var onManage: (() -> Void)? = nil
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
            if let onManage { Button("Manage folders…", action: onManage) }
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
    @Environment(AppearanceStore.self) private var store
    let model: AppModel
    let onCreated: (LibraryFolder) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            Text("New folder").bvFont(.bodyStrong)
            TextField("Folder name", text: $name)
                .onSubmit(create)
            if let error {
                Text(error).bvFont(.footnote).foregroundStyle(.bvRecording)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create", action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(LayoutTokens.spacing[3])
        .frame(width: store.scaled(340))
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

/// The folder and tag filters at the top of a list pane: one row when they
/// fit, wrapping whole controls onto the next row when they do not.
struct FilterRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        FlowLayout(spacing: LayoutTokens.spacing[1]) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
