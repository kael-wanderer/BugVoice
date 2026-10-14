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

    private var controller: NotesController { model.notesController }
    private var selectedNote: NoteDocument? {
        guard let id = controller.selectedNoteID else { return nil }
        return controller.note(id: id)
    }
    private var filteredNotes: [NotesListItem] {
        NotesListProjection.filter(
            controller.notes.map { NotesListItem(id: $0.id, title: $0.title, body: $0.body, modifiedAt: $0.modifiedAt) },
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
            if controller.selectedNoteID == nil, let first = controller.notes.first {
                try? await controller.select(id: first.id)
                bodyFocusRequested = true
            }
        }
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
                                    try await controller.select(id: item.id)
                                    bodyFocusRequested = true
                                }
                                catch { model.saveError = "Could not save the current note: \(error.localizedDescription)" }
                            }
                        } label: {
                            noteRow(item)
                        }
                        .buttonStyle(.plain)
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
            Text(item.title).font(.headline).lineLimit(1)
            HStack(spacing: 6) {
                Text(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                Text("·")
                Text("\(wordCount(item.body)) words")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var editor: some View {
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
                    Button("Copy as Markdown") { copyMarkdown(note) }
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

                Text("Markdown · saved to Notes/\(note.slug).md · style: document")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)

                statusRow(for: note)

                NotesBodyEditor(
                    controller: controller,
                    noteID: note.id,
                    body: note.body,
                    focusRequested: $bodyFocusRequested
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                NotesMicButton(
                    disabled: model.isListening || model.dictation?.isBusy == true,
                    action: { model.dictation?.toggleNotesRecording() }
                )
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
                _ = try await controller.create()
                bodyFocusRequested = true
            } catch {
                model.saveError = "Could not create note: \(error.localizedDescription)"
            }
        }
    }

    private func deleteSelected() {
        guard let id = controller.selectedNoteID else { return }
        Task {
            do { try await controller.delete(id: id, confirmed: true) }
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
        let button = NonFocusNSButton(title: "Dictate into note", target: context.coordinator, action: #selector(Coordinator.activate))
        button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Dictate into note")
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

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller, noteID: noteID)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let editor = NotesTextView(frame: .zero)
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 8, height: 10)
        editor.string = body

        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.documentView = editor
        controller.attachEditor(editor, to: noteID)
        context.coordinator.editor = editor
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
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor else { return }
            controller.updateSelection(id: noteID, range: editor.selectedRange())
        }
    }
}
