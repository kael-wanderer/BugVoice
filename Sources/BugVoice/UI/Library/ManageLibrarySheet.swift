import SwiftUI
import VoiceCore

struct ManageLibrarySheet: View {
    @Environment(AppearanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let model: AppModel
    @State private var tab: LibrarySheetTab

    init(model: AppModel, tab: LibrarySheetTab) {
        self.model = model
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            Text("Manage library").bvFont(.bodyStrong)
            Picker("Library", selection: $tab) {
                Text("Folders").tag(LibrarySheetTab.folders)
                Text("Tags").tag(LibrarySheetTab.tags)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Group {
                switch tab {
                case .folders: ScrollView { FoldersTab(model: model) }
                case .tags: TagsTab(model: model)
                }
            }
            .disabled(model.libraryReadOnly)
            .frame(maxHeight: store.scaled(360))
            if let error = model.saveError {
                Text(error).bvFont(.footnote).foregroundStyle(.bvRecording)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(LayoutTokens.spacing[3])
        .frame(width: store.scaled(460))
        .onExitCommand { dismiss() }
    }
}

struct FoldersTab: View {
    @Environment(AppearanceStore.self) private var store
    let model: AppModel
    @State private var editing: FolderID?
    @State private var draft = ""
    @State private var error: String?
    @State private var pendingDelete: LibraryFolder?
    @State private var creating = false

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            if model.sortedFolders.isEmpty {
                Text("No folders yet.").foregroundStyle(.bvSecondary)
            }
            ForEach(model.sortedFolders) { folder in
                HStack(spacing: LayoutTokens.spacing[1]) {
                    if editing == folder.id {
                        TextField("Folder name", text: $draft).onSubmit { save(folder.id) }
                    } else {
                        Label(folder.name, systemImage: "folder")
                    }
                    Spacer()
                    Text(countText(folder.id)).bvFont(.footnote).foregroundStyle(.bvSecondary)
                    if editing == folder.id {
                        Button("Save") { save(folder.id) }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Rename") { editing = folder.id; draft = folder.name; error = nil }
                        Button("Delete", role: .destructive) { pendingDelete = folder }
                    }
                }
                .disabled(model.libraryReadOnly)
                .padding(LayoutTokens.spacing[1])
                .overlay(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).strokeBorder(store.theme.secondaryText.opacity(0.25)))
            }
            if let error {
                Text(error).bvFont(.footnote).foregroundStyle(.bvRecording)
            }
            HStack {
                Button("+ New folder") { creating = true }.disabled(model.libraryReadOnly)
                Spacer()
                Text(unfiledText).bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
            Text("Deleting a folder moves its meetings and notes to Unfiled. Nothing is deleted, and files on disk never move.")
                .bvFont(.footnote).foregroundStyle(.bvSecondary)
        }
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

    private var unfiledText: String {
        let notes = LibraryProjection.counts(model.notesController.notes, known: model.library.knownIDs).unfiled
        let meetings = LibraryProjection.counts(model.meetingManifests, known: model.library.knownIDs).unfiled
        return "Unfiled: \(counted(notes, "note")) · \(counted(meetings, "meeting"))"
    }

    private func countText(_ id: FolderID) -> String {
        let meetings = LibraryProjection.counts(model.meetingManifests, known: model.library.knownIDs).count(id)
        let notes = LibraryProjection.counts(model.notesController.notes, known: model.library.knownIDs).count(id)
        return "\(counted(notes, "note")) · \(counted(meetings, "meeting"))"
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

private struct TagsTab: View {
    @Environment(AppearanceStore.self) private var store
    let model: AppModel
    @State private var editing: String?
    @State private var draft = ""
    @State private var creating = false
    @State private var newName = ""
    @State private var highlighted: String?
    @State private var palette: String?
    @State private var error: String?
    @State private var pendingMerge: Merge?
    @State private var pendingDelete: TagRow?
    @State private var saving = false
    /// The open name field: the new tag field, or the tag being renamed.
    @FocusState private var focusedField: String?

    private static let newTagField = "\u{0}new"

    private struct Merge {
        let old: String
        let target: String
        let notes: Int
        let meetings: Int
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                    if creating {
                        TextField("#tag", text: $newName)
                            .focused($focusedField, equals: Self.newTagField)
                            .onAppear { focusedField = Self.newTagField }
                            .onSubmit {
                                Task {
                                    saving = true
                                    defer { saving = false }
                                    switch await model.createTag(newName) {
                                    case .created(let name), .exists(let name):
                                        creating = false
                                        newName = ""
                                        error = nil
                                        highlighted = name
                                    case .invalid: error = invalidName
                                    }
                                }
                            }
                    }
                    if model.tagRows.isEmpty { Text("No tags yet.").foregroundStyle(.bvSecondary) }
                    ForEach(model.tagRows) { tag in
                        VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                            row(tag)
                            if palette == tag.name { swatches(tag) }
                        }
                        .padding(LayoutTokens.spacing[1])
                        .background(highlighted == tag.name ? AnyShapeStyle(.bvAccentSoft) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                        .id(tag.name)
                    }
                    if let error { Text(error).bvFont(.footnote).foregroundStyle(.bvRecording) }
                    HStack {
                        Button("+ New tag") { creating = true; newName = ""; error = nil }
                        Spacer()
                    }
                }
            }
            .disabled(saving)
            .onChange(of: highlighted) { _, name in
                if let name { proxy.scrollTo(name) }
            }
        }
        .confirmationDialog(
            "Merge #\(pendingMerge?.old ?? "") into #\(pendingMerge?.target ?? "")?",
            isPresented: Binding(get: { pendingMerge != nil }, set: { if !$0 { pendingMerge = nil } }),
            titleVisibility: .visible, presenting: pendingMerge
        ) { merge in
            Button("Merge") {
                Task {
                    saving = true
                    defer { saving = false }
                    handle(await model.mergeTag(merge.old, into: merge.target), old: merge.old)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { merge in
            Text("\(counted(merge.notes, "note")) and \(counted(merge.meetings, "meeting")) will use #\(merge.target).")
        }
        .confirmationDialog(
            "Delete #\(pendingDelete?.name ?? "")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible, presenting: pendingDelete
        ) { tag in
            Button("Delete", role: .destructive) {
                Task {
                    saving = true
                    defer { saving = false }
                    let result = await model.deleteTag(tag.name)
                    if result == .renamed, editing == tag.name { editing = nil }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { tag in
            Text("It will be removed from \(counted(tag.notes, "note")) and \(counted(tag.meetings, "meeting")). The notes and meetings stay.")
        }
    }

    private var invalidName: String { "Tags use letters, numbers, - _ and /, up to 32 characters." }

    private func row(_ tag: TagRow) -> some View {
        HStack(spacing: LayoutTokens.spacing[1]) {
            Button { palette = palette == tag.name ? nil : tag.name } label: {
                Group {
                    if let color = tag.color { Circle().fill(TagColors.color(color)) }
                    else { Circle().stroke(.bvSecondary) }
                }
                .frame(width: store.scaled(10), height: store.scaled(10))
                .padding(LayoutTokens.spacing[0])
                // A hollow dot only takes clicks on its outline without this.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Colour for #\(tag.name)")
            if editing == tag.name {
                TextField("#tag", text: $draft)
                    .focused($focusedField, equals: tag.name)
                    .onAppear { focusedField = tag.name }
                    .onSubmit { rename(tag.name) }
            } else {
                Text("#\(tag.name)")
            }
            Spacer(minLength: LayoutTokens.spacing[0])
            Text(tag.countText).bvFont(.footnote).foregroundStyle(.bvSecondary)
            if editing == tag.name {
                Button("Save") { rename(tag.name) }.buttonStyle(.borderedProminent)
                Button("Cancel") { editing = nil; error = nil }
            } else {
                Button("Rename") { editing = tag.name; draft = tag.name; error = nil; highlighted = nil }
                Button("Delete", role: .destructive) { pendingDelete = tag }
            }
        }
    }

    private func swatches(_ tag: TagRow) -> some View {
        HStack(spacing: LayoutTokens.spacing[1]) {
            ForEach(TagColor.allCases, id: \.self) { color in
                Button { setColor(color, for: tag.name) } label: {
                    Circle().fill(TagColors.color(color))
                        .frame(width: store.scaled(16), height: store.scaled(16))
                        .overlay(Circle().strokeBorder(tag.color == color ? AnyShapeStyle(.bvText) : AnyShapeStyle(.clear)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.rawValue.capitalized)
            }
            Button("None") { setColor(nil, for: tag.name) }
        }
    }

    private func setColor(_ color: TagColor?, for name: String) {
        Task {
            saving = true
            defer { saving = false }
            await model.setTagColor(color, for: name)
            palette = nil
        }
    }

    private func rename(_ old: String) {
        Task {
            saving = true
            defer { saving = false }
            handle(await model.renameTag(old, to: draft), old: old)
        }
    }

    private func handle(_ result: TagRenameOutcome, old: String) {
        switch result {
        case .invalid: error = invalidName
        case .unchanged, .renamed: editing = nil; error = nil
        case .needsMerge(let target, let notes, let meetings):
            pendingMerge = Merge(old: old, target: target, notes: notes, meetings: meetings)
        case .failed: break
        }
    }
}

/// "1 note", "2 notes".
func counted(_ count: Int, _ word: String) -> String {
    "\(count) \(word)\(count == 1 ? "" : "s")"
}
