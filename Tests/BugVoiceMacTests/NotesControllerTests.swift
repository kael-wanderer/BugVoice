import AppKit
import Foundation
import Testing
@testable import BugVoiceMac
import VoiceCore

@MainActor
struct NotesControllerTests {
    @Test func insertionWhileBodySaveIsPendingKeepsTypedEditAndDictation() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Buffer", body: "start")
        let controller = NotesController(store: store)
        try await controller.load(id: created.id)
        let capture = NotesDictationCapture(
            noteID: created.id,
            editorID: UUID(),
            selection: NotesTextRange(location: 5, length: 0),
            bodyUTF16Length: 5,
            bodyRevision: 0
        )

        controller.updateBody(id: created.id, body: "typed edit")
        #expect(controller.hasPendingSave(id: created.id))
        #expect(await controller.insert(capture: capture, text: " dictated") == .inserted)
        #expect(controller.note(id: created.id)?.body == "typed edit dictated")
        await controller.flush(id: created.id)
        let persisted = try await store.open(id: created.id)
        #expect(persisted.body == "typed edit dictated")
    }

    @Test func secondDictationIsSeparatedFromThePreviousWord() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Spacing", body: "more feature")
        let controller = NotesController(store: store)
        try await controller.load(id: created.id)
        let capture = NotesDictationCapture(
            noteID: created.id,
            editorID: UUID(),
            selection: NotesTextRange(location: 12, length: 0),
            bodyUTF16Length: 12,
            bodyRevision: 0
        )

        #expect(await controller.insert(capture: capture, text: "Hello, how are you?") == .inserted)
        #expect(controller.note(id: created.id)?.body == "more feature Hello, how are you?")
    }

    @Test func ownSaveUpdatesKnownVersionWithoutExternalChangeWarning() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Version")
        let controller = NotesController(store: store)
        try await controller.load(id: created.id)
        controller.updateBody(id: created.id, body: "owned edit")
        await controller.flush(id: created.id)

        await controller.refresh(id: created.id, trigger: .selection)
        #expect(controller.externalChangeMessage(for: created.id) == nil)
        #expect(controller.note(id: created.id)?.body == "owned edit")
    }

    @Test func offscreenInsertionUsesPerNoteUndoManagerAndSurvivesEditorReopen() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Undo", body: "body")
        let controller = NotesController(store: store)
        try await controller.load(id: created.id)
        let manager = controller.undoManager(for: created.id)
        let editor = NotesTextView(frame: .zero)
        controller.attachEditor(editor, to: created.id)
        #expect(editor.undoManager === manager)
        let capture = NotesDictationCapture(
            noteID: created.id,
            editorID: UUID(),
            selection: NotesTextRange(location: 4, length: 0),
            bodyUTF16Length: 4,
            bodyRevision: 0
        )
        controller.detachEditor(editor, from: created.id)
        #expect(await controller.insert(capture: capture, text: " dictation") == .inserted)
        #expect(controller.undoManager(for: created.id) === manager)
        #expect(controller.note(id: created.id)?.body == "body dictation")

        let reopenedEditor = NotesTextView(frame: .zero)
        controller.attachEditor(reopenedEditor, to: created.id)
        manager?.undo()
        #expect(controller.note(id: created.id)?.body == "body")
        #expect(reopenedEditor.string == "body")
        #expect(manager?.canUndo == false)
    }

    @Test func unloadedNoteInsertionUsesStoreDirectPath() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Unloaded", body: "body")
        let controller = NotesController(store: store)
        let capture = NotesDictationCapture(
            noteID: created.id,
            editorID: UUID(),
            selection: NotesTextRange(location: 4, length: 0),
            bodyUTF16Length: 4,
            bodyRevision: 0
        )

        #expect(await controller.insert(capture: capture, text: " dictated") == .inserted)
        #expect(!controller.isLoaded(id: created.id))
        #expect(try await store.open(id: created.id).body == "body dictated")
    }

    @Test func unloadedInsertionSaveFailureRetainsDictationForCopy() async throws {
        let root = try directory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Read only", body: "body")
        let controller = NotesController(store: store)
        let capture = NotesDictationCapture(
            noteID: created.id,
            editorID: UUID(),
            selection: NotesTextRange(location: 4, length: 0),
            bodyUTF16Length: 4,
            bodyRevision: 0
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)

        let result = await controller.insert(capture: capture, text: " dictated")
        #expect(result == .saveFailed)
        let recovery = try #require(controller.insertionRecoveries.last)
        #expect(recovery.text == " dictated")
        #expect(recovery.noteID == created.id)
        #expect(!controller.isLoaded(id: created.id))
    }

    @Test func saveUpdatesItsListRowWithoutRescanningTheNotesDirectory() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Loaded", body: "original")
        let controller = NotesController(store: store)
        await controller.reloadList()
        try await controller.load(id: created.id)
        try Data("# External\n\nexternal".utf8).write(to: root.appendingPathComponent("external.md"))

        controller.updateBody(id: created.id, body: "saved locally")
        #expect(await controller.flush(id: created.id))
        #expect(controller.notes.count == 1)
        #expect(controller.notes.first?.id == created.id)
        #expect(controller.notes.first?.body == "saved locally")
    }

    @Test func routeCaptureRequiresBugVoiceNotesPageAndMatchingFirstResponder() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Route", body: "body")
        let controller = NotesController(store: store)
        try await controller.select(id: created.id)
        let editor = NotesTextView(frame: .zero)
        controller.attachEditor(editor, to: created.id)

        let valid = controller.captureAtStart(
            bugVoiceIsFrontmost: true,
            notesPageIsSelected: true,
            firstResponderEditorID: editor.editorID
        )
        #expect(valid?.noteID == created.id)
        #expect(valid?.selection == NotesTextRange(location: 4, length: 0))
        #expect(controller.captureAtStart(
            bugVoiceIsFrontmost: false,
            notesPageIsSelected: true,
            firstResponderEditorID: editor.editorID
        ) == nil)
        #expect(controller.captureAtStart(
            bugVoiceIsFrontmost: true,
            notesPageIsSelected: false,
            firstResponderEditorID: editor.editorID
        ) == nil)
        #expect(controller.captureAtStart(
            bugVoiceIsFrontmost: true,
            notesPageIsSelected: true,
            firstResponderEditorID: UUID()
        ) == nil)
        // The immutable start capture remains bound after focus moves.
        #expect(valid?.noteID == created.id)
    }

    @Test func notesMicUsesLastEditorSelectionAfterFocusMovesToAnotherControl() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Mic", body: "hello world")
        let controller = NotesController(store: store)
        try await controller.select(id: created.id)
        let editor = NotesTextView(frame: .zero)
        controller.attachEditor(editor, to: created.id)
        editor.setSelectedRange(NSRange(location: 6, length: 5))
        controller.updateSelection(id: created.id, range: NSRange(location: 6, length: 5))

        let capture = try #require(controller.captureSelectedNoteForMic())
        #expect(capture.noteID == created.id)
        #expect(capture.selection == NotesTextRange(location: 6, length: 5))
        #expect(controller.captureAtStart(
            bugVoiceIsFrontmost: true,
            notesPageIsSelected: true,
            firstResponderEditorID: nil
        ) == nil)
        #expect(controller.captureSelectedNoteForMic()?.selection == capture.selection)
    }

    @Test func textViewTypingAndDictationUndoRemainSafeAcrossExternalReloadWithoutWindow() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Undo", body: "hello")
        let controller = NotesController(store: store)
        try await controller.select(id: created.id)
        let editor = NotesTextView(frame: .zero)
        #expect(editor.textStorage != nil)
        controller.attachEditor(editor, to: created.id)
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        editor.insertText(" typed", replacementRange: NSRange(location: 5, length: 0))
        controller.updateBody(id: created.id, body: editor.string)

        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        let capture = try #require(controller.captureAtStart(
            bugVoiceIsFrontmost: true,
            notesPageIsSelected: true,
            firstResponderEditorID: editor.editorID
        ))
        #expect(await controller.insert(capture: capture, text: " dictated") == .inserted)
        #expect(editor.string == "hello typed dictated")

        let undo = try #require(controller.undoManager(for: created.id))
        undo.undo()
        controller.updateBody(id: created.id, body: editor.string)
        undo.undo()
        controller.updateBody(id: created.id, body: editor.string)
        #expect(editor.string == "hello")
        #expect(controller.note(id: created.id)?.body == "hello")
        #expect(await controller.flush(id: created.id))

        try Data("# Undo\n\nexternal replacement".utf8).write(to: root.appendingPathComponent("undo.md"))
        await controller.refresh(id: created.id, trigger: .appActivation)
        undo.undo()
        #expect(editor.string == "external replacement")
        #expect(controller.note(id: created.id)?.body == "external replacement")
    }

    @Test func externalBodyChangeAfterCaptureMovesInsertionToLatestBodyEnd() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "External", body: "body")
        let controller = NotesController(store: store)
        try await controller.select(id: created.id)
        let editor = NotesTextView(frame: .zero)
        controller.attachEditor(editor, to: created.id)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        let capture = controller.captureAtStart(
            bugVoiceIsFrontmost: true,
            notesPageIsSelected: true,
            firstResponderEditorID: editor.editorID
        )!

        try Data("# External\n\nnew external body".utf8).write(to: root.appendingPathComponent("external.md"))
        await controller.refresh(id: created.id, trigger: .appActivation)
        #expect(controller.note(id: created.id)?.revision == capture.bodyRevision + 1)
        #expect(await controller.insert(capture: capture, text: " dictated") == .inserted)
        #expect(controller.note(id: created.id)?.body == "new external body dictated")
    }

    @Test func bodySaveUsesCommittedTitleUntilTitleEditingEndsThenRenames() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Old title", body: "body")
        let controller = NotesController(store: store)
        try await controller.load(id: created.id)
        controller.updateTitleDraft(id: created.id, title: "New title")
        controller.updateBody(id: created.id, body: "edited body")

        // Wait for the autosave; a fixed sleep raced it when the suite ran in parallel.
        let deadline = ContinuousClock.now + .seconds(3)
        while try await store.open(id: created.id).body != "edited body", ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(try await store.open(id: created.id).title == "Old title")
        #expect(try await store.open(id: created.id).body == "edited body")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("old-title.md").path))

        await controller.commitTitle(id: created.id, reason: .returnKey)
        #expect(try await store.open(id: created.id).title == "New title")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("new-title.md").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("old-title.md").path))
    }

    @Test func dirtyExternalChangeRequiresExplicitKeepMineOrReload() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Conflict", body: "original")
        let controller = NotesController(store: store)
        try await controller.load(id: created.id)
        controller.updateBody(id: created.id, body: "local edit")
        try Data("# Conflict\n\nexternal edit".utf8).write(to: root.appendingPathComponent("conflict.md"))
        await controller.refresh(id: created.id, trigger: .appActivation)
        #expect(controller.externalChangeMessage(for: created.id) == "Changed outside BugVoice")

        await controller.resolveExternalChange(id: created.id, keepMine: true)
        #expect(controller.externalChangeMessage(for: created.id) == nil)
        #expect(try await store.open(id: created.id).body == "local edit")
    }

    @Test func dirtyBufferCanBeRecoveredAfterExternalFileDeletion() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Missing", body: "original")
        let controller = NotesController(store: store)
        try await controller.load(id: created.id)
        controller.updateBody(id: created.id, body: "local recovery")
        try FileManager.default.removeItem(at: root.appendingPathComponent("missing.md"))
        await controller.refresh(id: created.id, trigger: .selection)
        #expect(controller.externalChangeMessage(for: created.id) == "Changed outside BugVoice")

        await controller.resolveExternalChange(id: created.id, keepMine: true)
        #expect(try await store.open(id: created.id).body == "local recovery")
    }

    @Test func undoHistoryIsPerControllerAndDoesNotSurviveRecreation() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Run", body: "body")
        let firstRun = NotesController(store: store)
        try await firstRun.load(id: created.id)
        let capture = NotesDictationCapture(
            noteID: created.id,
            editorID: UUID(),
            selection: NotesTextRange(location: 4, length: 0),
            bodyUTF16Length: 4,
            bodyRevision: 0
        )
        #expect(await firstRun.insert(capture: capture, text: " dictation") == .inserted)
        #expect(firstRun.undoManager(for: created.id)?.canUndo == true)

        let nextRun = NotesController(store: store)
        try await nextRun.load(id: created.id)
        #expect(nextRun.undoManager(for: created.id)?.canUndo == false)
    }

    @Test func labelsAreWrittenAsFrontMatterAndSurviveRename() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Plan", body: "body")
        let controller = NotesController(store: store)

        try await controller.setLabels(id: created.id, folderID: FolderID(rawValue: "f1"), tags: ["acme"])
        await controller.flush(id: created.id)
        let text = try String(contentsOf: root.appendingPathComponent("plan.md"), encoding: .utf8)
        #expect(text == "---\nfolder: f1\ntags: [acme]\n---\n# Plan\n\nbody")

        let note = try #require(controller.note(id: created.id))
        _ = try await store.rename(id: created.id, title: "Plan B", revision: note.revision, expectedVersion: note.fileVersion)
        let renamed = try String(contentsOf: root.appendingPathComponent("plan-b.md"), encoding: .utf8)
        #expect(renamed.hasPrefix("---\nfolder: f1\ntags: [acme]\n---\n# Plan B"))
    }

    @Test func pinIsSavedInFrontMatterAndListed() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Plan", body: "body")
        let controller = NotesController(store: store)
        await controller.reloadList()

        try await controller.setPinned(id: created.id, pinned: true)
        #expect(controller.notes.first { $0.id == created.id }?.frontMatter.pinned == true)
        await controller.flush(id: created.id)
        #expect(try String(contentsOf: root.appendingPathComponent("plan.md"), encoding: .utf8) == "---\npinned: true\n---\n# Plan\n\nbody")

        try await controller.setPinned(id: created.id, pinned: false)
        await controller.flush(id: created.id)
        #expect(try String(contentsOf: root.appendingPathComponent("plan.md"), encoding: .utf8) == "# Plan\n\nbody")
    }

    @Test func labelChangeKeepsUnsavedTyping() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Typing", body: "start")
        let controller = NotesController(store: store)
        try await controller.load(id: created.id)

        controller.updateBody(id: created.id, body: "start and more")
        try await controller.setLabels(id: created.id, folderID: nil, tags: ["todo"])
        await controller.flush(id: created.id)

        let persisted = try await store.open(id: created.id)
        #expect(persisted.body == "start and more")
        #expect(persisted.frontMatter.tags == ["todo"])
    }

    @Test func createPutsNoteInFolder() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = NotesController(store: NotesStore(directory: root))
        let note = try await controller.create(frontMatter: NoteFrontMatter(folderID: FolderID(rawValue: "f9")))
        let persisted = try await NotesStore(directory: root).list()
        #expect(persisted.first?.frontMatter.folderID == FolderID(rawValue: "f9"))
        #expect(note.frontMatter.folderID == FolderID(rawValue: "f9"))
    }

    @Test func createWithBodySavesTitleBodyAndLabels() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let controller = NotesController(store: store)
        let front = NoteFrontMatter(folderID: FolderID(rawValue: "f1"), tags: ["standup"])
        let note = try await controller.create(title: "Standup · Summary", body: "Shipped.", frontMatter: front)
        #expect(controller.selectedNoteID == note.id)
        let persisted = try await store.open(id: note.id)
        #expect(persisted.title == "Standup · Summary")
        #expect(persisted.body == "Shipped.")
        #expect(persisted.frontMatter.folderID == FolderID(rawValue: "f1"))
        #expect(persisted.frontMatter.tags == ["standup"])
    }

    @Test func clearSelectionSavesAndDeselects() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Close", body: "a")
        let controller = NotesController(store: store)
        try await controller.select(id: created.id)
        controller.updateBody(id: created.id, body: "a typed")
        await controller.clearSelection()
        #expect(controller.selectedNoteID == nil)
        #expect(!controller.hasPendingSave(id: created.id))
        #expect(try await store.open(id: created.id).body == "a typed")
    }

    @Test func createForAgentKeepsSelection() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let a = try await store.create(title: "A", body: "a")
        let controller = NotesController(store: store)
        try await controller.select(id: a.id)
        controller.updateBody(id: a.id, body: "a typing")
        let b = try await controller.createForAgent(
            title: "B", body: "from agent", frontMatter: NoteFrontMatter(tags: ["plan"]))
        #expect(controller.selectedNoteID == a.id)
        #expect(controller.notes.contains { $0.id == b.id })
        #expect(!controller.isLoaded(id: b.id))
        #expect(try await store.open(id: a.id).body == "a")
        #expect(controller.note(id: a.id)?.body == "a typing")
        let saved = try await store.open(id: b.id)
        #expect(saved.body == "from agent")
        #expect(saved.frontMatter.tags == ["plan"])
    }

    @Test func agentEditReplaceAndAppend() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Edit", body: "old")
        let controller = NotesController(store: store)
        try await controller.load(id: created.id)
        let replaced = try await controller.agentEdit(id: created.id, body: "x\n", append: false, title: nil, labels: nil)
        #expect(replaced.body == "x\n")
        let appended = try await controller.agentEdit(id: created.id, body: "y", append: true, title: nil, labels: nil)
        #expect(appended.body == "x\n\ny")
        #expect(try await store.open(id: created.id).body == "x\n\ny")
        #expect(controller.note(id: created.id)?.body == "x\n\ny")
        #expect(controller.saveMessage(for: created.id) == "Saved")
    }

    @Test func agentEditTitleAndLabels() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Plan", body: "b")
        let controller = NotesController(store: store)
        try await controller.load(id: created.id)
        let folder = FolderID(rawValue: "work")
        let edited = try await controller.agentEdit(
            id: created.id, body: "b2", append: false, title: "Plan v2", labels: (folderID: folder, tags: ["x"]))
        #expect(edited.title == "Plan v2")
        let saved = try await store.open(id: created.id)
        #expect(saved.title == "Plan v2")
        #expect(saved.body == "b2")
        #expect(saved.frontMatter.folderID == folder)
        #expect(saved.frontMatter.tags == ["x"])
    }

    @Test func agentEditRefusedWhileDirty() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Dirty", body: "saved")
        let controller = NotesController(store: store)
        try await controller.select(id: created.id)
        controller.updateBody(id: created.id, body: "typing")
        await #expect(throws: AgentEditRefusal.unsaved) {
            try await controller.agentEdit(id: created.id, body: "agent", append: false, title: nil, labels: nil)
        }
        #expect(try await store.open(id: created.id).body == "saved")
        #expect(controller.note(id: created.id)?.body == "typing")
        #expect(AgentEditRefusal.unsaved.message == "This note has unsaved changes in BugVoice. Try again after it saves.")
    }

    @Test func agentEditRefusedWhileTitleDraft() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Title", body: "b")
        let controller = NotesController(store: store)
        try await controller.load(id: created.id)
        controller.updateTitleDraft(id: created.id, title: "Title typing")
        await #expect(throws: AgentEditRefusal.unsaved) {
            try await controller.agentEdit(id: created.id, body: "agent", append: false, title: nil, labels: nil)
        }
        #expect(try await store.open(id: created.id).body == "b")
    }

    @Test func agentEditRefusedWhileDictating() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Dictate", body: "b")
        let controller = NotesController(store: store)
        try await controller.select(id: created.id)
        let editor = NotesTextView(frame: .zero)
        controller.attachEditor(editor, to: created.id)
        let capture = try #require(controller.captureAtStart(
            bugVoiceIsFrontmost: true, notesPageIsSelected: true, firstResponderEditorID: editor.editorID))
        await #expect(throws: AgentEditRefusal.dictating) {
            try await controller.agentEdit(id: created.id, body: "agent", append: false, title: nil, labels: nil)
        }
        #expect(AgentEditRefusal.dictating.message == "BugVoice is dictating into this note. Try again in a moment.")
        controller.releaseCapture(capture)
        let edited = try await controller.agentEdit(id: created.id, body: "agent", append: false, title: nil, labels: nil)
        #expect(edited.body == "agent")
        #expect(editor.string == "agent")
    }

    @Test func agentEditRefusedWhenDictationStartsDuringRefresh() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Race", body: "b")
        let controller = NotesController(store: store)
        try await controller.select(id: created.id)
        let editor = NotesTextView(frame: .zero)
        controller.attachEditor(editor, to: created.id)
        controller.agentEditWillMutate = {
            _ = controller.captureAtStart(
                bugVoiceIsFrontmost: true, notesPageIsSelected: true, firstResponderEditorID: editor.editorID)
        }
        await #expect(throws: AgentEditRefusal.dictating) {
            try await controller.agentEdit(id: created.id, body: "agent", append: false, title: nil, labels: nil)
        }
        #expect(controller.note(id: created.id)?.body == "b")
        #expect(editor.string == "b")
        #expect(try await store.open(id: created.id).body == "b")
    }

    @Test func agentEditUndoName() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Undo agent", body: "before")
        let controller = NotesController(store: store)
        try await controller.select(id: created.id)
        let editor = NotesTextView(frame: .zero)
        controller.attachEditor(editor, to: created.id)
        _ = try await controller.agentEdit(id: created.id, body: "after", append: false, title: nil, labels: nil)
        let undo = try #require(controller.undoManager(for: created.id))
        #expect(undo.undoActionName == "Agent edit")
        undo.undo()
        #expect(editor.string == "before")
        #expect(controller.note(id: created.id)?.body == "before")
    }

    @Test func agentEditUnloadedNote() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Cold", body: "line\n")
        let controller = NotesController(store: store)
        await controller.reloadList()
        let edited = try await controller.agentEdit(
            id: created.id, body: "more", append: true, title: "Cold 2", labels: (folderID: nil, tags: ["t"]))
        #expect(!controller.isLoaded(id: created.id))
        let saved = try await store.open(id: created.id)
        #expect(saved.body == "line\n\nmore")
        #expect(saved.title == "Cold 2")
        #expect(saved.frontMatter.tags == ["t"])
        #expect(edited.title == "Cold 2")
        #expect(controller.notes.first { $0.id == created.id }?.title == "Cold 2")
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BugVoiceNotesController-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
