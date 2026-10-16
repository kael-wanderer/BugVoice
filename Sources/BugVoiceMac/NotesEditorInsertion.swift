import AppKit
import Foundation
import VoiceCore

@MainActor
public final class NotesTextView: NSTextView {
    public let editorID = UUID()
    weak var notesController: NotesController?
    var noteID: NoteID?

    public override var undoManager: UndoManager? {
        guard let noteID, let notesController else { return super.undoManager }
        return notesController.undoManager(for: noteID) ?? super.undoManager
    }

    /// ⌘Z and ⌘⇧Z go straight to the note's undo manager. The Edit menu's
    /// Undo does not reach this view's per-note manager.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard window?.firstResponder === self, event.charactersIgnoringModifiers?.lowercased() == "z",
              flags == .command || flags == [.command, .shift], let undoManager else {
            return super.performKeyEquivalent(with: event)
        }
        if flags.contains(.shift) {
            if undoManager.canRedo { undoManager.redo() }
        } else if undoManager.canUndo {
            undoManager.undo()
        }
        return true
    }
}

/// Insertion adapter bound to one captured note and selection for one run.
@MainActor
public final class NotesEditorInsertion: InsertionTarget, @unchecked Sendable {
    private let controller: NotesController
    private let capture: NotesDictationCapture

    public init(controller: NotesController, capture: NotesDictationCapture) {
        self.controller = controller
        self.capture = capture
    }

    public func insert(_ text: String) async -> InsertOutcome {
        switch await controller.insert(capture: capture, text: text) {
        case .inserted: .pasted
        case .noteDeleted: .notConsumed
        case .saveFailed: .failed
        }
    }

    public func copy(_ text: String) async {
        // Notes dictation has no clipboard fallback.
    }
}
