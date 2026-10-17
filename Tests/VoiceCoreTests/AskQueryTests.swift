import Foundation
import Testing
@testable import VoiceCore

@Suite("AskQuery")
struct AskQueryTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi, second: s))!
    }

    @Test func parsesTermsDatesPeople() {
        let reply = #"{"terms": ["budget", " ", "ngân sách"], "time": "last month", "from": "2026-09-01", "to": "2026-09-30", "people": ["Linh"]}"#
        let q = AskQueryPrompt.parse(reply, question: "budget last month", calendar: calendar)
        #expect(q.terms == ["budget", "ngân sách"])
        #expect(q.from == date(2026, 9, 1))
        #expect(q.to == date(2026, 9, 30, 23, 59, 59))
        #expect(q.people == ["Linh"])
    }

    @Test func fencedJSONParses() {
        let reply = "<think>hmm</think>\n```json\n{\"terms\": [\"roadmap\"], \"from\": null, \"to\": null, \"people\": []}\n```"
        let q = AskQueryPrompt.parse(reply, question: "roadmap", calendar: calendar)
        #expect(q.terms == ["roadmap"])
        #expect(q.from == nil && q.to == nil && q.people.isEmpty)
    }

    @Test func badJSONFallsBack() {
        let q = AskQueryPrompt.parse("not json at all", question: "what did we decide about pricing", calendar: calendar)
        #expect(q == AskQueryPrompt.fallback(question: "what did we decide about pricing"))
        #expect(q.terms.contains("pricing"))
    }

    @Test func badDateIsNilOnly() {
        let reply = #"{"terms": ["a1"], "time": "September", "from": "last month", "to": "2026-09-30", "people": []}"#
        let q = AskQueryPrompt.parse(reply, question: "q in September", calendar: calendar)
        #expect(q.terms == ["a1"])
        #expect(q.from == nil)
        #expect(q.to != nil)
    }

    @Test func rangeWithoutTimeWordsIsDropped() {
        let reply = #"{"terms": ["bot"], "time": null, "from": "2026-10-17", "to": "2026-10-17", "people": []}"#
        let q = AskQueryPrompt.parse(reply, question: "Which features did we decide to build?", calendar: calendar)
        #expect(q.from == nil && q.to == nil)
        #expect(q.terms == ["bot"])
    }

    @Test func rangeWithTimeWordsNotInQuestionIsDropped() {
        let reply = #"{"terms": ["bot"], "time": "today", "from": "2026-10-17", "to": "2026-10-17", "people": []}"#
        let q = AskQueryPrompt.parse(reply, question: "Chúng ta đã quyết định làm gì cho con bot?", calendar: calendar)
        #expect(q.from == nil && q.to == nil)
    }

    @Test func timeWordsMatchFolded() {
        let reply = #"{"terms": ["bot"], "time": "tuan truoc", "from": "2026-10-05", "to": "2026-10-11", "people": []}"#
        let q = AskQueryPrompt.parse(reply, question: "Tuần trước chúng ta nói gì về bot?", calendar: calendar)
        #expect(q.from == date(2026, 10, 5))
        #expect(q.to != nil)
    }

    @Test func emptyTermsUseFallbackTerms() {
        let q = AskQueryPrompt.parse(#"{"terms": [], "people": ["Luna"]}"#, question: "what about pricing", calendar: calendar)
        #expect(q.terms == ["pricing"])
        #expect(q.people == ["Luna"])
    }

    @Test func termsCappedAt24() {
        let terms = (0..<40).map { "\"t\($0)\"" }.joined(separator: ",")
        let q = AskQueryPrompt.parse(#"{"terms": [\#(terms)], "from": null, "to": null, "people": []}"#, question: "q", calendar: calendar)
        #expect(q.terms.count == 24)
        #expect(q.terms.first == "t0")
    }

    @Test func fallbackDropsStopWords() {
        let q = AskQueryPrompt.fallback(question: "what did we decide about feature x")
        #expect(q.terms.contains("decide"))
        #expect(q.terms.contains("feature"))
        #expect(q.terms.contains("x"))
        #expect(!q.terms.contains("what"))
        #expect(!q.terms.contains("we"))
        #expect(q.from == nil && q.to == nil && q.people.isEmpty)
    }

    @Test func historyIsInPrompt() {
        let history = [NoteChatTurn(message: "Who joined the launch call?", reply: "Linh and Marco.")]
        let r = AskQueryPrompt.request(question: "and who else?", history: history, today: date(2026, 10, 17, 12), modelID: "qwen3")
        #expect(r.user.contains("Who joined the launch call?"))
        #expect(r.user.contains("Linh and Marco."))
        #expect(r.user.contains("and who else?"))
        #expect(r.disableThinking)
        #expect(r.temperature == 0)
        #expect(r.maxTokens == 512)
    }

    @Test func todayIsInPrompt() {
        let r = AskQueryPrompt.request(question: "q", history: [], today: date(2026, 10, 17, 12), modelID: "m")
        #expect(r.system.contains("2026-10-17") || r.user.contains("2026-10-17"))
    }

    @Test func recentMeansLastFourteenDays() {
        #expect(AskQueryPrompt.rules.contains("recent, recently, lately or latest mean the last 14 days"))
    }

    @Test func tenseIsNotATime() {
        #expect(AskQueryPrompt.rules.contains("Past tense alone (did, was, đã, fue) is not a time"))
    }
}
