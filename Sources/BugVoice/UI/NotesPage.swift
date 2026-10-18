import AppKit
import BugVoiceMac
import SwiftUI
import VoiceCore

/// The Scratchpad page: every note as a card. Notes are edited in the
/// Scratchpad window; Edit or a click opens one there.
struct NotesPage: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @State private var searchText = ""
    @State private var managingFolders = false
    @State private var pendingDelete: NotesListItem?
    @State private var hovered: NoteID?

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
            query: searchText,
            sort: model.settings.scratchpad.sort
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            HStack(spacing: LayoutTokens.spacing[1]) {
                Text("Scratchpad").bvFont(.title2)
                Spacer()
                Button {
                    Task { await model.openScratchpadWindow(newNote: false) }
                } label: {
                    Text("Open window ⌃⌥N")
                }
                Button {
                    Task { await model.openScratchpadWindow(newNote: true) }
                } label: {
                    Label("New note", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: LayoutTokens.spacing[1]) {
                FolderFilterMenu(
                    model: model,
                    filter: Binding(get: { model.notesFolderFilter }, set: { model.notesFolderFilter = $0 }),
                    counts: LibraryProjection.counts(controller.notes, known: model.library.knownIDs),
                    allTitle: "All notes",
                    onManage: { managingFolders = true }
                )
                TagFilterBar(catalog: model.noteTagCatalog, selected: $model.notesTagFilter)
                Spacer(minLength: 8)
                TextField("Search notes", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: store.scaled(200))
                    .accessibilityLabel("Search notes")
                Picker("Sort", selection: $model.settings.scratchpad.sort) {
                    ForEach(NotesSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .help("Sort")
                Button {
                    Task { await controller.reloadList() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload from disk")
                .accessibilityLabel("Reload from disk")
            }

            ForEach(controller.insertionRecoveries) { recovery in
                HStack {
                    Text(recovery.message).foregroundStyle(.bvRecording)
                    Spacer()
                    Button("Copy") {
                        ScratchpadClipboard.copyText(recovery.text)
                        controller.dismissInsertionRecovery(id: recovery.id)
                    }
                }
            }

            Divider()

            content
        }
        .padding(.horizontal, LayoutTokens.spacing[4])
        .padding(.top, LayoutTokens.spacing[3])
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

    @ViewBuilder private var content: some View {
        if let listError = controller.listError {
            ContentUnavailableView {
                Label("Notes unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(listError)
            } actions: {
                Button("Retry") { Task { await controller.reloadList() } }
            }
        } else if items.isEmpty {
            if controller.notes.isEmpty {
                ContentUnavailableView {
                    Label("No notes", systemImage: "note.text")
                } actions: {
                    Button("New note") { Task { await model.openScratchpadWindow(newNote: true) } }
                }
            } else {
                ContentUnavailableView("No results", systemImage: "magnifyingglass")
            }
        } else {
            GeometryReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: LayoutTokens.spacing[2]), count: proxy.size.width < 640 ? 1 : 2),
                        spacing: 12
                    ) {
                        ForEach(items) { item in card(item) }
                    }
                    .padding(.bottom, LayoutTokens.spacing[3])
                }
            }
        }
    }

    private func card(_ item: NotesListItem) -> some View {
        let isHovered = hovered == item.id
        let folderID = controller.notes.first { $0.id == item.id }?.frontMatter.folderID
        let folder = folderID.flatMap { id in model.library.folders.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
            HStack(spacing: LayoutTokens.spacing[0]) {
                if item.pinned {
                    Image(systemName: "pin.fill").bvFont(.footnote).foregroundStyle(store.theme.accent)
                        .accessibilityLabel("Pinned")
                }
                Text(item.title).bvFont(.bodyStrong).lineLimit(1)
            }
            Text(preview(item.body))
                .foregroundStyle(.bvSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
            HStack(spacing: LayoutTokens.spacing[0]) {
                Text(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                if let folder {
                    Text("·")
                    Text(folder.name)
                }
                ForEach(item.tags.prefix(3), id: \.self) { TagChip(name: $0) }
                Spacer(minLength: 0)
            }
            .bvFont(.footnote)
            .foregroundStyle(.bvSecondary)
        }
        .padding(LayoutTokens.spacing[2])
        .background(store.theme.card, in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: LayoutTokens.cardRadius).stroke(isHovered ? store.theme.accent : store.theme.secondaryText.opacity(0.2)))
        .overlay(alignment: .topTrailing) {
            if isHovered { cardActions(item) }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
        }
        .onTapGesture { Task { await model.openNoteInWindow(item.id) } }
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

    private func cardActions(_ item: NotesListItem) -> some View {
        HStack(spacing: LayoutTokens.spacing[0]) {
            iconButton("pencil", help: "Edit") { Task { await model.openNoteInWindow(item.id) } }
            iconButton(item.pinned ? "pin.slash" : "pin", help: item.pinned ? "Unpin" : "Pin") {
                Task { await model.setNotePinned(item.id, pinned: !item.pinned) }
            }
            iconButton("trash", help: "Move to Trash", tint: store.theme.recording) { pendingDelete = item }
        }
        .padding(LayoutTokens.spacing[0])
        .background(.bvCard, in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).stroke(store.theme.secondaryText.opacity(0.2)))
        .padding(LayoutTokens.spacing[1])
    }

    private func iconButton(_ symbol: String, help: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(tint ?? store.theme.secondaryText).frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }

    /// The first lines of the body without Markdown marks.
    private func preview(_ body: String) -> String {
        MarkdownPlainText.convert(String(body.prefix(400)))
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(3)
            .joined(separator: " ")
    }
}
