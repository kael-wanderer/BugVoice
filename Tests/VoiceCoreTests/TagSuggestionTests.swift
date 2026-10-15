import Testing
@testable import VoiceCore

struct TagSuggestionTests {
    let allowed = ["decision", "todo", "acme", "sprint"]

    @Test func keepsAllowedTagsInOrderUpToThree() {
        let answer = "1. #todo\n- acme\n* Decision\nsprint"
        #expect(TagSuggestion.parse(answer, allowed: allowed, existing: []) == ["todo", "acme", "decision"])
    }

    @Test func dropsInventedExistingAndDuplicateTags() {
        let answer = "todo\nbudget\ntodo\nsprint"
        #expect(TagSuggestion.parse(answer, allowed: allowed, existing: ["sprint"]) == ["todo"])
    }

    @Test func noneAndThinkingGiveNothing() {
        #expect(TagSuggestion.parse("none", allowed: allowed, existing: []).isEmpty)
        #expect(TagSuggestion.parse("<think>maybe todo</think>\nNone.", allowed: allowed, existing: []).isEmpty)
    }

    @Test func proseLinesAreIgnored() {
        let answer = "Here are the tags that fit:\ntodo"
        #expect(TagSuggestion.parse(answer, allowed: allowed, existing: []) == ["todo"])
    }

    @Test func requestListsAllowedTagsAndSummary() {
        let request = TagSuggestion.request(summary: "We agreed on scope.", allowed: ["todo", "acme"])
        #expect(request.system == TagSuggestion.system)
        #expect(request.user == "Allowed tags:\ntodo\nacme\n\nSummary:\nWe agreed on scope.")
        #expect(request.maxTokens == 64)
        #expect(request.disableThinking)
    }

    @Test func requestCapsAllowedList() {
        let many = (0..<250).map { "t\($0)" }
        let request = TagSuggestion.request(summary: "S", allowed: many)
        #expect(request.user.components(separatedBy: "\n").filter { $0.hasPrefix("t") }.count == 200)
    }
}
