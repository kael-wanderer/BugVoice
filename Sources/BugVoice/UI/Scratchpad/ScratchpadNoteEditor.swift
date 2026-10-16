import AppKit
import BugVoiceMac
import SwiftUI
import UniformTypeIdentifiers
import VoiceCore

/// The note in the Scratchpad window: title, labels, body (Markdown or Doc),
/// the action row (view switch, Dictate, History, Trash, Copy) and the
/// AI or Formatting bar.
struct ScratchpadNoteEditor: View {
    @Bindable var model: AppModel
    @Bindable var assistant: ScratchpadAssistant
    let note: NoteDocument
    @Binding var bodyFocusRequested: Bool
    @FocusState private var titleFocused: Bool
    @State private var confirmDelete = false
    @State private var confirmExternalReload = false
    @State private var caretToEndRequested = false
    @State private var dictateWhenCaretPlaced = false

    private var controller: NotesController { model.notesController }

    var body: some View {
        VStack(spacing: 0) {
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
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 6)

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
            .padding(.bottom, 6)

            statusRow

            ZStack(alignment: .topLeading) {
                if model.scratchpadView == .markdown {
                    NotesBodyEditor(
                        controller: controller,
                        noteID: note.id,
                        body: note.body,
                        focusRequested: $bodyFocusRequested,
                        caretToEndRequested: $caretToEndRequested,
                        onCaretPlaced: caretPlaced
                    )
                    if note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Hold \(model.settings.hotkey.displayName) to dictate, or start typing.")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                } else {
                    MarkdownDocView(text: note.body) { line in
                        if let body = MarkdownCommands.toggleTask(in: note.body, line: line) {
                            controller.updateBody(id: note.id, body: body)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) { noticeView }

            VStack(spacing: 8) {
                if let reply = assistant.reply, reply.noteID == note.id {
                    AIReplyView(
                        reply: reply,
                        onInsert: { assistant.insertReply(controller: controller) },
                        onDismiss: { assistant.dismissReply() })
                }
                actionRow
                if model.notesIsListening { listeningBar }
                bottomBar
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background { shortcuts }
        .confirmationDialog(
            "Move \(note.title) to the Trash?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                Task {
                    do { try await model.deleteNote(note.id) }
                    catch { model.saveError = "Could not move note to the Trash: \(error.localizedDescription)" }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Reload this note and discard your unsaved changes?",
            isPresented: $confirmExternalReload,
            titleVisibility: .visible
        ) {
            Button("Reload", role: .destructive) {
                Task { await controller.resolveExternalChange(id: note.id, keepMine: false) }
            }
            Button("Keep mine") { Task { await controller.resolveExternalChange(id: note.id, keepMine: true) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Rows

    @ViewBuilder private var statusRow: some View {
        if controller.externalChangeMessage(for: note.id) != nil {
            HStack {
                Text("Changed outside BugVoice").foregroundStyle(.orange)
                Spacer()
                Button("Resolve…") { confirmExternalReload = true }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 6)
        } else if controller.saveMessage(for: note.id).hasPrefix("Could not") {
            HStack {
                Text(controller.saveMessage(for: note.id)).foregroundStyle(.red)
                Spacer()
                Button("Retry save") { Task { _ = await controller.flush(id: note.id) } }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 6)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Picker("View", selection: Binding(get: { model.scratchpadView }, set: { model.scratchpadView = $0 })) {
                ForEach(NoteViewMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            NotesMicButton(
                disabled: model.isListening || model.dictation?.isBusy == true || model.notesIsListening,
                action: dictate
            )
            .frame(width: 30, height: 30)
            .help("Dictate")
            historyMenu
            Button {
                confirmDelete = true
            } label: {
                Image(systemName: "trash").frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Move note to Trash")
            .accessibilityLabel("Move note to Trash")
            copyMenu
        }
    }

    private var historyMenu: some View {
        let entries = assistant.history.entries(for: note.id)
        return Menu {
            Section("AI changes in this note") {
                ForEach(entries) { entry in
                    Button("\(entry.title) · \(entry.date.formatted(date: .omitted, time: .shortened)) · \(entry.wordsLabel)") {
                        assistant.restore(entry, noteID: note.id, controller: controller)
                    }
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(entries.isEmpty)
        .help(entries.isEmpty ? "No AI changes yet" : "History")
        .accessibilityLabel("History")
    }

    private var copyMenu: some View {
        Menu {
            Button("Copy") { copy() }
            Button("Copy and close") { copyAndClose() }
            Divider()
            Button("Copy as Markdown") { copyMarkdown() }
            Button("Copy as plain text") { copyPlainText() }
            Divider()
            Button("Export…") { exportMarkdown() }
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        } primaryAction: {
            copy()
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .fixedSize()
        .help("Copy (⌘⇧C)")
    }

    @ViewBuilder private var bottomBar: some View {
        Group {
            if model.settings.scratchpad.bottomBar == .ai {
                AIBar(assistant: assistant, model: model, noteID: note.id, input: currentInput)
            } else if model.scratchpadView == .markdown {
                MarkdownToolbar { command in run(command) }
            } else {
                Text("Doc view is read only. Switch to Markdown to edit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
    }

    @ViewBuilder private var noticeView: some View {
        if let notice = assistant.notice, notice.noteID == note.id {
            HStack(spacing: 10) {
                Text(notice.text)
                Button("Undo") { assistant.undo(controller: controller) }
                    .buttonStyle(.borderless)
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.25)))
            .padding(.bottom, 10)
        } else if let notice = model.notice {
            Text(notice)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.25)))
                .padding(.bottom, 10)
        }
    }

    private var listeningBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform").foregroundStyle(.red)
            Text("Listening").fontWeight(.semibold)
            if let started = model.notesRecordingStartedAt {
                TimelineView(.periodic(from: started, by: 1)) { context in
                    Text(elapsed(context.date.timeIntervalSince(started))).monospacedDigit()
                }
            }
            ProgressView(value: Double(model.dictation?.recordingLevel ?? 0), total: 0.2)
                .frame(width: 80)
            Text("Text will be added to this note").foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("Stop") { model.dictation?.toggleNotesRecording() }
                .keyboardShortcut(.escape)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    /// ⌘1…⌘3 chips, ⌘⇧C Copy, ⌘↩ Copy and close.
    private var shortcuts: some View {
        ZStack {
            ForEach(NoteTransform.allCases, id: \.self) { transform in
                Button("") {
                    if let input = currentInput() { assistant.run(transform, input: input, model: model) }
                }
                .keyboardShortcut(KeyEquivalent(transform.shortcutKey), modifiers: .command)
            }
            Button("") { copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("") { copyAndClose() }
                .keyboardShortcut(.return, modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Actions

    private func currentInput() -> TransformInput? {
        TransformInput.capture(noteID: note.id, controller: controller, useSelection: model.scratchpadView == .markdown)
    }

    private func run(_ command: MarkdownToolbarCommand) {
        guard let body = controller.note(id: note.id)?.body else { return }
        let selection = ScratchpadEditing.selection(of: note.id, controller: controller)
        guard selection.isValid(inUTF16Length: (body as NSString).length) else { return }
        let edit: MarkdownEdit? = switch command {
        case .inline(let marker): MarkdownCommands.toggleInline(marker, in: body, selection: selection)
        case .underline: MarkdownCommands.toggleUnderline(in: body, selection: selection)
        case .line(let format): MarkdownCommands.toggleLineFormat(format, in: body, selection: selection)
        case .indent(let outdent): MarkdownCommands.indent(in: body, selection: selection, outdent: outdent)
        case .link: MarkdownCommands.insertLink(in: body, selection: selection)
        case .table(let columns, let rows): MarkdownCommands.insertTable(columns: columns, rows: rows, in: body, selection: selection)
        }
        if let edit { ScratchpadEditing.apply(edit, to: note.id, controller: controller) }
        bodyFocusRequested = true
    }

    /// The selection when there is one in Markdown view, otherwise the whole body.
    private func copySource() -> String {
        guard let latest = controller.note(id: note.id) else { return note.body }
        if model.scratchpadView == .markdown, let input = currentInput(), input.isSelection { return input.text }
        return latest.body
    }

    private func copy() {
        if ScratchpadClipboard.copyFormatted(copySource()) {
            model.showNotice("Copied")
        } else {
            model.saveError = "Could not copy: the clipboard did not accept the text."
        }
    }

    private func copyAndClose() {
        guard ScratchpadClipboard.copyFormatted(copySource()) else {
            model.saveError = "Could not copy: the clipboard did not accept the text."
            return
        }
        model.closeScratchpadWindow(returnToPreviousApp: true)
    }

    private func copyMarkdown() {
        Task { @MainActor in
            await controller.commitTitle(id: note.id, reason: .focusOut)
            guard let latest = controller.note(id: note.id) else { return }
            ScratchpadClipboard.copyText(NotesExporter.markdown(title: latest.title, body: latest.body))
            model.showNotice("Copied as Markdown")
        }
    }

    private func copyPlainText() {
        ScratchpadClipboard.copyText(MarkdownPlainText.convert(copySource()))
        model.showNotice("Copied as plain text")
    }

    private func exportMarkdown() {
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

    private func elapsed(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct NotesMicButton: NSViewRepresentable {
    let disabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NonFocusNSButton(title: "", target: context.coordinator, action: #selector(Coordinator.activate))
        button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Dictate")
        button.imagePosition = .imageOnly
        button.bezelStyle = .circular
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

struct NotesBodyEditor: NSViewRepresentable {
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

        /// Tab and Shift-Tab indent list lines; elsewhere Tab types a tab.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let outdent: Bool
            switch commandSelector {
            case #selector(NSResponder.insertTab(_:)): outdent = false
            case #selector(NSResponder.insertBacktab(_:)): outdent = true
            default: return false
            }
            let range = textView.selectedRange()
            guard let edit = MarkdownCommands.indent(
                in: textView.string, selection: NotesTextRange(location: range.location, length: range.length), outdent: outdent)
            else { return outdent }
            ScratchpadEditing.apply(edit, to: noteID, controller: controller)
            return true
        }
    }
}
