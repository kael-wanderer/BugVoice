import AppKit
import Foundation
import VoiceCore

enum MeetingSummaryState: Equatable {
    /// Before the first refresh, or between refreshes.
    case waiting
    case refreshing
    /// No Meetings model is set.
    case noModel
    /// The last refresh failed; the next one retries.
    case failed
    /// Writing the final summary after Stop.
    case finalizing
}

/// The answer card above the dock.
struct MeetingAnswer: Equatable {
    enum State: Equatable {
        case loading
        case done
        case noModel
        case failed(String)
    }

    var question: String
    var text: String
    var state: State
}

/// Live summary, Ask anything and the final summary for the meeting window.
extension MeetingController {
    /// Runs a live summary refresh when one is due. Called once a second while recording.
    func refreshLiveSummaryIfDue() {
        guard summaryTask == nil, isRecording, let session else { return }
        // Dictation goes first on the same model.
        guard model.dictation?.isBusy != true, !model.isListening else { return }
        guard LiveSummaryPlanner.isDue(
            activeTime: elapsed,
            lastRefresh: lastRefreshActiveTime,
            interval: TimeInterval(model.settings.meetings.liveSummaryInterval),
            segments: segments,
            cutoff: liveSummaryCutoff,
            notesChanged: notes != notesAtLastRefresh
        ) else { return }
        let activeTime = elapsed
        let notes = notes
        let planned = LiveSummaryPlanner.request(
            previous: liveSummary,
            notes: notes,
            segments: segments,
            cutoff: liveSummaryCutoff,
            budget: MeetingTextBudget(settings: model.settings.meetings)
        )
        // A failed or skipped refresh waits for the next interval too.
        lastRefreshActiveTime = activeTime
        notesAtLastRefresh = notes
        summaryTask = Task { [weak self] in
            guard let self else { return }
            defer { self.summaryTask = nil }
            guard let textModel = await self.model.meetingTextModel() else {
                self.summaryState = .noModel
                return
            }
            self.summaryState = .refreshing
            do {
                let text = try await textModel.clean(planned.request).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    self.summaryState = .failed
                    return
                }
                let now = Date()
                try? await session.setLiveSummary(text, updatedAt: now, cutoff: planned.cutoff)
                self.liveSummary = text
                self.liveSummaryUpdatedAt = now
                self.liveSummaryCutoff = planned.cutoff
                self.summaryState = .waiting
            } catch {
                self.summaryState = .failed
            }
        }
    }

    /// Asks about this meeting; nil asks "What did I miss?".
    func ask(_ question: String?) {
        let text = question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? MeetingQuestion.missedQuestion
        guard !text.isEmpty else { return }
        askTask?.cancel()
        answer = MeetingAnswer(question: text, text: "", state: .loading)
        let budget = MeetingTextBudget(settings: model.settings.meetings)
        let request = question == nil
            ? MeetingQuestion.missedRequest(notes: notes, segments: segments, now: elapsed, budget: budget)
            : MeetingQuestion.request(question: text, notes: notes, segments: segments, budget: budget)
        askTask = Task { [weak self] in
            guard let self else { return }
            guard let textModel = await self.model.meetingTextModel() else {
                self.answer?.state = .noModel
                return
            }
            do {
                let reply = try await textModel.clean(request).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !Task.isCancelled, self.answer?.question == text else { return }
                self.answer = MeetingAnswer(question: text, text: reply, state: .done)
            } catch {
                guard !Task.isCancelled, self.answer?.question == text else { return }
                self.answer?.state = .failed("Could not get an answer: \(error.localizedDescription)")
            }
        }
    }

    func closeAnswer() {
        askTask?.cancel()
        askTask = nil
        answer = nil
    }

    /// Appends the question and answer to My notes.
    func addAnswerToNotes() {
        guard let answer, answer.state == .done else { return }
        let separator = notes.isEmpty || notes.hasSuffix("\n\n") ? "" : notes.hasSuffix("\n") ? "\n" : "\n\n"
        notes += separator + "**Q:** \(answer.question)\n\n\(answer.text)\n"
        closeAnswer()
    }

    /// After Stop: the summary from the whole transcript, following the notes.
    func generateFinalSummary() async {
        summaryTask?.cancel()
        await summaryTask?.value
        guard let id = shownMeetingID, !segments.isEmpty else { return }
        guard await model.meetingTextModel() != nil else {
            summaryState = .noModel
            return
        }
        summaryState = .finalizing
        do {
            finalSummary = try await model.generateMeetingText(id: id, kind: .summary) { _ in }
            summaryState = .waiting
        } catch {
            summaryState = .failed
        }
    }
}

/// Dictation into the meeting window's notes, at the cursor, when the hotkey is held.
@MainActor
final class MeetingNotesInsertion: InsertionTarget, @unchecked Sendable {
    private weak var editor: MeetingNotesTextView?

    init(editor: MeetingNotesTextView) {
        self.editor = editor
    }

    func insert(_ text: String) async -> InsertOutcome {
        guard let editor, editor.window != nil else { return .notConsumed }
        let range = editor.selectedRange()
        let spaced = NotesSpacing.fit(text, into: editor.string, at: range.location, replacing: range.length)
        editor.breakUndoCoalescing()
        guard editor.shouldChangeText(in: range, replacementString: spaced) else { return .failed }
        editor.textStorage?.replaceCharacters(in: range, with: spaced)
        editor.didChangeText()
        editor.setSelectedRange(NSRange(location: range.location + (spaced as NSString).length, length: 0))
        return .pasted
    }

    func copy(_ text: String) async {
        // Meeting notes dictation has no clipboard fallback.
    }
}
