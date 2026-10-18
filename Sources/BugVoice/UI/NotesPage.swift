import AppKit
import BugVoiceMac
import SwiftUI
import VoiceCore

/// A growing note library and a read-only preview. Editing stays in the floating window.
struct NotesPage: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @State private var managingFolders = false
    @State private var pendingDelete: NotesListItem?

    private var controller: NotesController { model.notesController }

    private var items: [NotesListItem] {
        let visible = LibraryProjection.filter(
            controller.notes,
            folder: model.notesFolderFilter,
            tags: model.notesTagFilter,
            known: model.library.knownIDs
        )
        return NotesListProjection.filter(
            visible.map {
                NotesListItem(
                    id: $0.id, title: $0.title, body: $0.body, modifiedAt: $0.modifiedAt,
                    tags: $0.frontMatter.tags, pinned: $0.frontMatter.pinned)
            },
            query: model.notesSearchQuery,
            sort: model.settings.scratchpad.sort
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            library
                .frame(width: ShellLayout.listPaneWidth(scale: model.settings.appearance.textScale))
                .background(.bvSidebar)
            Rectangle().fill(.bvSeparator).frame(width: 1)
            if let note = controller.notes.first(where: { $0.id == model.selectedNoteID }) {
                NotePreview(note: note, model: model)
            } else {
                EmptyState("Choose a note", systemImage: "note.text") {
                    Button("New note") { Task { await model.openScratchpadWindow(newNote: true) } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await controller.reloadList()
            model.syncScratchpadTabs()
        }
        .onChange(of: controller.notes) { _, _ in model.syncScratchpadTabs() }
        .sheet(isPresented: $managingFolders) { ManageFoldersSheet(model: model) }
        .confirmationDialog(
            "Move \(pendingDelete?.title ?? "this note") to the Trash?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                guard let item = pendingDelete else { return }
                Task {
                    do { try await model.deleteNote(item.id) }
                    catch { model.saveError = "Could not move note to the Trash: \(error.localizedDescription)" }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                FolderFilterMenu(
                    model: model,
                    filter: Binding(get: { model.notesFolderFilter }, set: { model.notesFolderFilter = $0 }),
                    counts: LibraryProjection.counts(controller.notes, known: model.library.knownIDs),
                    allTitle: "All notes", onManage: { managingFolders = true }
                )
                TagFilterBar(catalog: model.noteTagCatalog, selected: $model.notesTagFilter)
                TextField("Search notes", text: $model.notesSearchQuery).textFieldStyle(.roundedBorder).accessibilityLabel("Search notes")
                HStack(spacing: LayoutTokens.spacing[1]) {
                    Picker("Sort", selection: $model.settings.scratchpad.sort) {
                        ForEach(NotesSort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().help("Sort")
                    Button { Task { await controller.reloadList() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).help("Reload from disk").accessibilityLabel("Reload from disk")
                }
                ForEach(controller.insertionRecoveries) { recovery in
                    VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                        Text(recovery.message).foregroundStyle(.bvRecording)
                        Button("Copy") {
                            ScratchpadClipboard.copyText(recovery.text)
                            controller.dismissInsertionRecovery(id: recovery.id)
                        }
                    }
                }
                content
            }.padding(LayoutTokens.spacing[2])
        }
    }

    @ViewBuilder private var content: some View {
        if let listError = controller.listError {
            EmptyState("Notes unavailable", systemImage: "exclamationmark.triangle", message: listError) {
                Button("Retry") { Task { await controller.reloadList() } }
            }
        } else if items.isEmpty {
            if controller.notes.isEmpty {
                EmptyState("No notes", systemImage: "note.text") {
                    Button("New note") { Task { await model.openScratchpadWindow(newNote: true) } }
                }
            } else {
                EmptyState("No results", systemImage: "magnifyingglass")
            }
        } else {
            LazyVStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                ForEach(items) { item in card(item) }
            }
        }
    }

    private func card(_ item: NotesListItem) -> some View {
        let selected = model.selectedNoteID == item.id
        return VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
            HStack(spacing: LayoutTokens.spacing[0]) {
                if item.pinned { Image(systemName: "pin.fill").bvFont(.footnote).foregroundStyle(.bvAccent).accessibilityLabel("Pinned") }
                Text(item.title).bvFont(.bodyStrong).lineLimit(1)
            }
            Text(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                .bvFont(.footnote).foregroundStyle(.bvSecondary).lineLimit(1)
            Text(preview(item.body)).bvFont(.footnote).foregroundStyle(.bvSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LayoutTokens.spacing[1])
        .background(selected ? AnyShapeStyle(.bvAccentSoft) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).stroke(selected ? store.theme.accent.opacity(0.55) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.selectedNoteID = item.id; Task { await model.openNoteInWindow(item.id) } }
        .onTapGesture { model.selectedNoteID = item.id }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction { model.selectedNoteID = item.id }
        .contextMenu {
            Button("Edit") { Task { await model.openNoteInWindow(item.id) } }
            Button(item.pinned ? "Unpin" : "Pin") { Task { await model.setNotePinned(item.id, pinned: !item.pinned) } }
            Menu("Move to folder") {
                Button("Unfiled") { Task { await model.setNoteLabels(id: item.id, folderID: nil, tags: item.tags) } }
                Divider()
                ForEach(model.sortedFolders) { folder in
                    Button(folder.name) {
                        Task { await model.setNoteLabels(id: item.id, folderID: folder.id, tags: item.tags) }
                    }
                }
            }
            Divider()
            Button("Move to Trash…", role: .destructive) { pendingDelete = item }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Edit") { Task { await model.openNoteInWindow(item.id) } }
    }

    /// The first lines of the body without Markdown marks.
    private func preview(_ body: String) -> String {
        MarkdownPlainText.convert(String(body.prefix(400)))
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(3)
            .joined(separator: " ")
    }
}
