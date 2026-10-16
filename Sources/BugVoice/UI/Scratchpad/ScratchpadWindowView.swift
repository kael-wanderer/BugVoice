import BugVoiceMac
import SwiftUI
import VoiceCore

/// Contents of the Scratchpad window: tabs on top, the notes list on the
/// left (hidden when smaller or by Hide notes), the note editor.
struct ScratchpadWindowView: View {
    @Bindable var model: AppModel
    @State private var assistant = ScratchpadAssistant()
    @State private var searchText = ""
    @State private var bodyFocusRequested = false
    @FocusState private var searchFocused: Bool

    private var controller: NotesController { model.notesController }
    private var showsSideList: Bool {
        !model.settings.scratchpad.compact && !model.settings.scratchpad.sideListHidden
    }

    var body: some View {
        VStack(spacing: 0) {
            ScratchpadTabBar(model: model, onNew: newNote)
            HStack(spacing: 0) {
                if showsSideList {
                    sideList.frame(width: 190)
                }
                editorArea
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.18)))
                    .padding([.trailing, .bottom], 8)
                    .padding(.leading, showsSideList ? 0 : 8)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 420, minHeight: 360)
        .background { shortcuts }
        .task {
            await controller.reloadList()
            model.syncScratchpadTabs()
        }
        .onChange(of: controller.notes) { _, _ in model.syncScratchpadTabs() }
        .onChange(of: controller.selectedNoteID) { _, _ in assistant.noteChanged() }
        .onChange(of: model.notesFocusRequest) { _, _ in bodyFocusRequested = true }
        .animation(.easeInOut(duration: 0.2), value: model.notice)
        .animation(.easeInOut(duration: 0.2), value: assistant.notice)
        .alert(
            "Could not save",
            isPresented: Binding(
                get: { model.saveError != nil && model.scratchpadWindowIsKey },
                set: { if !$0 { model.saveError = nil } }
            )
        ) {
            Button("OK") { model.saveError = nil }
        } message: {
            Text(model.saveError ?? "")
        }
    }

    // MARK: Side list

    private var sideList: some View {
        VStack(alignment: .leading, spacing: 0) {
            sideButton("Hide notes", symbol: "sidebar.left") { model.settings.scratchpad.sideListHidden = true }
            sideButton("New note", symbol: "square.and.pencil", detail: "⌘N", action: newNote)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search notes", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            Divider().padding(.horizontal, 10).padding(.vertical, 4)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(listItems) { item in
                        Button {
                            open(item.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    if item.pinned {
                                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Color.accentColor)
                                    }
                                    Text(item.title).lineLimit(1)
                                }
                                Text(subtitle(item)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                controller.selectedNoteID == item.id ? Color.secondary.opacity(0.15) : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
            Divider().padding(.horizontal, 10)
            barButton(.ai, title: "AI", symbol: "sparkles")
            barButton(.formatting, title: "Formatting", symbol: "textformat")
                .padding(.bottom, 8)
        }
        .padding(.top, 4)
    }

    private var listItems: [NotesListItem] {
        NotesListProjection.filter(
            controller.notes.map {
                NotesListItem(
                    id: $0.id, title: $0.title, body: $0.body, modifiedAt: $0.modifiedAt,
                    tags: $0.frontMatter.tags, pinned: $0.frontMatter.pinned)
            },
            query: searchText,
            sort: model.settings.scratchpad.sort
        )
    }

    private func subtitle(_ item: NotesListItem) -> String {
        let when = item.modifiedAt.formatted(.relative(presentation: .named))
        guard let folderID = controller.notes.first(where: { $0.id == item.id })?.frontMatter.folderID,
              let folder = model.library.folders.first(where: { $0.id == folderID }) else { return when }
        return "\(when) · \(folder.name)"
    }

    private func sideButton(_ title: String, symbol: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 16)
                Text(title)
                Spacer()
                if let detail { Text(detail).font(.caption).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func barButton(_ bar: ScratchpadBottomBar, title: String, symbol: String) -> some View {
        let on = model.settings.scratchpad.bottomBar == bar
        return Button {
            model.settings.scratchpad.bottomBar = bar
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 16)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(on ? Color.secondary.opacity(0.15) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Editor

    @ViewBuilder private var editorArea: some View {
        if let id = controller.selectedNoteID, let note = controller.note(id: id) {
            ScratchpadNoteEditor(
                model: model, assistant: assistant, note: note, bodyFocusRequested: $bodyFocusRequested)
                // A new view per note, so shortcuts and state belong to the open note.
                .id(note.id)
                .overlay(alignment: .topLeading) {
                    if !showsSideList && !model.settings.scratchpad.compact {
                        Button {
                            model.settings.scratchpad.sideListHidden = false
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .buttonStyle(.borderless)
                        .help("Show notes")
                        .accessibilityLabel("Show notes")
                        .padding(8)
                    }
                }
        } else {
            ContentUnavailableView {
                Label("No note open", systemImage: "note.text")
            } description: {
                Text("Create a note or pick one from the list.")
            } actions: {
                Button("New note", action: newNote)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// ⌘N new note, ⌘W close tab, ⌘F search notes.
    private var shortcuts: some View {
        ZStack {
            Button("", action: newNote).keyboardShortcut("n", modifiers: .command)
            Button("") {
                if let id = model.scratchpadTabs.active { Task { await model.closeNoteTab(id) } }
            }
            .keyboardShortcut("w", modifiers: .command)
            Button("") {
                model.settings.scratchpad.sideListHidden = false
                model.settings.scratchpad.compact = false
                searchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func open(_ id: NoteID) {
        Task {
            do {
                try await model.openNoteTab(id)
                bodyFocusRequested = true
            } catch {
                model.saveError = "Could not save the current note: \(error.localizedDescription)"
            }
        }
    }

    private func newNote() {
        Task {
            await model.newScratchpadNoteInWindow()
            bodyFocusRequested = true
        }
    }
}
