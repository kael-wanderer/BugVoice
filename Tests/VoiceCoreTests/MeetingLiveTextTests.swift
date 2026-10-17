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

    @Test func noRefreshBeforeTheFirstInterval() {
        #expect(!LiveSummaryPlanner.isDue(activeTime: 179, lastRefresh: nil, interval: 180, segments: [line(1, "a")], cutoff: 0, notesChanged: false))
        #expect(LiveSummaryPlanner.isDue(activeTime: 180, lastRefresh: nil, interval: 180, segments: [line(1, "a")], cutoff: 0, notesChanged: false))
        #expect(!LiveSummaryPlanner.isDue(activeTime: 59, lastRefresh: nil, interval: 60, segments: [line(1, "a")], cutoff: 0, notesChanged: false))
        #expect(LiveSummaryPlanner.isDue(activeTime: 60, lastRefresh: nil, interval: 60, segments: [line(1, "a")], cutoff: 0, notesChanged: false))
    }

    @Test func noRefreshWithoutTranscript() {
        #expect(!LiveSummaryPlanner.isDue(activeTime: 600, lastRefresh: nil, interval: 120, segments: [], cutoff: 0, notesChanged: true))
    }

    @Test func nextRefreshAfterTheIntervalOnlyWithSomethingNew() {
        let lines = [line(10, "a"), line(200, "b")]
        #expect(!LiveSummaryPlanner.isDue(activeTime: 300, lastRefresh: 180, interval: 180, segments: lines, cutoff: 15, notesChanged: false))
        #expect(LiveSummaryPlanner.isDue(activeTime: 360, lastRefresh: 180, interval: 180, segments: lines, cutoff: 15, notesChanged: false))
        #expect(!LiveSummaryPlanner.isDue(activeTime: 360, lastRefresh: 180, interval: 180, segments: lines, cutoff: 205, notesChanged: false))
        #expect(LiveSummaryPlanner.isDue(activeTime: 360, lastRefresh: 180, interval: 180, segments: lines, cutoff: 205, notesChanged: true))
        #expect(LiveSummaryPlanner.isDue(activeTime: 300, lastRefresh: 180, interval: 120, segments: lines, cutoff: 15, notesChanged: false))
    }

    @Test func intervalChoicesRunFromOneToFiveMinutesInHalfMinutes() {
        #expect(LiveSummaryPlanner.intervalChoices == [60, 90, 120, 150, 180, 210, 240, 270, 300])
        #expect(LiveSummaryPlanner.defaultInterval == 120)
    }

    @Test func intervalLabelsReadAsMinutesAndSeconds() {
        #expect(LiveSummaryPlanner.intervalLabel(60) == "1 min")
        #expect(LiveSummaryPlanner.intervalLabel(90) == "1 min 30 s")
        #expect(LiveSummaryPlanner.intervalLabel(300) == "5 min")
    }

    @Test func savedIntervalSnapsToTheNearestChoice() {
        #expect(LiveSummaryPlanner.normalizedInterval(120) == 120)
        #expect(LiveSummaryPlanner.normalizedInterval(30) == 60)
        #expect(LiveSummaryPlanner.normalizedInterval(400) == 300)
        #expect(LiveSummaryPlanner.normalizedInterval(100) == 90)
        #expect(LiveSummaryPlanner.normalizedInterval(110) == 120)
    }

    @Test func settingsDefaultToTwoMinutesAndOlderFilesToo() throws {
        #expect(MeetingSettings().liveSummaryInterval == 120)
        let old = try JSONDecoder().decode(MeetingSettings.self, from: Data(#"{"windowCollapsed":true}"#.utf8))
        #expect(old.liveSummaryInterval == 120)
        let odd = try JSONDecoder().decode(MeetingSettings.self, from: Data(#"{"liveSummaryInterval":45}"#.utf8))
        #expect(odd.liveSummaryInterval == 60)
        let saved = try JSONDecoder().decode(MeetingSettings.self, from: Data(#"{"liveSummaryInterval":240}"#.utf8))
        #expect(saved.liveSummaryInterval == 240)
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
        #expect(request.disableThinking)
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
        #expect(request.disableThinking)
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
