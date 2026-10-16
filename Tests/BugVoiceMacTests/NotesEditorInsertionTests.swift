import AppKit
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

    @Test func commandZUndoesAndCommandShiftZRedoesInTheNotesUndoManager() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let created = try await store.create(title: "Undo", body: "body")
        let controller = NotesController(store: store)
        try await controller.load(id: created.id)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        let editor = NotesTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        window.contentView = editor
        controller.attachEditor(editor, to: created.id)
        window.makeFirstResponder(editor)
        let manager = try #require(controller.undoManager(for: created.id))
        var value = "after"
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: editor) { editor in
            value = "before"
            manager.registerUndo(withTarget: editor) { _ in value = "after" }
        }
        manager.endUndoGrouping()

        #expect(editor.performKeyEquivalent(with: key("z", flags: .command, window: window)))
        #expect(value == "before")
        #expect(manager.canRedo)
        #expect(editor.performKeyEquivalent(with: key("z", flags: [.command, .shift], window: window)))
        #expect(value == "after")
        #expect(!editor.performKeyEquivalent(with: key("x", flags: .command, window: window)))
    }

    private func key(_ characters: String, flags: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 6
        )!
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BugVoiceNotesInsertion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
