import AppKit
import Foundation
import Observation
import VoiceCore

public enum NotesControllerError: Error {
    case saveFailed(NoteID)
}

public enum NotesInsertionResult: Equatable, Sendable {
    case inserted
    case noteDeleted
    case saveFailed
}

/// Why an agent's note edit was refused. Nothing changes when it is.
public enum AgentEditRefusal: Error, Equatable {
    case unsaved, dictating

    public var message: String {
        switch self {
        case .unsaved: "This note has unsaved changes in BugVoice. Try again after it saves."
        case .dictating: "BugVoice is dictating into this note. Try again in a moment."
        }
    }
}

public struct NotesInsertionRecovery: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let noteID: NoteID
    public let text: String
    public let message: String

    public init(id: UUID = UUID(), noteID: NoteID, text: String, message: String) {
        self.id = id
        self.noteID = noteID
        self.text = text
        self.message = message
    }
}

@MainActor
@Observable
public final class NotesController {
    @ObservationIgnored private let store: NotesStore
    @ObservationIgnored private var loaded: [NoteID: LoadedNote] = [:]
    @ObservationIgnored private var saveTasks: [NoteID: Task<Void, Never>] = [:]
    @ObservationIgnored private var saveTokens: [NoteID: UUID] = [:]
    /// Dictation captures not yet released, per note. Agent edits wait for zero.
    @ObservationIgnored private var dictating: [NoteID: Int] = [:]
    /// Tests only: runs after the last await before an agent edit changes the note.
    @ObservationIgnored var agentEditWillMutate: (() -> Void)?
    public private(set) var selectedNoteID: NoteID?
    public private(set) var notes: [NoteDocument] = []
    public private(set) var changeCounter: UInt64 = 0
    public private(set) var listError: String?
    public private(set) var insertionRecoveries: [NotesInsertionRecovery] = []

    @ObservationIgnored public var onSaved: ((NoteID) -> Void)?
    @ObservationIgnored public var onListLoaded: (() -> Void)?

    public init(store: NotesStore) {
        self.store = store
    }

    public func load(id: NoteID) async throws {
        if loaded[id] != nil { return }
        let note = try await store.open(id: id)
        loaded[id] = LoadedNote(note: note)
        changed()
    }

    public func select(id: NoteID) async throws {
        if let previous = selectedNoteID, previous != id {
            guard await flush(id: previous) else { throw NotesControllerError.saveFailed(previous) }
        }
        try await load(id: id)
        selectedNoteID = id
        await refresh(id: id, trigger: .selection)
        changed()
    }

    public func reloadList() async {
        do {
            notes = try await store.list()
            listError = nil
            onListLoaded?()
        } catch {
            listError = "Could not read Notes: \(error.localizedDescription)"
        }
        changed()
    }

    @discardableResult
    public func create(title: String = "Untitled", body: String = "", frontMatter: NoteFrontMatter = NoteFrontMatter()) async throws -> NoteDocument {
        if let selectedNoteID {
            guard await flush(id: selectedNoteID) else { throw NotesControllerError.saveFailed(selectedNoteID) }
        }
        let note = try await store.create(title: title, body: body, frontMatter: frontMatter)
        loaded[note.id] = LoadedNote(note: note)
        selectedNoteID = note.id
        onSaved?(note.id)
        await reloadList()
        changed()
        return note
    }

    /// Saves and deselects the current note; the editor shows "Select a note".
    public func clearSelection() async {
        if let selectedNoteID { _ = await flush(id: selectedNoteID) }
        selectedNoteID = nil
        changed()
    }

    public func delete(id: NoteID, confirmed: Bool) async throws {
        guard confirmed else { return }
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        saveTokens[id] = nil
        try await store.delete(id: id, confirmed: true)
        loaded[id] = nil
        if selectedNoteID == id { selectedNoteID = nil }
        await reloadList()
        changed()
    }

    public func updateTitleDraft(id: NoteID, title: String) {
        guard let state = loaded[id] else { return }
        state.titleDraft = title
        state.isTitleEditing = true
        changed()
    }

