import BugVoiceMac
import SwiftUI
import VoiceCore

/// Contents of the Scratchpad window: tabs on top, the notes list on the
/// left (hidden when smaller or by Hide notes), then the editor with its
/// tool row, always-visible Formatting bar and AI bar shown on request.
struct ScratchpadWindowView: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @State private var assistant = ScratchpadAssistant()
    @State private var assistants: [NoteID: ScratchpadAssistant] = [:]
    @State private var assistantNoteID: NoteID?
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
                    sideList.frame(width: store.scaled(190))
                }
                editorArea
                    .background(store.theme.background, in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: LayoutTokens.cardRadius).stroke(store.theme.secondaryText.opacity(0.18)))
                    .padding([.trailing, .bottom], LayoutTokens.spacing[1])
                    .padding(.leading, showsSideList ? 0 : LayoutTokens.spacing[1])
            }
        }
        .background(store.theme.background)
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 420, minHeight: 360)
        .background { shortcuts }
        .task {
            await controller.reloadList()
            model.syncScratchpadTabs()
            activateAssistant(controller.selectedNoteID)
        }
        .onChange(of: controller.notes) { _, _ in model.syncScratchpadTabs() }
        .onChange(of: controller.selectedNoteID) { _, id in activateAssistant(id) }
        .onChange(of: model.scratchpadTabs.ids) { _, ids in
            for (id, saved) in assistants where !ids.contains(id) { saved.cancel() }
            assistants = assistants.filter { ids.contains($0.key) }
            if let assistantNoteID, !ids.contains(assistantNoteID) { assistant.cancel() }
        }
        .onDisappear { assistant.cancel(); for saved in assistants.values { saved.cancel() } }
        .onChange(of: model.scratchpadAskRequest) { _, _ in
            activateAssistant(controller.selectedNoteID)
            assistant.changeScope(.all)
            assistant.questionFocusRequest &+= 1
        }
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

    private func activateAssistant(_ id: NoteID?) {
        guard assistantNoteID != id else { return }
        assistant.noteChanged()
        if let previous = assistantNoteID, model.scratchpadTabs.ids.contains(previous) { assistants[previous] = assistant }
        assistantNoteID = id
        guard let id else { return }
        if let saved = assistants[id] { assistant = saved }
        else {
            let fresh = ScratchpadAssistant()
            fresh.scope = .note(id)
            assistants[id] = fresh
            assistant = fresh
        }
    }

    // MARK: Side list

    private var sideList: some View {
        VStack(alignment: .leading, spacing: 0) {
            sideButton("Hide notes", symbol: "sidebar.left") { model.settings.scratchpad.sideListHidden = true }
            sideButton("New note", symbol: "square.and.pencil", detail: "⌘N", action: newNote)
            HStack(spacing: LayoutTokens.spacing[1]) {
                Image(systemName: "magnifyingglass").foregroundStyle(.bvSecondary)
                TextField("Search notes", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, LayoutTokens.spacing[2])
            .padding(.vertical, LayoutTokens.spacing[1])
            Divider().padding(.horizontal, LayoutTokens.spacing[1]).padding(.vertical, LayoutTokens.spacing[0])
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                    ForEach(listItems) { item in
                        Button {
                            open(item.id)
                        } label: {
                            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                                HStack(spacing: LayoutTokens.spacing[0]) {
                                    if item.pinned {
                                        Image(systemName: "pin.fill").bvFont(.caption).foregroundStyle(store.theme.accent)
                                    }
                                    Text(item.title).lineLimit(1)
                                }
                                Text(subtitle(item)).bvFont(.footnote).foregroundStyle(.bvSecondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, LayoutTokens.spacing[1])
                            .padding(.vertical, LayoutTokens.spacing[0])
                            .background(
                                controller.selectedNoteID == item.id ? store.theme.secondaryText.opacity(0.15) : .clear,
                                in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, LayoutTokens.spacing[1])
            }
            Spacer(minLength: 0)
        }
        .padding(.top, LayoutTokens.spacing[0])
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
            HStack(spacing: LayoutTokens.spacing[1]) {
                Image(systemName: symbol).frame(width: 16)
                Text(title)
                Spacer()
                if let detail { Text(detail).bvFont(.footnote).foregroundStyle(.bvSecondary) }
            }
            .padding(.horizontal, LayoutTokens.spacing[2])
            .padding(.vertical, LayoutTokens.spacing[1])
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                        .padding(LayoutTokens.spacing[1])
                    }
                }
        } else {
            EmptyState("No note open", systemImage: "note.text", message: "Create a note or pick one from the list.") {
                Button("New note", action: newNote)
            }
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
