import Foundation
import Testing
@testable import VoiceCore

struct MeetingLiveTextTests {
    private func line(_ start: Double, _ text: String, track: MeetingTrack = .system) -> MeetingSegment {
        MeetingSegment(start: start, end: start + 5, text: text, track: track, sourceChunkID: "c")
    }

    @Test func linesShowTimeAndSpeaker() {
        #expect(MeetingPromptLines.line(line(65, "Hello", track: .mic)) == "[1:05] You: Hello")
        #expect(MeetingPromptLines.line(line(5, "Hi")) == "[0:05] Others: Hi")
    }

    @Test func noRefreshBeforeThreeActiveMinutes() {
        #expect(!LiveSummaryPlanner.isDue(activeTime: 179, lastRefresh: nil, segments: [line(1, "a")], cutoff: 0, notesChanged: false))
        #expect(LiveSummaryPlanner.isDue(activeTime: 180, lastRefresh: nil, segments: [line(1, "a")], cutoff: 0, notesChanged: false))
    }

    @Test func noRefreshWithoutTranscript() {
        #expect(!LiveSummaryPlanner.isDue(activeTime: 600, lastRefresh: nil, segments: [], cutoff: 0, notesChanged: true))
    }

    @Test func nextRefreshEveryThreeMinutesOnlyWithSomethingNew() {
        let lines = [line(10, "a"), line(200, "b")]
        #expect(!LiveSummaryPlanner.isDue(activeTime: 300, lastRefresh: 180, segments: lines, cutoff: 15, notesChanged: false))
        #expect(LiveSummaryPlanner.isDue(activeTime: 360, lastRefresh: 180, segments: lines, cutoff: 15, notesChanged: false))
        #expect(!LiveSummaryPlanner.isDue(activeTime: 360, lastRefresh: 180, segments: lines, cutoff: 205, notesChanged: false))
        #expect(LiveSummaryPlanner.isDue(activeTime: 360, lastRefresh: 180, segments: lines, cutoff: 205, notesChanged: true))
    }

    @Test func requestHoldsPreviousSummaryNotesAndOnlyNewLines() {
        let (request, cutoff) = LiveSummaryPlanner.request(
            previous: "- Bot closes resets",
            notes: "## Bot results",
            segments: [line(10, "old line"), line(200, "new line")],
            cutoff: 15,
            budget: MeetingTextBudget()
        )
        #expect(request.system == LiveSummaryPlanner.systemPrompt)
        #expect(request.user.contains("Previous summary:\n- Bot closes resets"))
        #expect(request.user.contains("My notes:\n## Bot results"))
        #expect(request.user.contains("[3:20] Others: new line"))
        #expect(!request.user.contains("old line"))
        #expect(request.maxTokens == MeetingTextBudget().outputTokens)
        #expect(cutoff == 205)
    }

    @Test func firstRequestSaysNoneYet() {
        let (request, cutoff) = LiveSummaryPlanner.request(previous: nil, notes: "", segments: [], cutoff: 0, budget: MeetingTextBudget())
        #expect(request.user.contains("Previous summary:\nNone yet"))
        #expect(request.user.contains("My notes:\nNone"))
        #expect(cutoff == 0)
    }

    @Test func oversizeNewLinesKeepTheNewestAndCutoffCoversAll() {
        let long = String(repeating: "word ", count: 400)
        let lines = (0..<40).map { line(Double($0) * 10, "\($0) \(long)") }
        let budget = MeetingTextBudget(contextTokens: 4_096, outputTokens: 1_024)
        let (request, cutoff) = LiveSummaryPlanner.request(previous: nil, notes: "", segments: lines, cutoff: 0, budget: budget)
        #expect(request.user.contains("39 word"))
        #expect(!request.user.contains("[0:00] Others: 0 word"))
        #expect(request.user.count <= budget.inputTokens * 3)
        #expect(cutoff == 395)
    }

    @Test func questionHoldsNotesTranscriptAndQuestion() {
        let request = MeetingQuestion.request(
            question: "Who approves terminations?",
            notes: "- HR?",
            segments: [line(10, "HR approves")],
            budget: MeetingTextBudget()
        )
        #expect(request.system == MeetingQuestion.systemPrompt)
        #expect(request.user.contains("[0:10] Others: HR approves"))
        #expect(request.user.contains("My notes:\n- HR?"))
        #expect(request.user.hasSuffix("Question: Who approves terminations?"))
    }

    @Test func whatDidIMissKeepsOnlyTheLastFiveMinutes() {
        let request = MeetingQuestion.missedRequest(
            notes: "",
            segments: [line(10, "early"), line(400, "recent")],
            now: 600,
            budget: MeetingTextBudget()
        )
        #expect(request.user.contains("recent"))
        #expect(!request.user.contains("early"))
        #expect(request.user.hasSuffix("Question: What was said in the last 5 minutes?"))
    }

    @Test func questionWithNoLinesSaysSo() {
        let request = MeetingQuestion.request(question: "Anything?", notes: "", segments: [], budget: MeetingTextBudget())
        #expect(request.user.contains("Transcript so far:\nNo lines yet."))
    }
}
