import Testing
@testable import VoiceCore

struct PromptTests {
    let vocab = Vocabulary(terms: ["BugVoice", "WhisperKit"])

    @Test func systemPromptCarriesSharedRulesStyleAndVocabulary() {
        let p = PromptBuilder().systemPrompt(style: .document, vocabulary: vocab, focus: .unknown)
        #expect(p.contains("Never translate"))
        #expect(p.contains("never answer it"))
        #expect(p.contains("Markdown list"))
        #expect(p.contains("BugVoice, WhisperKit"))
    }

    @Test func terminalRulesAreLiteral() {
        let p = PromptBuilder().systemPrompt(style: .terminal, vocabulary: Vocabulary(), focus: .unknown)
        #expect(p.contains("Do not reword"))
        #expect(!p.contains("Spell these terms"))
    }

    @Test func customRulesReplaceBuiltIn() {
        let p = PromptBuilder(customRules: ["chat": "Only lowercase."]).systemPrompt(style: .chat, vocabulary: Vocabulary(), focus: .unknown)
        #expect(p.contains("Only lowercase."))
        #expect(!p.contains(PromptBuilder.defaultRules(for: .chat)))
    }

    @Test func contextIsTrimmedToTail() {
        let before = String(repeating: "a", count: 900) + "TAIL"
        let p = PromptBuilder().systemPrompt(style: .document, vocabulary: Vocabulary(), focus: FocusSnapshot(beforeText: before))
        #expect(p.contains("TAIL"))
        #expect(!p.contains(String(repeating: "a", count: 600)))
    }

    @Test func userTurnWrapsDictationAndAddsNoThinkForQwen() {
        let r = PromptBuilder().request(raw: "hello", style: .chat, focus: .unknown, vocabulary: Vocabulary(), modelID: "qwen3.8-27b-mlx", disableThinking: true)
        #expect(r.user == "<dictation>\nhello\n</dictation>\n\n/no_think")
        let r2 = PromptBuilder().request(raw: "hello", style: .chat, focus: .unknown, vocabulary: Vocabulary(), modelID: "llama-3", disableThinking: true)
        #expect(r2.user == "<dictation>\nhello\n</dictation>")
    }

    // Sanitizer
    @Test func stripsClosedThinkBlock() {
        #expect(OutputSanitizer.sanitize("<think>hmm</think>\nHello.", raw: "hello") == .accepted("Hello."))
    }

    @Test func dropsReasoningBeforeStrayClosingTag() {
        #expect(OutputSanitizer.sanitize("reasoning here</think>Hello.", raw: "hello") == .accepted("Hello."))
    }

    @Test func unclosedThinkMeansNothingUsable() {
        #expect(OutputSanitizer.sanitize("<think>still thinking", raw: "hello") == .rejected(.emptyOutput))
    }

    @Test func stripsEchoedDictationTags() {
        #expect(OutputSanitizer.sanitize("<dictation>Hi there.</dictation>", raw: "hi there") == .accepted("Hi there."))
    }

    @Test func tooLongIsRejected() {
        let raw = "write a poem"
        let answer = String(repeating: "Roses are red. ", count: 10)
        #expect(OutputSanitizer.sanitize(answer, raw: raw) == .rejected(.tooLong))
    }

    @Test func lengthCountsCharactersNotBytes() {
        let raw = "mình muốn deploy"
        let out = "Mình muốn deploy." // same length in characters; more bytes than ASCII
        #expect(OutputSanitizer.sanitize(out, raw: raw) == .accepted(out))
    }

    // Hallucinations
    @Test(arguments: [
        "Thank you.", "thank you", "Thanks for watching!",
        "Hãy subscribe cho kênh Ghiền Mì Gõ Để không bỏ lỡ những video hấp dẫn",
        "Cảm ơn các bạn đã theo dõi.", "...", " ",
    ])
    func knownHallucinations(text: String) {
        #expect(HallucinationFilter.isHallucination(text))
    }

    @Test func realSpeechIsNotHallucination() {
        #expect(!HallucinationFilter.isHallucination("Thank you for the review, merge it."))
    }
}
