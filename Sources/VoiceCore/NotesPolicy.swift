import Foundation

public struct NotesRouteConditions: Equatable, Sendable {
    public let bugVoiceIsFrontmost: Bool
    public let notesPageIsSelected: Bool
    public let selectedNoteID: NoteID?
    public let selectedEditorID: UUID?
    public let firstResponderEditorID: UUID?
    public let selection: NotesTextRange?
    public let bodyUTF16Length: Int
    public let noteRevision: UInt64
    public let editingBlocked: Bool

    public init(
        bugVoiceIsFrontmost: Bool,
        notesPageIsSelected: Bool,
        selectedNoteID: NoteID?,
        selectedEditorID: UUID?,
        firstResponderEditorID: UUID?,
        selection: NotesTextRange?,
        bodyUTF16Length: Int,
        noteRevision: UInt64,
        editingBlocked: Bool
    ) {
        self.bugVoiceIsFrontmost = bugVoiceIsFrontmost
        self.notesPageIsSelected = notesPageIsSelected
        self.selectedNoteID = selectedNoteID
        self.selectedEditorID = selectedEditorID
        self.firstResponderEditorID = firstResponderEditorID
        self.selection = selection
        self.bodyUTF16Length = bodyUTF16Length
        self.noteRevision = noteRevision
        self.editingBlocked = editingBlocked
    }
}

public struct NotesDictationCapture: Equatable, Sendable {
    public let noteID: NoteID
    public let editorID: UUID
    public let selection: NotesTextRange
    public let bodyUTF16Length: Int
    public let bodyRevision: UInt64

    public init(noteID: NoteID, editorID: UUID, selection: NotesTextRange, bodyUTF16Length: Int, bodyRevision: UInt64) {
        self.noteID = noteID
        self.editorID = editorID
        self.selection = selection
        self.bodyUTF16Length = bodyUTF16Length
        self.bodyRevision = bodyRevision
    }
}

public enum NotesRoutePolicy {
    /// Called once at run start. A returned capture stays bound to that note
    /// even if focus or the selected page later changes.
    public static func capture(atStart conditions: NotesRouteConditions) -> NotesDictationCapture? {
        guard conditions.bugVoiceIsFrontmost,
              conditions.notesPageIsSelected,
              !conditions.editingBlocked,
              let noteID = conditions.selectedNoteID,
              let editorID = conditions.selectedEditorID,
              conditions.firstResponderEditorID == editorID,
              let selection = conditions.selection,
              selection.isValid(inUTF16Length: conditions.bodyUTF16Length) else { return nil }

        return NotesDictationCapture(
            noteID: noteID,
            editorID: editorID,
            selection: selection,
            bodyUTF16Length: conditions.bodyUTF16Length,
            bodyRevision: conditions.noteRevision
        )
    }

    /// The Notes mic button already expresses an in-app Notes destination, so
    /// it does not depend on which control currently owns first responder.
    public static func captureForMic(
        selectedNoteID: NoteID?,
        editorID: UUID,
        lastSelection: NotesTextRange?,
        bodyUTF16Length: Int,
        noteRevision: UInt64,
        editingBlocked: Bool
    ) -> NotesDictationCapture? {
        guard let selectedNoteID,
              !editingBlocked,
              let lastSelection,
              lastSelection.isValid(inUTF16Length: bodyUTF16Length) else { return nil }
        return NotesDictationCapture(
            noteID: selectedNoteID,
            editorID: editorID,
            selection: lastSelection,
            bodyUTF16Length: bodyUTF16Length,
            bodyRevision: noteRevision
        )
    }
}

public enum NotesInsertionLocation: Equatable, Sendable {
    case selection(NotesTextRange)
    case bodyEnd(Int)
}

public struct NotesInsertionPlan: Equatable, Sendable {
    public let noteID: NoteID
    public let location: NotesInsertionLocation
    public let editorVisible: Bool

    public init(noteID: NoteID, location: NotesInsertionLocation, editorVisible: Bool) {
        self.noteID = noteID
        self.location = location
        self.editorVisible = editorVisible
    }

    /// Visibility chooses the view/buffer adapter only; it does not change
    /// which text range receives this run's result.
    public static func make(
        capture: NotesDictationCapture,
        noteExists: Bool,
        currentRevision: UInt64,
        currentBodyUTF16Length: Int,
        editorVisible: Bool
    ) -> NotesInsertionPlan? {
        guard noteExists else { return nil }
        let location: NotesInsertionLocation
        if currentRevision == capture.bodyRevision,
           capture.selection.isValid(inUTF16Length: currentBodyUTF16Length) {
            location = .selection(capture.selection)
        } else {
            location = .bodyEnd(currentBodyUTF16Length)
        }
        return NotesInsertionPlan(noteID: capture.noteID, location: location, editorVisible: editorVisible)
    }
}