    public func titleDraft(id: NoteID) -> String? {
        _ = changeCounter
        return loaded[id]?.titleDraft
    }

    public func commitTitle(id: NoteID, reason: NotesTitleCommitReason) async {
        guard let state = loaded[id] else { return }
        let requestedTitle = NotesAutosavePolicy.committedTitle(
            previous: state.note.title,
            draft: state.titleDraft,
            reason: reason
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let title = requestedTitle.isEmpty ? "Untitled" : requestedTitle
        state.isTitleEditing = false
        state.titleDraft = title
        guard title != state.note.title else { changed(); return }
        guard await flushBody(id: id) else { return }
        guard let latest = loaded[id] else { return }
        do {
            let renamed = try await store.rename(
                id: id,
                title: title,
                revision: latest.note.revision &+ 1,
                expectedVersion: latest.note.fileVersion
            )
            latest.note.title = renamed.title
            latest.note.slug = renamed.slug
            latest.note.fileVersion = renamed.fileVersion
            latest.note.modifiedAt = renamed.modifiedAt
            latest.note.needsNormalization = false
            latest.note.revision = renamed.revision
            latest.lastPersistedRevision = latest.note.revision
            latest.isDirty = false
            latest.saveError = nil
            latest.externalChangeDetected = false
            updateListRow(latest.note)
        } catch NotesStoreError.externalChange {
            do {
                let change = try await store.checkExternalChange(
                    id: id,
                    knownVersion: latest.note.fileVersion,
                    isDirty: true
                )
                switch change {
                case .conflict(let version): latest.externalVersion = version
                case .missingConflict, .deleted: latest.externalVersion = nil
                case .unchanged, .reloaded, .saved, .stale: break
                }
                latest.externalChangeDetected = true
            } catch {
                latest.saveError = "Could not check note changes: \(error.localizedDescription)"
            }
        } catch {
            latest.saveError = "Could not save note: \(error.localizedDescription)"
        }
        changed()
    }

    public func saveMessage(for id: NoteID) -> String {
        _ = changeCounter
        guard let state = loaded[id] else { return "" }
        if state.externalChangeDetected { return "Changed outside BugVoice" }
        if let saveError = state.saveError { return saveError }
        return state.isDirty ? "Saving" : "Saved"
    }

    public var hasUnsavedChanges: Bool {
        _ = changeCounter
        return loaded.values.contains { $0.isDirty || $0.titleDraft != $0.note.title }
    }

    public func resolveExternalChange(id: NoteID, keepMine: Bool) async {
        guard let state = loaded[id], state.externalChangeDetected else { return }
        if !keepMine {
            do {
                var reloaded = try await store.open(id: id)
                if reloaded.body != state.note.body { reloaded.revision = max(reloaded.revision, state.note.revision &+ 1) }
                state.undoManager.removeAllActions()
                state.note = reloaded
                state.titleDraft = reloaded.title
                state.lastPersistedRevision = reloaded.revision
                state.isDirty = false
                state.externalChangeDetected = false
                state.externalVersion = nil
                state.saveError = nil
                state.editor?.string = reloaded.body
                updateListRow(reloaded)
            } catch NotesStoreError.missing {
                loaded[id] = nil
                if selectedNoteID == id { selectedNoteID = nil }
                removeListRow(id: id)
            } catch {
                state.saveError = "Could not reload note: \(error.localizedDescription)"
            }
            changed()
            return
        }

        do {
            let result = try await store.save(
                state.note,
                expectedVersion: state.note.fileVersion,
                isDirty: true,
                keepMine: true,
                confirmedExternalVersion: state.externalVersion
            )
            switch result {
            case .saved(let saved, let version):
                state.note.fileVersion = version
                state.note.modifiedAt = saved.modifiedAt
                state.note.needsNormalization = false
                state.lastPersistedRevision = saved.revision
                state.isDirty = false
                state.externalChangeDetected = false
                state.externalVersion = nil
                state.saveError = nil
                updateListRow(state.note)
                if state.titleDraft != state.note.title {
                    await commitTitle(id: id, reason: .returnKey)
                }
            case .conflict(let version):
                state.externalVersion = version
                state.externalChangeDetected = true
            case .missingConflict:
                state.externalVersion = nil
                state.externalChangeDetected = true
            case .deleted:
                state.externalVersion = nil
                state.externalChangeDetected = true
            case .reloaded, .stale, .unchanged:
                break
            }
        } catch {
            state.saveError = "Could not save note: \(error.localizedDescription)"
        }
        changed()
    }

    public func captureAtStart(
        bugVoiceIsFrontmost: Bool,
        notesPageIsSelected: Bool,
        firstResponderEditorID: UUID?
    ) -> NotesDictationCapture? {
        guard let id = selectedNoteID,
              let state = loaded[id],
              !state.externalChangeDetected,
              let editor = state.editor else { return nil }
        let selection = editor.selectedRange()
        state.lastSelection = selection
        let bodyLength = (state.note.body as NSString).length
        let conditions = NotesRouteConditions(
            bugVoiceIsFrontmost: bugVoiceIsFrontmost,
            notesPageIsSelected: notesPageIsSelected,
            selectedNoteID: id,
            selectedEditorID: editor.editorID,
            firstResponderEditorID: firstResponderEditorID,
            selection: NotesTextRange(location: selection.location, length: selection.length),
            bodyUTF16Length: bodyLength,
            noteRevision: state.note.revision,
            editingBlocked: state.externalChangeDetected
        )
        return holding(NotesRoutePolicy.capture(atStart: conditions))
    }

    public func captureSelectedNoteForMic() -> NotesDictationCapture? {
        guard let id = selectedNoteID, let state = loaded[id] else { return nil }
        return holding(NotesRoutePolicy.captureForMic(
            selectedNoteID: id,
            editorID: state.editorID,
            lastSelection: NotesTextRange(location: state.lastSelection.location, length: state.lastSelection.length),
            bodyUTF16Length: (state.note.body as NSString).length,
            noteRevision: state.note.revision,
            editingBlocked: state.externalChangeDetected
        ))
    }

    /// Ends a capture from `captureAtStart` or `captureSelectedNoteForMic`, after
    /// its dictation was inserted, cancelled or failed.
    public func releaseCapture(_ capture: NotesDictationCapture) {
        let count = (dictating[capture.noteID] ?? 0) - 1
        dictating[capture.noteID] = count > 0 ? count : nil
    }

    private func holding(_ capture: NotesDictationCapture?) -> NotesDictationCapture? {
        if let capture { dictating[capture.noteID, default: 0] += 1 }
        return capture
    }

    // MARK: Agents

    /// Saves a new note without selecting it, saving the selected note, or opening a window.
    public func createForAgent(title: String, body: String, frontMatter: NoteFrontMatter) async throws -> NoteDocument {
        let note = try await store.create(title: title, body: body, frontMatter: frontMatter)
        onSaved?(note.id)
        await reloadList()
        changed()
        return note
    }

    /// Replaces or appends to a note for an agent. Refused, with nothing changed,
    /// while the owner has unsaved changes in it or dictation targets it.
    /// `labels` replaces the folder and tags when given.
    public func agentEdit(
        id: NoteID, body: String, append: Bool, title: String?, labels: (folderID: FolderID?, tags: [String])?
    ) async throws -> NoteDocument {
        guard dictating[id] == nil else { throw AgentEditRefusal.dictating }
        let newTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard loaded[id] != nil else {
            return try await agentEditOnDisk(id: id, body: body, append: append, title: newTitle, labels: labels)
        }

        await refresh(id: id, trigger: .beforeSave)
        agentEditWillMutate?()
        // Dictation may have started while the refresh waited.
        guard dictating[id] == nil else { throw AgentEditRefusal.dictating }
        guard let state = loaded[id] else { throw NotesStoreError.missing(id) }
        guard !state.isDirty, state.titleDraft == state.note.title, !state.externalChangeDetected else {
            throw AgentEditRefusal.unsaved
        }
        let newBody = append ? Self.appending(body, to: state.note.body) : body
        if newBody != state.note.body {
            registerUndo(for: id, body: state.note.body, selection: state.editor?.selectedRange(), actionName: "Agent edit")
            state.note.body = newBody
            if let editor = state.editor { replaceEditorContentsWithoutUndo(editor, with: newBody) }
        }
        if let labels {
            state.note.frontMatter.folderID = labels.folderID
            state.note.frontMatter.tags = labels.tags
        }
        state.note.revision &+= 1
        state.note.modifiedAt = .now
        state.isDirty = true
        state.saveError = nil
        guard await flushBody(id: id) else { throw NotesControllerError.saveFailed(id) }
        if let newTitle, newTitle != state.note.title {
            state.titleDraft = newTitle
            await commitTitle(id: id, reason: .returnKey)
            guard loaded[id]?.note.title == newTitle else { throw NotesControllerError.saveFailed(id) }
        }
        guard let saved = loaded[id]?.note else { throw NotesStoreError.missing(id) }
        updateListRow(saved)
        changed()
        return saved
    }

    private func agentEditOnDisk(
        id: NoteID, body: String, append: Bool, title: String?, labels: (folderID: FolderID?, tags: [String])?
    ) async throws -> NoteDocument {
        let current = try await store.open(id: id)
        agentEditWillMutate?()
        // The note may have been opened, or dictation started, while the file was read.
        guard dictating[id] == nil else { throw AgentEditRefusal.dictating }
        guard loaded[id] == nil else { throw AgentEditRefusal.unsaved }
        var updated = current
        updated.body = append ? Self.appending(body, to: current.body) : body
        if let labels {
            updated.frontMatter.folderID = labels.folderID
            updated.frontMatter.tags = labels.tags
        }
        updated.revision &+= 1
        guard case .saved(var saved, let version) = try await store.save(
            updated, expectedVersion: current.fileVersion, isDirty: true)
        else { throw NotesControllerError.saveFailed(id) }
        if let title, title != saved.title {
            saved = try await store.rename(id: id, title: title, revision: saved.revision &+ 1, expectedVersion: version)
        }
        updateListRow(saved)
        changed()
        return saved
    }

    /// One blank line between the old text and the new; an empty note takes the text as is.
    static func appending(_ text: String, to body: String) -> String {
        guard !body.isEmpty else { return text }
        let base = body.hasSuffix("\n") ? String(body.dropLast()) : body
        return base + "\n\n" + text
    }

    public func note(id: NoteID) -> NoteDocument? {
        _ = changeCounter
        return loaded[id]?.note
    }

    public func isLoaded(id: NoteID) -> Bool {
        _ = changeCounter
        return loaded[id] != nil
    }

    /// The text view showing the note, if one is on screen.
    public func attachedEditor(id: NoteID) -> NotesTextView? {
        loaded[id]?.editor
    }

    public func undoManager(for id: NoteID) -> UndoManager? {
        loaded[id]?.undoManager
    }

    public func attachEditor(_ editor: NotesTextView?, to id: NoteID) {
        guard let state = loaded[id] else { return }
        if let editor, let previousID = editor.noteID, previousID != id,
           loaded[previousID]?.editor === editor {
            loaded[previousID]?.editor = nil
        }
        state.editor = editor
        if let editor {
            state.editorID = editor.editorID
            state.lastSelection = editor.selectedRange()
        }
        editor?.notesController = self
        editor?.noteID = id
        editor?.allowsUndo = true
        if let editor, editor.string != state.note.body { replaceEditorContentsWithoutUndo(editor, with: state.note.body) }
    }

    public func detachEditor(_ editor: NotesTextView, from id: NoteID) {
        guard loaded[id]?.editor === editor else { return }
        loaded[id]?.editor = nil
        loaded[id]?.lastSelection = editor.selectedRange()
        if editor.noteID == id {
            editor.notesController = nil
            editor.noteID = nil
        }
    }

    public func updateSelection(id: NoteID, range: NSRange) {
        guard let state = loaded[id] else { return }
        let length = (state.note.body as NSString).length
        let location = min(max(range.location, 0), length)
        let selectionLength = min(max(range.length, 0), length - location)
        state.lastSelection = NSRange(location: location, length: selectionLength)
    }

    /// The NSTextView delegate calls this after ordinary user edits. The
    /// buffer is authoritative, and each change rearms the 500 ms save.
    public func updateBody(id: NoteID, body: String) {
        guard let state = loaded[id], state.note.body != body else { return }
        state.note.body = body
        state.note.revision &+= 1
        state.note.modifiedAt = .now
        state.isDirty = true
        state.saveError = nil
        scheduleSave(id: id)
        changed()
    }

    /// Changes a note's folder and tags. Loads the note if needed; the change
    /// rides the same autosave as body edits, so unsaved typing is kept.
    public func setLabels(id: NoteID, folderID: FolderID?, tags: [String]) async throws {
        try await load(id: id)
        guard let state = loaded[id] else { return }
        guard state.note.frontMatter.folderID != folderID || state.note.frontMatter.tags != tags else { return }
        state.note.frontMatter.folderID = folderID
        state.note.frontMatter.tags = tags
        state.note.revision &+= 1
        state.isDirty = true
        state.saveError = nil
        updateListRow(state.note)
        scheduleSave(id: id)
        changed()
    }

    public func setPinned(id: NoteID, pinned: Bool) async throws {
        try await load(id: id)
        guard let state = loaded[id], state.note.frontMatter.pinned != pinned else { return }
        state.note.frontMatter.pinned = pinned
        state.note.revision &+= 1
        state.isDirty = true
        state.saveError = nil
        updateListRow(state.note)
        scheduleSave(id: id)
        changed()
    }

    /// Inserts into the captured note, regardless of current focus or selected
    /// note. The visible editor is updated from the same authoritative buffer.
    public func insert(capture: NotesDictationCapture, text: String) async -> NotesInsertionResult {
        guard loaded[capture.noteID] != nil else {
            do {
                let outcome = try await store.applyInsertion(capture: capture, text: text)
                switch outcome {
                case .saved(let saved, _):
                    updateListRow(saved)
                    return .inserted
                case .deleted:
                    return .noteDeleted
                case .unchanged, .reloaded, .conflict, .missingConflict, .stale:
                    retainInsertionRecovery(noteID: capture.noteID, text: text)
                    return .saveFailed
                }
            } catch {
                retainInsertionRecovery(noteID: capture.noteID, text: text, detail: error.localizedDescription)
                return .saveFailed
            }
        }

        await refresh(id: capture.noteID, trigger: .beforeSave)
        guard let latestState = loaded[capture.noteID] else { return .noteDeleted }
        let bodyLength = (latestState.note.body as NSString).length
        guard let plan = NotesInsertionPlan.make(
            capture: capture,
            noteExists: true,
            currentRevision: latestState.note.revision,
            currentBodyUTF16Length: bodyLength,
            editorVisible: latestState.editor != nil
        ) else { return .noteDeleted }

        let range: NSRange
        switch plan.location {
        case .selection(let selection):
            range = NSRange(location: selection.location, length: selection.length)
        case .bodyEnd(let location):
            range = NSRange(location: location, length: 0)
        }
        let oldBody = latestState.note.body
        let spaced = NotesSpacing.fit(text, into: oldBody, at: range.location, replacing: range.length)
        let updatedBody = (oldBody as NSString).replacingCharacters(in: range, with: spaced)
        if let editor = latestState.editor {
            guard let textStorage = editor.textStorage else {
                retainInsertionRecovery(noteID: capture.noteID, text: text)
                return .saveFailed
            }
            let undoManager = latestState.undoManager
            editor.breakUndoCoalescing()
            undoManager.beginUndoGrouping()
            guard editor.shouldChangeText(in: range, replacementString: spaced) else {
                undoManager.endUndoGrouping()
                retainInsertionRecovery(noteID: capture.noteID, text: text)
                return .saveFailed
            }
            textStorage.replaceCharacters(in: range, with: spaced)
            latestState.note.body = updatedBody
            latestState.note.revision &+= 1
            latestState.note.modifiedAt = .now
            latestState.isDirty = true
            editor.didChangeText()
            editor.setSelectedRange(NSRange(location: range.location + (spaced as NSString).length, length: 0))
            latestState.lastSelection = editor.selectedRange()
            undoManager.setActionName("Dictation")
            undoManager.endUndoGrouping()
        } else {
            registerUndo(for: capture.noteID, body: oldBody, selection: nil)
            latestState.note.body = updatedBody
            latestState.note.revision &+= 1
            latestState.note.modifiedAt = .now
            latestState.isDirty = true
        }
        scheduleSave(id: capture.noteID)
        changed()
        return .inserted
    }

    public func dismissInsertionRecovery(id: UUID) {
        insertionRecoveries.removeAll { $0.id == id }
        changed()
    }

    private func retainInsertionRecovery(noteID: NoteID, text: String, detail: String? = nil) {
        let message = detail.map { "Could not save this dictation: \($0)" } ?? "Could not save this dictation."
        insertionRecoveries.append(NotesInsertionRecovery(noteID: noteID, text: text, message: message))
        changed()
    }

    @discardableResult
    public func flush(id: NoteID) async -> Bool {
        if let state = loaded[id], state.titleDraft != state.note.title {
            await commitTitle(id: id, reason: .focusOut)
            guard let updated = loaded[id], updated.titleDraft == updated.note.title, !updated.externalChangeDetected else { return false }
        }
        return await flushBody(id: id)
    }

    private func flushBody(id: NoteID) async -> Bool {
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        saveTokens[id] = nil
        let success = await save(id: id, taskToken: nil)
        changed()
        return success
    }

    @discardableResult
    public func flushAll() async -> Bool {
        var success = true
        for id in loaded.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            if !(await flush(id: id)) { success = false }
        }
        return success
    }

