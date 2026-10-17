import Foundation

/// Transcript lines as the meeting window's prompts show them: `[m:ss] You: text`.
public enum MeetingPromptLines {
    public static func line(_ segment: MeetingSegment) -> String {
        let seconds = max(0, Int(segment.start))
        return String(format: "[%d:%02d] ", seconds / 60, seconds % 60) + "\(segment.speaker): \(segment.text)"
    }

    /// The newest lines that fit `maxCharacters`, oldest first.
    static func newest(_ segments: [MeetingSegment], maxCharacters: Int) -> [MeetingSegment] {
        var kept: [MeetingSegment] = []
        var size = 0
        for segment in segments.reversed() {
            let length = line(segment).count + 1
            if size + length > maxCharacters { break }
            kept.append(segment)
            size += length
        }
        return kept.reversed()
    }
}

/// When the meeting window refreshes its running summary, and what it sends.
public enum LiveSummaryPlanner {
    /// Active (unpaused) meeting time before the first refresh, and between refreshes.
    public static let interval: TimeInterval = 180
    /// Notes longer than this are cut before they go into a request.
    public static let maxNotesCharacters = 4_000

    public static let systemPrompt = """
    You keep a running summary of a meeting that is still going on. You get the previous summary, \
    the user's own notes and the transcript lines spoken since the previous summary. Return the whole \
    updated summary as short Markdown bullets: what was discussed, decisions, and open questions. When the \
    notes have headings, use the same headings in the same order. Use only facts from the transcript and \
    the notes. Write in the language of the transcript. Return only the summary.
    """

    /// Whether a refresh should run now.
    /// - Parameters:
    ///   - activeTime: meeting time so far, pauses excluded.
    ///   - lastRefresh: `activeTime` at the last refresh, nil before the first.
    ///   - cutoff: meeting time up to which lines are already in the summary.
    public static func isDue(
        activeTime: TimeInterval,
        lastRefresh: TimeInterval?,
        segments: [MeetingSegment],
        cutoff: TimeInterval,
        notesChanged: Bool
    ) -> Bool {
        guard activeTime >= interval, !segments.isEmpty else { return false }
        guard let lastRefresh else { return true }
        guard activeTime - lastRefresh >= interval else { return false }
        return notesChanged || segments.contains { $0.end > cutoff }
    }

    /// The request for the next refresh and the cutoff to save with its result.
    /// New lines that do not fit the budget are dropped oldest first; the cutoff
    /// then covers the lines that went in.
    public static func request(
        previous: String?,
        notes: String,
        segments: [MeetingSegment],
        cutoff: TimeInterval,
        budget: MeetingTextBudget
    ) -> (request: CleanupRequest, cutoff: TimeInterval) {
        let notesText = String(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNotesCharacters))
        let previousText = previous?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fixed = notesText.count + previousText.count + 200
        let room = max(0, budget.inputTokens * 3 - fixed)
        let fresh = segments.filter { $0.end > cutoff }.sorted { $0.start < $1.start }
        let kept = MeetingPromptLines.newest(fresh, maxCharacters: room)
        let newCutoff = max(cutoff, fresh.map(\.end).max() ?? cutoff)
        let user = """
        Previous summary:
        \(previousText.isEmpty ? "None yet" : previousText)

        My notes:
        \(notesText.isEmpty ? "None" : notesText)

        New transcript lines:
        \(kept.isEmpty ? "None" : kept.map(MeetingPromptLines.line).joined(separator: "\n"))
        """
        return (CleanupRequest(system: systemPrompt, user: user, maxTokens: budget.outputTokens, disableThinking: true), newCutoff)
    }
}

/// Questions about the meeting that is being recorded.
public enum MeetingQuestion {
    public static let missedWindow: TimeInterval = 300
    public static let missedQuestion = "What was said in the last 5 minutes?"

    public static let systemPrompt = """
    Answer the user's question about a meeting that is still going on, using only the transcript lines \
    and the user's notes below. When the answer is not there, say that it was not said in the meeting so \
    far. Cite times as [m:ss]. Keep the answer short. Write in the language of the question.
    """

    /// - Parameter since: when set, only lines that end after this meeting time go in.
    public static func request(
        question: String,
        notes: String,
        segments: [MeetingSegment],
        since: TimeInterval? = nil,
        budget: MeetingTextBudget
    ) -> CleanupRequest {
        let notesText = String(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(LiveSummaryPlanner.maxNotesCharacters))
        let lines = segments.filter { since == nil || $0.end > since! }.sorted { $0.start < $1.start }
        let room = max(0, budget.inputTokens * 3 - notesText.count - question.count - 200)
        let kept = MeetingPromptLines.newest(lines, maxCharacters: room)
        let user = """
        Transcript so far:
        \(kept.isEmpty ? "No lines yet." : kept.map(MeetingPromptLines.line).joined(separator: "\n"))

        My notes:
        \(notesText.isEmpty ? "None" : notesText)

        Question: \(question)
        """
        return CleanupRequest(system: systemPrompt, user: user, maxTokens: min(1_024, budget.outputTokens), disableThinking: true)
    }

    /// "What did I miss?": the last 5 minutes of meeting time before `now`.
    public static func missedRequest(
        notes: String,
        segments: [MeetingSegment],
        now: TimeInterval,
        budget: MeetingTextBudget
    ) -> CleanupRequest {
        request(question: missedQuestion, notes: notes, segments: segments, since: max(0, now - missedWindow), budget: budget)
    }
}
