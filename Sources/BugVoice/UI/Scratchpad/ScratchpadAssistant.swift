import BugVoiceMac
import Foundation
import Observation
import VoiceCore

/// The text a Transform or Ask works on, captured when it starts.
struct TransformInput: Equatable {
    let noteID: NoteID
    let range: NotesTextRange
    let text: String
    let revision: UInt64
    let isSelection: Bool

    var words: Int { NoteTransformPrompt.wordCount(text) }
    var header: String { "\(isSelection ? "Selection" : "Whole note") · \(words) words" }

    /// The selection, or the whole body when nothing is selected.
    @MainActor
    static func capture(noteID: NoteID, controller: NotesController, useSelection: Bool) -> TransformInput? {
        guard let note = controller.note(id: noteID) else { return nil }
        let body = note.body as NSString
        let selection = useSelection ? ScratchpadEditing.selection(of: noteID, controller: controller) : NotesTextRange(location: 0, length: 0)
        let isSelection = selection.length > 0 && selection.isValid(inUTF16Length: body.length)
        let range = isSelection ? selection : NotesTextRange(location: 0, length: body.length)
        return TransformInput(
            noteID: noteID, range: range,
            text: body.substring(with: NSRange(location: range.location, length: range.length)),
            revision: note.revision, isSelection: isSelection)
    }
}

struct TransformPreview: Equatable {
    let title: String
    let input: TransformInput
    let result: String
    let modelName: String
    let seconds: Int
}

/// State of the Transform / Ask panel under the editor. One request at a time.
@MainActor
@Observable
final class ScratchpadAssistant {
    enum Phase: Equatable {
        case idle
        case running(String)
        case preview(TransformPreview)
        case ask(TransformInput)
        case failed(String)
    }

    var phase: Phase = .idle
    var question = ""
    var answer: String?
    var isAsking = false
    @ObservationIgnored private var task: Task<Void, Never>?

    var isBusy: Bool {
        if case .running = phase { return true }
        return isAsking
    }

    func run(_ transform: NoteTransform, input: TransformInput, model: AppModel) {
        guard !isBusy else { return }
        guard !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !NoteTransformPrompt.isTooLong(input.text) else {
            phase = .failed(ScratchpadAIError.tooLong.localizedDescription)
            return
        }
        phase = .running("Working… \(transform.title) · \(input.words) words")
        task = Task {
            do {
                let answer = try await model.askNotesModel { modelID, disableThinking in
                    NoteTransformPrompt.request(transform, text: input.text, modelID: modelID, disableThinking: disableThinking)
                }
                guard let result = NoteTransformPrompt.clean(answer.output) else { throw ScratchpadAIError.empty }
                phase = .preview(TransformPreview(
                    title: transform.title, input: input, result: result,
                    modelName: answer.modelName, seconds: answer.seconds))
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(Self.message(for: error))
            }
            task = nil
        }
    }

    func startAsk(input: TransformInput) {
        guard !isBusy else { return }
        question = ""
        answer = nil
        phase = .ask(input)
    }

    func sendQuestion(model: AppModel) {
        guard case .ask(let input) = phase, !isAsking else { return }
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        guard !NoteTransformPrompt.isTooLong(input.text) else {
            phase = .failed(ScratchpadAIError.tooLong.localizedDescription)
            return
        }
        isAsking = true
        answer = nil
        task = Task {
            defer { isAsking = false; task = nil }
            do {
                let reply = try await model.askNotesModel { modelID, disableThinking in
                    NoteTransformPrompt.askRequest(question: question, note: input.text, modelID: modelID, disableThinking: disableThinking)
                }
                guard let text = NoteTransformPrompt.clean(reply.output) else { throw ScratchpadAIError.empty }
                answer = text
            } catch is CancellationError {
            } catch {
                phase = .failed(Self.message(for: error))
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isAsking = false
        phase = .idle
    }

    func close() {
        cancel()
        answer = nil
        question = ""
    }

    /// True when the note changed after the request was sent.
    func isStale(_ input: TransformInput, controller: NotesController) -> Bool {
        controller.note(id: input.noteID)?.revision != input.revision
    }

    func replace(_ preview: TransformPreview, controller: NotesController) {
        guard !isStale(preview.input, controller: controller) else { return }
        let edit = MarkdownEdit(
            range: preview.input.range, replacement: preview.result,
            selection: NotesTextRange(location: preview.input.range.location, length: (preview.result as NSString).length))
        ScratchpadEditing.apply(edit, to: preview.input.noteID, controller: controller)
        close()
    }

    func insertBelow(_ preview: TransformPreview, controller: NotesController) {
        guard !isStale(preview.input, controller: controller), let body = controller.note(id: preview.input.noteID)?.body else { return }
        let end = preview.input.range.location + preview.input.range.length
        ScratchpadEditing.apply(MarkdownCommands.insertBelow(preview.result, in: body, after: end), to: preview.input.noteID, controller: controller)
        close()
    }

    /// Ask → Insert below: at the end of the note.
    func insertAnswer(into id: NoteID, controller: NotesController) {
        guard let answer, let body = controller.note(id: id)?.body else { return }
        ScratchpadEditing.apply(MarkdownCommands.insertBelow(answer, in: body, after: (body as NSString).length), to: id, controller: controller)
        close()
    }

    static func message(for error: Error) -> String {
        if let error = error as? ScratchpadAIError { return error.localizedDescription }
        if error is TimeoutError { return "Notes model did not answer: it took too long." }
        return "Notes model did not answer: \(error.localizedDescription)"
    }
}
