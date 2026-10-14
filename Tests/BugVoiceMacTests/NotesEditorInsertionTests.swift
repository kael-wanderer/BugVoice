import Foundation
import Testing
@testable import BugVoiceMac
import VoiceCore

@MainActor
struct NotesEditorInsertionTests {
    @Test func targetRemainsBoundToCapturedNoteAndInsertsWithoutPasteboard() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let capturedNote = try await store.create(title: "Captured", body: "body")
        let otherNote = try await store.create(title: "Other", body: "other")
        let controller = NotesController(store: store)
        try await controller.load(id: capturedNote.id)
        try await controller.load(id: otherNote.id)
        let capture = NotesDictationCapture(
            noteID: capturedNote.id,
            editorID: UUID(),
            selection: NotesTextRange(location: 4, length: 0),
            bodyUTF16Length: 4,
            bodyRevision: 0
        )
        let target = NotesEditorInsertion(controller: controller, capture: capture)

        let result = await target.insert(" dictated")
        #expect(result == .pasted)
        #expect(controller.note(id: capturedNote.id)?.body == "body dictated")
        #expect(controller.note(id: otherNote.id)?.body == "other")
    }

    @Test func deletedCapturedNoteReturnsNotConsumedWithoutChoosingAnotherNote() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let capturedNote = try await store.create(title: "Gone", body: "body")
        let controller = NotesController(store: store)
        try await controller.load(id: capturedNote.id)
        let capture = NotesDictationCapture(
            noteID: capturedNote.id,
            editorID: UUID(),
            selection: NotesTextRange(location: 4, length: 0),
            bodyUTF16Length: 4,
            bodyRevision: 0
        )
        let target = NotesEditorInsertion(controller: controller, capture: capture)
        try await store.delete(id: capturedNote.id, confirmed: true)

        #expect(await target.insert("dictation") == .notConsumed)
        #expect(try await store.list().isEmpty)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BugVoiceNotesInsertion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