    public func hasPendingSave(id: NoteID) -> Bool {
        saveTasks[id] != nil
    }

    public func refresh(id: NoteID, trigger: NotesRefreshTrigger) async {
        guard let state = loaded[id] else { return }
        do {
            let result = try await store.checkExternalChange(
                id: id,
                knownVersion: state.note.fileVersion,
                isDirty: state.isDirty || state.titleDraft != state.note.title
            )
            switch result {
            case .unchanged:
                state.externalChangeDetected = false
                state.externalVersion = nil
            case .reloaded(let note, let version):
                var reloaded = note
                if reloaded.body != state.note.body {
                    reloaded.revision = max(reloaded.revision, state.note.revision &+ 1)
                }
                state.undoManager.removeAllActions()
                reloaded.fileVersion = version
                state.note = reloaded
                state.titleDraft = reloaded.title
                state.lastPersistedRevision = reloaded.revision
                state.isDirty = false
                state.externalChangeDetected = false
                state.editor?.string = reloaded.body
                updateListRow(reloaded)
            case .conflict(let version):
                state.externalChangeDetected = true
                state.externalVersion = version
            case .missingConflict:
                state.externalChangeDetected = true
                state.externalVersion = nil
            case .saved, .stale, .deleted:
                if case .deleted = result {
                    loaded[id] = nil
                    if selectedNoteID == id { selectedNoteID = nil }
                    removeListRow(id: id)
                }
            }
        } catch {
            state.externalChangeDetected = true
            state.saveError = "Could not check note changes: \(error.localizedDescription)"
        }
        changed()
    }

