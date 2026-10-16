import AppKit
import BugVoiceMac
import SwiftUI
import UniformTypeIdentifiers
import VoiceCore

struct NotesPage: View {
    @Bindable var model: AppModel
    @FocusState private var titleFocused: Bool
    @State private var searchText = ""
    @State private var bodyFocusRequested = false
    @State private var confirmDelete = false
    @State private var confirmExternalReload = false
    @State private var managingFolders = false
    @State private var assistant = ScratchpadAssistant()
    @State private var caretToEndRequested = false
    @State private var dictateWhenCaretPlaced = false

    private var controller: NotesController { model.notesController }
    private var selectedNote: NoteDocument? {
        guard let id = controller.selectedNoteID else { return nil }
        return controller.note(id: id)
    }
    private var filteredNotes: [NotesListItem] {
        let visible = LibraryProjection.filter(
            controller.notes,
            folder: model.notesFolderFilter,
            tags: model.notesTagFilter,
            known: model.library.knownIDs
        )
        return NotesListProjection.filter(
            visible.map {
                NotesListItem(id: $0.id, title: $0.title, body: $0.body, modifiedAt: $0.modifiedAt, tags: $0.frontMatter.tags)
            },
            query: searchText
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search notes", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search notes")
                Button("New note") { createNote() }
                    .keyboardShortcut("n", modifiers: [.control, .option])
            }
            .padding(12)

