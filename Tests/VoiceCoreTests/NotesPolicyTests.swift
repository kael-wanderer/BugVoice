import Foundation
import Testing
@testable import VoiceCore

struct NotesPolicyTests {
    @Test func routeCapturesSelectedFirstResponderAtStart() throws {
        let noteID = NoteID()
        let editorID = UUID()
        let conditions = NotesRouteConditions(
            bugVoiceIsFrontmost: true,
            notesPageIsSelected: true,
            selectedNoteID: noteID,
            selectedEditorID: editorID,
            firstResponderEditorID: editorID,
            selection: NotesTextRange(location: 4, length: 2),
            bodyUTF16Length: 12,
            noteRevision: 7,
            editingBlocked: false
        )

        let capture = try #require(NotesRoutePolicy.capture(atStart: conditions))
        #expect(capture.noteID == noteID)
        #expect(capture.editorID == editorID)
        #expect(capture.selection == NotesTextRange(location: 4, length: 2))
        #expect(capture.bodyRevision == 7)
        #expect(capture.bodyUTF16Length == 12)
    }

    @Test func routeFallsBackToOrdinaryForEveryInvalidStartCondition() {
        let noteID = NoteID()
        let editorID = UUID()
        let valid = NotesRouteConditions(
            bugVoiceIsFrontmost: true,
            notesPageIsSelected: true,
            selectedNoteID: noteID,
            selectedEditorID: editorID,
            firstResponderEditorID: editorID,
            selection: NotesTextRange(location: 0, length: 0),
            bodyUTF16Length: 0,
            noteRevision: 1,
            editingBlocked: false
        )
        let invalid = [
            replacing(valid, bugVoiceIsFrontmost: false),
            replacing(valid, notesPageIsSelected: false),
            replacing(valid, selectedNoteID: .some(nil)),
            replacing(valid, firstResponderEditorID: UUID()),
            replacing(valid, selection: .some(nil)),
            replacing(valid, selection: NotesTextRange(location: 3, length: 0)),
            replacing(valid, editingBlocked: true)
        ]
        for conditions in invalid {
            #expect(NotesRoutePolicy.capture(atStart: conditions) == nil)
        }
    }

    @Test func micCaptureUsesSelectedNotesAndLastSelectionWithoutRequiringFirstResponder() throws {
        let noteID = NoteID()
        let editorID = UUID()
        let selection = NotesTextRange(location: 5, length: 3)
        let capture = try #require(NotesRoutePolicy.captureForMic(
            selectedNoteID: noteID,
            editorID: editorID,
            lastSelection: selection,
            bodyUTF16Length: 12,
            noteRevision: 9,
            editingBlocked: false
        ))
        #expect(capture.noteID == noteID)
        #expect(capture.editorID == editorID)
        #expect(capture.selection == selection)
        #expect(capture.bodyRevision == 9)
        #expect(NotesRoutePolicy.captureForMic(
            selectedNoteID: nil,
            editorID: editorID,
            lastSelection: selection,
            bodyUTF16Length: 12,
            noteRevision: 9,
            editingBlocked: false
        ) == nil)
    }

    @Test func unchangedNoteUsesCapturedSelectionEvenWhenEditorIsOffScreen() throws {
        let capture = capture(revision: 4, selection: NotesTextRange(location: 2, length: 3))
        let plan = try #require(NotesInsertionPlan.make(
            capture: capture,
            noteExists: true,
            currentRevision: 4,
            currentBodyUTF16Length: 20,
            editorVisible: false
        ))
        #expect(plan.location == .selection(NotesTextRange(location: 2, length: 3)))
        #expect(!plan.editorVisible)
    }

    @Test func changedNoteAppendsAtCurrentBodyEnd() throws {
        let capture = capture(revision: 4, selection: NotesTextRange(location: 2, length: 3))
        let plan = try #require(NotesInsertionPlan.make(
            capture: capture,
            noteExists: true,
            currentRevision: 5,
            currentBodyUTF16Length: 20,
            editorVisible: true
        ))
        #expect(plan.location == .bodyEnd(20))
        #expect(plan.editorVisible)
    }

    @Test func deletedNoteDiscardsInsteadOfChoosingAnotherTarget() {
        let capture = capture(revision: 4, selection: NotesTextRange(location: 2, length: 3))
        #expect(NotesInsertionPlan.make(
            capture: capture,
            noteExists: false,
            currentRevision: 4,
            currentBodyUTF16Length: 20,
            editorVisible: false
        ) == nil)
    }

    private func capture(revision: UInt64, selection: NotesTextRange) -> NotesDictationCapture {
        let noteID = NoteID()
        let editorID = UUID()
        return NotesDictationCapture(
            noteID: noteID,
            editorID: editorID,
            selection: selection,
            bodyUTF16Length: 20,
            bodyRevision: revision
        )
    }

    private func replacing(
        _ value: NotesRouteConditions,
        bugVoiceIsFrontmost: Bool? = nil,
        notesPageIsSelected: Bool? = nil,
        selectedNoteID: NoteID?? = nil,
        selectedEditorID: UUID?? = nil,
        firstResponderEditorID: UUID?? = nil,
        selection: NotesTextRange?? = nil,
        editingBlocked: Bool? = nil
    ) -> NotesRouteConditions {
        NotesRouteConditions(
            bugVoiceIsFrontmost: bugVoiceIsFrontmost ?? value.bugVoiceIsFrontmost,
            notesPageIsSelected: notesPageIsSelected ?? value.notesPageIsSelected,
            selectedNoteID: selectedNoteID ?? value.selectedNoteID,
            selectedEditorID: selectedEditorID ?? value.selectedEditorID,
            firstResponderEditorID: firstResponderEditorID ?? value.firstResponderEditorID,
            selection: selection ?? value.selection,
            bodyUTF16Length: value.bodyUTF16Length,
            noteRevision: value.noteRevision,
            editingBlocked: editingBlocked ?? value.editingBlocked
        )
    }
}
