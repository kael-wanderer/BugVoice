import BugVoiceMac
import Foundation
import Observation
import VoiceCore

/// The text an AI change or question works on, captured when it starts.
struct TransformInput: Equatable {
    let noteID: NoteID
    let range: NotesTextRange
    let text: String
    let revision: UInt64
    let isSelection: Bool

    var words: Int { NoteTransformPrompt.wordCount(text) }

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

/// A question's answer, shown above the AI bar.
struct AssistantReply: Equatable {
    let noteID: NoteID
    let message: String
    let text: String
}

/// The short notice after an AI change, with Undo.
struct AssistantNotice: Equatable {
    let noteID: NoteID
    let text: String
}

/// State of the AI bar: chips, Run again, the box, History. One request at a time.
@MainActor
@Observable
final class ScratchpadAssistant {
    enum Phase: Equatable {
        case idle
        case running(String)
        case failed(String)
    }

    var phase: Phase = .idle
    var scope: AskScope = .note(NoteID(rawValue: ""))
    var askStep: AskStep?
    var askResult: (question: String, outcome: AskOutcome, scope: AskScope, counts: (meetings: Int, notes: Int, dictations: Int))?
    var askHistory: [NoteChatTurn] = []
    var askError: String?
    var searchedCounts = (meetings: 0, notes: 0, dictations: 0)
    @ObservationIgnored private var askRunID: UUID?
    var message = ""
    var reply: AssistantReply?
    var notice: AssistantNotice?
    private(set) var lastChange: NoteAIChange?
    private(set) var history = NoteAIHistory()
    @ObservationIgnored private var conversation: [NoteChatTurn] = []
    @ObservationIgnored private var conversationNote: NoteID?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    var isBusy: Bool {
        if case .running = phase { return true }
        return false
    }

    func canRunAgain(noteID: NoteID, controller: NotesController) -> Bool {
        guard scope == .note(noteID), !isBusy, let lastChange, let revision = controller.note(id: noteID)?.revision else { return false }
        return lastChange.canRunAgain(noteID: noteID, revision: revision)
    }

    // MARK: Requests

    func run(_ transform: NoteTransform, input: TransformInput, model: AppModel) {
        guard scope == .note(input.noteID), start(input) else { return }
        askResult = nil
        askError = nil
        rewrite(transform, input: input, model: model, again: false)
    }

    func send(input: TransformInput, model: AppModel) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 1_000 else { return }
        if scope != .note(input.noteID) {
            sendAcross(text, model: model)
            return
        }
        guard start(input) else { return }
        askResult = nil
        askError = nil
        if conversationNote != input.noteID { resetConversation() }
        conversationNote = input.noteID
        message = ""
        reply = nil
        ask(text, input: input, history: conversation, model: model, again: false)
    }

    func changeScope(_ scope: AskScope) {
        guard self.scope != scope else { return }
        cancel()
        self.scope = scope
        askHistory = []
    }

    private func sendAcross(_ question: String, model: AppModel) {
        guard !isBusy else { return }
        guard model.canAskAcross else {
            askError = "Choose a Notes model in Settings to ask questions."
            return
        }
        let scope = scope, history = askHistory, runID = UUID()
        askRunID = runID
        askError = nil
        askStep = .understanding
        message = ""
        phase = .running("")
        task = Task {
            do {
                let outcome = try await model.askAcross(question: question, history: history, scope: scope) { [weak self] step in
                    Task { @MainActor in
                        guard let self, self.askRunID == runID else { return }
                        self.askStep = step
                        if case .searching(let meetings, let notes, let dictations) = step {
                            self.searchedCounts = (meetings, notes, dictations)
                        }
                    }
                }
                // Stop may arrive just after the model returns an outcome.
                guard !Task.isCancelled, askRunID == runID else { return }
                if case .failed(.tooSlow) = outcome {
                    askError = "Ask took too long. Try a smaller scope."
                } else {
                    askResult = (question, outcome, scope, searchedCounts)
                    if case .answered(let result, _) = outcome {
                        askHistory.append(NoteChatTurn(message: question, reply: result.answer))
                        askHistory = Array(askHistory.suffix(3))
                    }
                }
            } catch {
                guard !Task.isCancelled, askRunID == runID else { return }
            }
            guard askRunID == runID else { return }
            askRunID = nil
            askStep = nil
            phase = .idle
            task = nil
        }
    }

    /// The last change again, on the same original text, replacing its result.
    func runAgain(model: AppModel) {
        let controller = model.notesController
        guard let change = lastChange, canRunAgain(noteID: change.noteID, controller: controller),
              let revision = controller.note(id: change.noteID)?.revision else { return }
        let input = TransformInput(
            noteID: change.noteID, range: change.range, text: change.original, revision: revision, isSelection: true)
        guard start(input) else { return }
        switch change.kind {
        case .transform(let transform):
            rewrite(transform, input: input, model: model, again: true)
        case .instruction(let text):
            ask(text, input: input, history: Array(conversation.dropLast()), model: model, again: true)
        }
    }

    private func start(_ input: TransformInput) -> Bool {
        guard !isBusy else { return false }
        guard !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !NoteTransformPrompt.isTooLong(input.text) else {
            phase = .failed(ScratchpadAIError.tooLong.localizedDescription)
            return false
        }
        return true
    }

