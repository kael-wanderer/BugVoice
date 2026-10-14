import AppKit
import Foundation
import VoiceCore

@MainActor
public final class NotesController {
    private let store: NotesStore
    private var loaded: [NoteID: LoadedNote] = [:]
    private var saveTasks: [NoteID: Task<Void, Never>] = [:]
    private var saveTokens: [NoteID: UUID] = [:]

    public init(store: NotesStore) {
        self.store = store
    }

    public func load(id: NoteID) async throws {
        if loaded[id] != nil { return }
        let note = try await store.open(id: id)
        loaded[id] = LoadedNote(note: note)
    }

    public func note(id: NoteID) -> NoteDocument? {
        loaded[id]?.note
    }

    public func isLoaded(id: NoteID) -> Bool {
        loaded[id] != nil
    }

    public func undoManager(for id: NoteID) -> UndoManager? {
        loaded[id]?.undoManager
    }

    public func attachEditor(_ editor: NotesTextView?, to id: NoteID) {
        guard let state = loaded[id] else { return }
        state.editor = editor
        editor?.notesController = self
        editor?.noteID = id
        editor?.allowsUndo = true
        if let editor, editor.string != state.note.body { editor.string = state.note.body }
    }

    /// The NSTextView delegate calls this after ordinary user edits. The
    /// buffer is authoritative, and each change rearms the 500 ms save.
    public func updateBody(id: NoteID, body: String) {
        guard let state = loaded[id], state.note.body != body else { return }
        state.note.body = body
        state.note.revision &+= 1
        state.note.modifiedAt = .now
        state.isDirty = true
        scheduleSave(id: id)
    }

    /// Inserts into the captured note, regardless of current focus or selected
    /// note. The visible editor is updated from the same authoritative buffer.
    public func insert(capture: NotesDictationCapture, text: String) async -> Bool {
        guard loaded[capture.noteID] != nil else {
            do {
                let outcome = try await store.applyInsertion(capture: capture, text: text)
                return outcome != .deleted
            } catch {
                return false
            }
        }

        await refresh(id: capture.noteID, trigger: .beforeSave)
        guard let latestState = loaded[capture.noteID] else { return false }
        let bodyLength = (latestState.note.body as NSString).length
        guard let plan = NotesInsertionPlan.make(
            capture: capture,
            noteExists: true,
            currentRevision: latestState.note.revision,
            currentBodyUTF16Length: bodyLength,
            editorVisible: latestState.editor?.window != nil
        ) else { return false }

        let range: NSRange
        switch plan.location {
        case .selection(let selection):
            range = NSRange(location: selection.location, length: selection.length)
        case .bodyEnd(let location):
            range = NSRange(location: location, length: 0)
        }
        let oldBody = latestState.note.body
        let oldSelection = latestState.editor?.selectedRange()
        registerUndo(for: capture.noteID, body: oldBody, selection: oldSelection)
        latestState.note.body = (oldBody as NSString).replacingCharacters(in: range, with: text)
        latestState.note.revision &+= 1
        latestState.note.modifiedAt = .now
        latestState.isDirty = true
        if let editor = latestState.editor {
            editor.string = latestState.note.body
            editor.setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
        }
        scheduleSave(id: capture.noteID)
        return true
    }

    public func flush(id: NoteID) async {
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        saveTokens[id] = nil
        await save(id: id, taskToken: nil)
    }

    public func flushAll() async {
        for id in loaded.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            await flush(id: id)
        }
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
                isDirty: state.isDirty
            )
            switch result {
            case .unchanged:
                state.externalChangeDetected = false
            case .reloaded(let note, let version):
                var reloaded = note
                reloaded.fileVersion = version
                state.note = reloaded
                state.lastPersistedRevision = reloaded.revision
                state.isDirty = false
                state.externalChangeDetected = false
                state.editor?.string = reloaded.body
            case .conflict:
                state.externalChangeDetected = true
            case .saved, .stale, .deleted:
                break
            }
        } catch NotesStoreError.missing {
            loaded[id] = nil
            saveTasks[id]?.cancel()
            saveTasks[id] = nil
        } catch {
            state.externalChangeDetected = true
        }
    }

    public func externalChangeMessage(for id: NoteID) -> String? {
        loaded[id]?.externalChangeDetected == true ? "Changed outside BugVoice" : nil
    }

    private func scheduleSave(id: NoteID) {
        saveTasks[id]?.cancel()
        let token = UUID()
        saveTokens[id] = token
        saveTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NotesAutosavePolicy.bodyDebounceInterval))
            guard !Task.isCancelled, let self, self.saveTokens[id] == token else { return }
            await self.save(id: id, taskToken: token)
        }
    }

    private func save(id: NoteID, taskToken: UUID?) async {
        guard let state = loaded[id], state.isDirty else {
            clearSaveTask(id: id, matching: taskToken)
            return
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
                if state.note.revision == saved.revision {
                    state.isDirty = false
                    state.externalChangeDetected = false
                }
            case .reloaded(let note, _):
                if !state.isDirty {
                    state.note = note
                    state.lastPersistedRevision = note.revision
                    state.editor?.string = note.body
                }
            case .conflict:
                state.externalChangeDetected = true
            case .stale:
                break
            case .unchanged, .deleted:
                break
            }
        } catch NotesStoreError.missing {
            loaded[id] = nil
        } catch {
            // Keep the dirty buffer so the caller can report and retry the save.
        }
        clearSaveTask(id: id, matching: taskToken)
    }

    private func registerUndo(for id: NoteID, body: String, selection: NSRange?) {
        guard let manager = loaded[id]?.undoManager else { return }
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: self) { controller in
            controller.restore(id: id, body: body, selection: selection)
        }
        manager.setActionName("Dictation")
        manager.endUndoGrouping()
    }

    private func clearSaveTask(id: NoteID, matching token: UUID?) {
        guard let token else { return }
        guard saveTokens[id] == token else { return }
        saveTokens[id] = nil
        saveTasks[id] = nil
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
            editor.string = body
            if let selection { editor.setSelectedRange(selection) }
        }
        scheduleSave(id: id)
    }
}

@MainActor
private final class LoadedNote {
    var note: NoteDocument
    let undoManager = UndoManager()
    weak var editor: NotesTextView?
    var isDirty = false
    var externalChangeDetected = false
    var lastPersistedRevision: UInt64

    init(note: NoteDocument) {
        self.note = note
        self.lastPersistedRevision = note.revision
    }
}
