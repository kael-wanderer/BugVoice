import AppKit
import BugVoiceMac
import VoiceCore

/// Applies a toolbar or Transform edit to a note.
@MainActor
enum ScratchpadEditing {
    /// Through the text view when the note is on screen, so the edit is one
    /// undo step and the delegate saves it; otherwise straight to the note.
    static func apply(_ edit: MarkdownEdit, to id: NoteID, controller: NotesController) {
        let range = NSRange(location: edit.range.location, length: edit.range.length)
        if let editor = controller.attachedEditor(id: id), NSMaxRange(range) <= (editor.string as NSString).length {
            guard editor.shouldChangeText(in: range, replacementString: edit.replacement) else { return }
            editor.textStorage?.replaceCharacters(in: range, with: edit.replacement)
            editor.didChangeText()
            editor.setSelectedRange(NSRange(location: edit.selection.location, length: edit.selection.length))
            editor.scrollRangeToVisible(editor.selectedRange())
            return
        }
        guard let body = controller.note(id: id)?.body, NSMaxRange(range) <= (body as NSString).length else { return }
        controller.updateBody(id: id, body: edit.applied(to: body))
    }

    /// The editor's selection, or the saved one when the note is not on screen.
    static func selection(of id: NoteID, controller: NotesController) -> NotesTextRange {
        if let editor = controller.attachedEditor(id: id) {
            let range = editor.selectedRange()
            return NotesTextRange(location: range.location, length: range.length)
        }
        let length = ((controller.note(id: id)?.body ?? "") as NSString).length
        return NotesTextRange(location: length, length: 0)
    }
}