    private func rewrite(_ transform: NoteTransform, input: TransformInput, model: AppModel, again: Bool) {
        phase = .running("Working… \(transform.title) · \(input.words) words")
        let runID = UUID()
        askRunID = runID
        task = Task {
            do {
                let answer = try await model.askNotesModel { modelID, disableThinking in
                    NoteTransformPrompt.request(transform, text: input.text, modelID: modelID, disableThinking: disableThinking)
                }
                try Task.checkCancellation()
                guard askRunID == runID else { return }
                guard let result = NoteTransformPrompt.clean(answer.output) else { throw ScratchpadAIError.empty }
                apply(result, kind: .transform(transform), input: input, controller: model.notesController, again: again)
            } catch is CancellationError {
                guard askRunID == runID else { return }
                phase = .idle
            } catch {
                guard askRunID == runID else { return }
                phase = .failed(Self.message(for: error))
            }
            guard askRunID == runID else { return }
            askRunID = nil
            task = nil
        }
    }

    private func ask(_ text: String, input: TransformInput, history: [NoteChatTurn], model: AppModel, again: Bool) {
        phase = .running("Working… · \(input.words) words")
        let runID = UUID()
        askRunID = runID
        task = Task {
            do {
                let answer = try await model.askNotesModel { modelID, disableThinking in
                    NoteTransformPrompt.chatRequest(
                        message: text, text: input.text, history: history, modelID: modelID, disableThinking: disableThinking)
                }
                try Task.checkCancellation()
                guard askRunID == runID else { return }
                guard let cleaned = NoteTransformPrompt.clean(answer.output),
                      let parsed = NoteTransformPrompt.parseChatReply(cleaned) else { throw ScratchpadAIError.empty }
                if again, !conversation.isEmpty { conversation.removeLast() }
                switch parsed {
                case .change(let result):
                    conversation.append(NoteChatTurn(message: text, reply: "(changed the text)"))
                    apply(result, kind: .instruction(text), input: input, controller: model.notesController, again: again)
                case .answer(let result):
                    conversation.append(NoteChatTurn(message: text, reply: result))
                    reply = AssistantReply(noteID: input.noteID, message: text, text: result)
                    phase = .idle
                }
            } catch is CancellationError {
                guard askRunID == runID else { return }
                phase = .idle
            } catch {
                guard askRunID == runID else { return }
                phase = .failed(Self.message(for: error))
            }
            guard askRunID == runID else { return }
            askRunID = nil
            task = nil
        }
    }

    /// Replaces the input range with `result` as one undoable edit, unless
    /// the note changed while the request ran.
    private func apply(_ result: String, kind: NoteAIChangeKind, input: TransformInput, controller: NotesController, again: Bool) {
        guard let note = controller.note(id: input.noteID), note.revision == input.revision else {
            phase = .failed(staleMessage(kind))
            return
        }
        if !again {
            history.add(NoteAIHistoryEntry(title: kind.historyTitle, body: note.body, date: Date()), to: input.noteID)
        }
        let length = (result as NSString).length
        let edit = MarkdownEdit(
            range: input.range, replacement: result,
            selection: NotesTextRange(location: input.range.location, length: length))
        ScratchpadEditing.apply(edit, to: input.noteID, controller: controller)
        let revision = controller.note(id: input.noteID)?.revision ?? input.revision
        lastChange = NoteAIChange(
            noteID: input.noteID, kind: kind, original: input.text,
            range: NotesTextRange(location: input.range.location, length: length), revision: revision)
        phase = .idle
        show(AssistantNotice(noteID: input.noteID, text: kind.notice(words: NoteTransformPrompt.wordCount(result))))
    }

    private func staleMessage(_ kind: NoteAIChangeKind) -> String {
        switch kind {
        case .transform(let transform): "The note changed while \(transform.title) ran. Run it again."
        case .instruction: "The note changed while your message ran. Send it again."
        }
    }

    // MARK: Undo, History, reply

    /// Undo from the notice: the text view's undo when the note is on
    /// screen, otherwise the version before from History.
    func undo(controller: NotesController) {
        guard let notice else { return }
        if let undoManager = controller.undoManager(for: notice.noteID), undoManager.canUndo {
            undoManager.undo()
        } else if let before = history.entries(for: notice.noteID).first {
            controller.updateBody(id: notice.noteID, body: before.body)
        }
        lastChange = nil
        self.notice = nil
    }

    /// Puts a version back as one undoable edit.
    func restore(_ entry: NoteAIHistoryEntry, noteID: NoteID, controller: NotesController) {
        guard let body = controller.note(id: noteID)?.body else { return }
        let edit = MarkdownEdit(
            range: NotesTextRange(location: 0, length: (body as NSString).length), replacement: entry.body,
            selection: NotesTextRange(location: (entry.body as NSString).length, length: 0))
        ScratchpadEditing.apply(edit, to: noteID, controller: controller)
        lastChange = nil
    }

    func insertReply(controller: NotesController) {
        guard let reply, let body = controller.note(id: reply.noteID)?.body else { return }
        ScratchpadEditing.apply(
            MarkdownCommands.insertBelow(reply.text, in: body, after: (body as NSString).length),
            to: reply.noteID, controller: controller)
        self.reply = nil
    }

    func dismissReply() {
        reply = nil
        resetConversation()
    }

    /// After a tab switch: the box starts a new conversation.
    func noteChanged() {
        cancel()
        reply = nil
        notice = nil
        resetConversation()
    }

    func cancel() {
        task?.cancel()
        task = nil
        askRunID = nil
        askStep = nil
        phase = .idle
    }

    private func resetConversation() {
        conversation = []
        conversationNote = nil
    }

    private func show(_ notice: AssistantNotice) {
        self.notice = notice
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    static func message(for error: Error) -> String {
        if let error = error as? ScratchpadAIError { return error.localizedDescription }
        if error is TimeoutError { return "Notes model did not answer: it took too long." }
        return "Notes model did not answer: \(error.localizedDescription)"
    }
}