    public func refreshAll(trigger: NotesRefreshTrigger) async {
        for id in loaded.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            await refresh(id: id, trigger: trigger)
        }
        await reloadList()
    }

    public func externalChangeMessage(for id: NoteID) -> String? {
        _ = changeCounter
        return loaded[id]?.externalChangeDetected == true ? "Changed outside BugVoice" : nil
    }

    private func scheduleSave(id: NoteID) {
        saveTasks[id]?.cancel()
        let token = UUID()
        saveTokens[id] = token
        saveTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NotesAutosavePolicy.bodyDebounceInterval))
            guard !Task.isCancelled, let self, self.saveTokens[id] == token else { return }
            _ = await self.save(id: id, taskToken: token)
        }
    }

    private func save(id: NoteID, taskToken: UUID?) async -> Bool {
        guard let state = loaded[id], state.isDirty else {
            clearSaveTask(id: id, matching: taskToken)
            return true
        }
        let snapshot = state.note
        do {
            let result = try await store.save(
                snapshot,
                expectedVersion: snapshot.fileVersion,
                isDirty: true
            )
            switch result {
            case .saved(let saved, let version):
                if saved.revision >= state.lastPersistedRevision {
                    state.note.fileVersion = version
                    state.note.modifiedAt = saved.modifiedAt
                    state.note.needsNormalization = false
                    state.lastPersistedRevision = saved.revision
                }
                state.saveError = nil
                if state.note.revision == saved.revision {
                    state.isDirty = false
                    state.externalChangeDetected = false
                    state.externalVersion = nil
                }
                updateListRow(state.note)
            case .reloaded(let note, _):
                if !state.isDirty {
                    state.note = note
                    state.lastPersistedRevision = note.revision
                    state.editor?.string = note.body
                    updateListRow(note)
                }
            case .conflict(let version):
                state.externalChangeDetected = true
                state.externalVersion = version
            case .missingConflict:
                state.externalChangeDetected = true
                state.externalVersion = nil
            case .stale:
                break
            case .unchanged:
                break
            case .deleted:
                state.externalChangeDetected = true
                state.externalVersion = nil
            }
        } catch {
            state.saveError = "Could not save note: \(error.localizedDescription)"
        }
        clearSaveTask(id: id, matching: taskToken)
        changed()
        return !state.isDirty && !state.externalChangeDetected && state.saveError == nil
    }

    private func registerUndo(for id: NoteID, body: String, selection: NSRange?, actionName: String = "Dictation") {
        guard let manager = loaded[id]?.undoManager else { return }
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: self) { controller in
            controller.restore(id: id, body: body, selection: selection)
        }
        manager.setActionName(actionName)
        manager.endUndoGrouping()
    }

    private func clearSaveTask(id: NoteID, matching token: UUID?) {
        guard let token else { return }
        guard saveTokens[id] == token else { return }
        saveTokens[id] = nil
        saveTasks[id] = nil
    }

    private func updateListRow(_ note: NoteDocument) {
        onSaved?(note.id)
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.append(note)
        }
        notes.sort {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func removeListRow(id: NoteID) {
        notes.removeAll { $0.id == id }
    }

    private func restore(id: NoteID, body: String, selection: NSRange?) {
        guard let state = loaded[id] else { return }
        let currentBody = state.note.body
        let currentSelection = state.editor?.selectedRange()
        registerUndo(for: id, body: currentBody, selection: currentSelection)
        state.note.body = body
        state.note.revision &+= 1
        state.note.modifiedAt = .now
        state.isDirty = true
        if let editor = state.editor {
            replaceEditorContentsWithoutUndo(editor, with: body)
            if let selection { editor.setSelectedRange(selection) }
        }
        scheduleSave(id: id)
        changed()
    }

    private func replaceEditorContentsWithoutUndo(_ editor: NotesTextView, with body: String) {
        editor.undoManager?.disableUndoRegistration()
        editor.string = body
        editor.undoManager?.enableUndoRegistration()
    }

    private func changed() {
        changeCounter &+= 1
    }
}

@MainActor
private final class LoadedNote {
    var note: NoteDocument
    let undoManager = UndoManager()
    weak var editor: NotesTextView?
    var editorID = UUID()
    var lastSelection = NSRange(location: 0, length: 0)
    var isDirty = false
    var externalChangeDetected = false
    var externalVersion: NoteFileVersion?
    var titleDraft: String
    var isTitleEditing = false
    var saveError: String?
    var lastPersistedRevision: UInt64

    init(note: NoteDocument) {
        self.note = note
        self.titleDraft = note.title
        self.lastPersistedRevision = note.revision
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
