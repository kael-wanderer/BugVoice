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
        #expect(await controller.insert(capture: capture, text: " dictated"))
        #expect(controller.note(id: created.id)?.body == "typed edit dictated")
        await controller.flush(id: created.id)
        let persisted = try await store.open(id: created.id)
        #expect(persisted.body == "typed edit dictated")
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
        #expect(await controller.insert(capture: capture, text: " dictation"))
        #expect(controller.undoManager(for: created.id) === manager)
        #expect(controller.note(id: created.id)?.body == "body dictation")

        manager?.undo()
        #expect(controller.note(id: created.id)?.body == "body")
        #expect(editor.string == "body")
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

        #expect(await controller.insert(capture: capture, text: " dictated"))
        #expect(!controller.isLoaded(id: created.id))
        #expect(try await store.open(id: created.id).body == "body dictated")
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
        #expect(await firstRun.insert(capture: capture, text: " dictation"))
        #expect(firstRun.undoManager(for: created.id)?.canUndo == true)

        let nextRun = NotesController(store: store)
        try await nextRun.load(id: created.id)
        #expect(nextRun.undoManager(for: created.id)?.canUndo == false)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BugVoiceNotesController-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