            HStack(spacing: 6) {
                FolderFilterMenu(
                    model: model,
                    filter: Binding(get: { model.notesFolderFilter }, set: { model.notesFolderFilter = $0 }),
                    counts: LibraryProjection.counts(controller.notes, known: model.library.knownIDs),
                    allTitle: "All notes",
                    onManage: { managingFolders = true }
                )
                TagFilterBar(catalog: model.noteTagCatalog, selected: $model.notesTagFilter)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            ForEach(controller.insertionRecoveries) { recovery in
                HStack {
                    Text(recovery.message)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Copy") { copyRecovery(recovery) }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            Divider()

            HStack(spacing: 0) {
                noteList
                    .frame(minWidth: 230, idealWidth: 280, maxWidth: 330)
                Divider()
                editor
            }
        }
        .task {
            await controller.reloadList()
            model.syncScratchpadTabs()
            if model.scratchpadTabs.ids.isEmpty, let first = controller.notes.first {
                try? await model.openNoteTab(first.id)
                bodyFocusRequested = true
            }
        }
        .onChange(of: controller.notes) { _, _ in model.syncScratchpadTabs() }
        .onChange(of: controller.selectedNoteID) { _, _ in assistant.close() }
        .background { transformShortcuts }
        .onChange(of: model.notesFocusRequest) { _, _ in
            bodyFocusRequested = true
        }
        .onChange(of: model.page) { oldPage, newPage in
            if oldPage == .notes, newPage != .notes {
                Task {
                    if !(await controller.flushAll()) {
                        model.saveError = "Could not save notes before leaving the Notes page."
                    }
                }
            }
        }
        .confirmationDialog(
            "Move \(selectedNote?.title ?? "this note") to the Trash?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $managingFolders) { ManageFoldersSheet(model: model) }
        .confirmationDialog(
            "Reload this note and discard your unsaved changes?",
            isPresented: $confirmExternalReload,
            titleVisibility: .visible
        ) {
            Button("Reload", role: .destructive) {
                if let id = controller.selectedNoteID { Task { await controller.resolveExternalChange(id: id, keepMine: false) } }
            }
            Button("Keep mine") {
                if let id = controller.selectedNoteID { Task { await controller.resolveExternalChange(id: id, keepMine: true) } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var noteList: some View {
        VStack(spacing: 0) {
            if let listError = controller.listError {
                ContentUnavailableView {
                    Label("Notes unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(listError)
                } actions: {
                    Button("Retry") { Task { await controller.reloadList() } }
                }
            } else if filteredNotes.isEmpty {
                ContentUnavailableView(searchText.isEmpty ? "No notes" : "No results", systemImage: "note.text")
            } else {
                List {
                    ForEach(filteredNotes) { item in
                        Button {
                            Task {
                                do {
                                    try await model.openNoteTab(item.id)
                                    bodyFocusRequested = true
                                }
                                catch { model.saveError = "Could not save the current note: \(error.localizedDescription)" }
                            }
                        } label: {
                            noteRow(item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Menu("Move to folder") {
                                Button("Unfiled") { Task { await model.setNoteLabels(id: item.id, folderID: nil, tags: item.tags) } }
                                Divider()
                                ForEach(model.sortedFolders) { folder in
                                    Button(folder.name) {
                                        Task { await model.setNoteLabels(id: item.id, folderID: folder.id, tags: item.tags) }
                                    }
                                }
                            }
                            Button("Tags…") { Task { try? await model.openNoteTab(item.id) } }
                            Divider()
                            Button("Delete…", role: .destructive) {
                                Task {
                                    try? await model.openNoteTab(item.id)
                                    confirmDelete = true
                                }
                            }
                        }
                        .listRowBackground(controller.selectedNoteID == item.id ? Color.accentColor.opacity(0.12) : Color.clear)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func noteRow(_ item: NotesListItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if model.scratchpadTabs.isOpen(item.id) {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                        .accessibilityLabel("Open in a tab")
                }
                Text(item.title).font(.headline).lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                Text("·")
                Text("\(wordCount(item.body)) words")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !item.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(item.tags.prefix(3), id: \.self) { TagChip(name: $0) }
                    if item.tags.count > 3 { Text("+\(item.tags.count - 3)").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var editor: some View {
        VStack(spacing: 0) {
            ScratchpadTabBar(model: model, onNew: createNote)
            Divider()
            noteEditor
        }
    }

    @ViewBuilder private var noteEditor: some View {
        if let note = selectedNote {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField("Untitled", text: Binding(
                        get: { controller.titleDraft(id: note.id) ?? note.title },
                        set: { controller.updateTitleDraft(id: note.id, title: $0) }
                    ))
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .onSubmit { Task { await controller.commitTitle(id: note.id, reason: .returnKey) } }
                    .onChange(of: titleFocused) { wasFocused, isFocused in
                        if wasFocused && !isFocused {
                            Task { await controller.commitTitle(id: note.id, reason: .focusOut) }
                        }
                    }
                    Button("Export…") { exportMarkdown(note) }
                    Button {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Move note to Trash")
                    .accessibilityLabel("Delete note")
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 6)

                Text("Saved to Notes/\(note.slug).md")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)

                LabelsBox(
                    model: model,
                    labels: note.frontMatter.labels,
                    catalog: model.allTagCatalog,
                    noun: "note",
                    onChange: { labels in
                        Task { await model.setNoteLabels(id: note.id, folderID: labels.folderID, tags: labels.tags) }
                    }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 10)

                statusRow(for: note)

                editorToolbar(for: note)
                Divider()

                if model.scratchpadView == .markdown {
                    NotesBodyEditor(
                        controller: controller,
                        noteID: note.id,
                        body: note.body,
                        focusRequested: $bodyFocusRequested,
                        caretToEndRequested: $caretToEndRequested,
                        onCaretPlaced: caretPlaced
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    MarkdownDocView(text: note.body) { line in
                        if let body = MarkdownCommands.toggleTask(in: note.body, line: line) {
                            controller.updateBody(id: note.id, body: body)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                TransformPanel(assistant: assistant, model: model, noteID: note.id)

                listeningBar
            }
        } else {
            ContentUnavailableView {
                Label("Select a note", systemImage: "note.text")
            } description: {
                Text("Choose a note or create a new one.")
            } actions: {
                Button("New note") { createNote() }
            }
        }
    }

    private func editorToolbar(for note: NoteDocument) -> some View {
        HStack(spacing: 8) {
            if model.scratchpadView == .markdown {
                MarkdownToolbar { command in run(command, on: note.id) }
            } else {
                Text("Doc view is read only. Switch to Markdown to edit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            NotesMicButton(
                disabled: model.isListening || model.dictation?.isBusy == true || model.notesIsListening,
                action: dictate
            )
            .fixedSize()
            copyAsMenu(note)
            transformsMenu(note)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func copyAsMenu(_ note: NoteDocument) -> some View {
        Menu("Copy as") {
            Section("Copy whole note") {
                Button("Markdown") { copyMarkdown(note) }
                Button("Plain text") { copyPlainText(note) }
            }
            Section("Rewrite with a Style, then copy") {
                ForEach(Style.allCases, id: \.self) { style in
                    Button(style.title) { copyWithStyle(style, note: note) }
                }
            }
        }
        .fixedSize()
    }

    private func transformsMenu(_ note: NoteDocument) -> some View {
        Menu("Transforms") {
            Section(currentInput(note.id)?.header ?? "Whole note") {
                ForEach(NoteTransform.allCases, id: \.self) { transform in
                    Button("\(transform.title)    ⌘\(String(transform.shortcutKey))") { runTransform(transform) }
                }
                Button("Ask a question…    ⌘J") { startAsk() }
            }
            Section("Notes model · \(model.transformPlan.shortName ?? "none")") {}
        }
        .fixedSize()
        .disabled(assistant.isBusy)
    }

    /// ⌘1…⌘4 and ⌘J, active while the Scratchpad page is shown.
    private var transformShortcuts: some View {
        ZStack {
            ForEach(NoteTransform.allCases, id: \.self) { transform in
                Button("") { runTransform(transform) }
                    .keyboardShortcut(KeyEquivalent(transform.shortcutKey), modifiers: .command)
            }
            Button("") { startAsk() }
                .keyboardShortcut("j", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func currentInput(_ id: NoteID) -> TransformInput? {
        TransformInput.capture(noteID: id, controller: controller, useSelection: model.scratchpadView == .markdown)
    }

    private func runTransform(_ transform: NoteTransform) {
        guard let id = controller.selectedNoteID, let input = currentInput(id) else { return }
        assistant.run(transform, input: input, model: model)
    }

    private func startAsk() {
        guard let id = controller.selectedNoteID, let input = currentInput(id) else { return }
        assistant.startAsk(input: input)
    }

    private func run(_ command: MarkdownToolbarCommand, on id: NoteID) {
        guard let body = controller.note(id: id)?.body else { return }
        let selection = ScratchpadEditing.selection(of: id, controller: controller)
        guard selection.isValid(inUTF16Length: (body as NSString).length) else { return }
        let edit: MarkdownEdit = switch command {
        case .inline(let marker): MarkdownCommands.toggleInline(marker, in: body, selection: selection)
        case .line(let format): MarkdownCommands.toggleLineFormat(format, in: body, selection: selection)
        case .link: MarkdownCommands.insertLink(in: body, selection: selection)
        }
        ScratchpadEditing.apply(edit, to: id, controller: controller)
        bodyFocusRequested = true
    }

    /// In Doc view, switch to Markdown and put the caret at the end first.
    private func dictate() {
        if model.scratchpadView == .doc {
            model.scratchpadView = .markdown
            caretToEndRequested = true
            dictateWhenCaretPlaced = true
        } else {
            model.dictation?.toggleNotesRecording()
        }
    }

    private func caretPlaced() {
        guard dictateWhenCaretPlaced else { return }
        dictateWhenCaretPlaced = false
        model.dictation?.toggleNotesRecording()
    }

    @ViewBuilder private func statusRow(for note: NoteDocument) -> some View {
        if controller.externalChangeMessage(for: note.id) != nil {
            HStack {
                Text("Changed outside BugVoice")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Resolve…") { confirmExternalReload = true }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
        } else if controller.saveMessage(for: note.id).hasPrefix("Could not") {
            HStack {
                Text(controller.saveMessage(for: note.id)).foregroundStyle(.red)
                Spacer()
                Button("Retry save") { Task { _ = await controller.flush(id: note.id) } }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
        } else {
            Text(controller.saveMessage(for: note.id))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder private var listeningBar: some View {
        HStack(spacing: 12) {
            if model.notesIsListening {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
                Text("Listening")
                    .fontWeight(.semibold)
                if let started = model.notesRecordingStartedAt {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        Text(elapsed(context.date.timeIntervalSince(started)))
                            .monospacedDigit()
                    }
                }
                ProgressView(value: Double(model.dictation?.recordingLevel ?? 0), total: 0.2)
                    .frame(width: 100)
                Text("Text will be added to this note")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Stop") { model.dictation?.toggleNotesRecording() }
                    .keyboardShortcut(.escape)
            } else {
                Spacer()
                Text("Hold Right Option to dictate at the caret")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func createNote() {
        Task {
            do {
                try await model.createScratchpadNote(frontMatter: NoteFrontMatter(folderID: model.notesFolderFilter.newItemFolderID))
                bodyFocusRequested = true
            } catch {
                model.saveError = "Could not create note: \(error.localizedDescription)"
            }
        }
    }

    private func deleteSelected() {
        guard let id = controller.selectedNoteID else { return }
        Task {
            do { try await model.deleteNote(id) }
            catch { model.saveError = "Could not move note to the Trash: \(error.localizedDescription)" }
        }
    }

    private func copyMarkdown(_ note: NoteDocument) {
        Task { @MainActor in
            await controller.commitTitle(id: note.id, reason: .focusOut)
            guard let latest = controller.note(id: note.id) else { return }
            let text = NotesExporter.markdown(title: latest.title, body: latest.body)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            model.showNotice("Copied as Markdown")
        }
    }

    private func copyPlainText(_ note: NoteDocument) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(MarkdownPlainText.convert(note.body), forType: .string)
        model.showNotice("Copied as plain text")
    }

    private func copyWithStyle(_ style: Style, note: NoteDocument) {
        guard let input = currentInput(note.id), !assistant.isBusy else { return }
        assistant.phase = .running("Working… \(style.title) · \(input.words) words")
        Task {
            do {
                try await model.copyWithStyle(style, text: input.text)
                assistant.phase = .idle
            } catch {
                assistant.phase = .failed(ScratchpadAssistant.message(for: error))
            }
        }
    }

    private func copyRecovery(_ recovery: NotesInsertionRecovery) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recovery.text, forType: .string)
        controller.dismissInsertionRecovery(id: recovery.id)
    }

    private func exportMarkdown(_ note: NoteDocument) {
        Task { @MainActor in
            await controller.commitTitle(id: note.id, reason: .focusOut)
            guard let latest = controller.note(id: note.id) else { return }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(latest.slug).md"
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let data = Data(NotesExporter.markdown(title: latest.title, body: latest.body).utf8)
            Task.detached {
                do { try data.write(to: url, options: .atomic) }
                catch {
                    await MainActor.run { model.saveError = "Could not export note: \(error.localizedDescription)" }
                }
            }
        }
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private func elapsed(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct NotesMicButton: NSViewRepresentable {
    let disabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NonFocusNSButton(title: "Dictate", target: context.coordinator, action: #selector(Coordinator.activate))
        button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Dictate")
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.isEnabled = !disabled
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = !disabled
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func activate() { action() }
    }
}

@MainActor
private final class NonFocusNSButton: NSButton {
    override var acceptsFirstResponder: Bool { false }
}

private struct NotesBodyEditor: NSViewRepresentable {
    let controller: NotesController
    let noteID: NoteID
    let body: String
    @Binding var focusRequested: Bool
    @Binding var caretToEndRequested: Bool
    let onCaretPlaced: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller, noteID: noteID)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let editor = NotesTextView(frame: .zero)
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.font = MarkdownTextStyler.bodyFont
        editor.typingAttributes = [.font: MarkdownTextStyler.bodyFont, .foregroundColor: NSColor.labelColor]
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 8, height: 10)
        editor.string = body

        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        // A text view made with frame .zero stays 0 pt wide and draws nothing
        // unless it grows with the scroll view.
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        scroll.documentView = editor
        controller.attachEditor(editor, to: noteID)
        context.coordinator.editor = editor
        context.coordinator.restyle()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NotesTextView else { return }
        if context.coordinator.noteID != noteID {
            controller.detachEditor(editor, from: context.coordinator.noteID)
            context.coordinator.noteID = noteID
        }
        controller.attachEditor(editor, to: noteID)
        context.coordinator.controller = controller
        if editor.string != body {
            let selection = editor.selectedRange()
            editor.string = body
            editor.setSelectedRange(NSRange(location: min(selection.location, (body as NSString).length), length: 0))
            context.coordinator.restyle()
        }
        if caretToEndRequested {
            let end = NSRange(location: (editor.string as NSString).length, length: 0)
            editor.setSelectedRange(end)
            controller.updateSelection(id: noteID, range: end)
            DispatchQueue.main.async {
                caretToEndRequested = false
                onCaretPlaced()
            }
        }
        if focusRequested, let window = editor.window {
            window.makeFirstResponder(editor)
            DispatchQueue.main.async { focusRequested = false }
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let editor = scroll.documentView as? NotesTextView else { return }
        coordinator.controller.detachEditor(editor, from: coordinator.noteID)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var controller: NotesController
        var noteID: NoteID
        weak var editor: NotesTextView?

        init(controller: NotesController, noteID: NoteID) {
            self.controller = controller
            self.noteID = noteID
        }

        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            controller.updateBody(id: noteID, body: editor.string)
            restyle()
        }

        func restyle() {
            guard let editor, let storage = editor.textStorage else { return }
            MarkdownTextStyler.apply(to: storage)
            editor.typingAttributes = [.font: MarkdownTextStyler.bodyFont, .foregroundColor: NSColor.labelColor]
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor else { return }
            controller.updateSelection(id: noteID, range: editor.selectedRange())
        }
    }
}
