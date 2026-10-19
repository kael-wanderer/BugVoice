import Testing
@testable import VoiceCore

struct PromptTests {
    let vocab = Vocabulary(terms: ["BugVoice", "WhisperKit"])

    @Test func englishLine() {
        let p = PromptBuilder().systemPrompt(style: .work, vocabulary: Vocabulary(), focus: .unknown, language: .en, keepEnglishWords: true)
        #expect(p.contains("The speaker spoke English."))
        #expect(!p.contains(PromptBuilder.keepEnglishRule))
    }

    @Test func vietnameseKeepsEnglish() {
        let p = PromptBuilder().systemPrompt(style: .work, vocabulary: Vocabulary(), focus: .unknown, language: .vi, keepEnglishWords: true)
        #expect(p.contains("The speaker spoke Vietnamese."))
        #expect(p.contains(PromptBuilder.keepEnglishRule))
    }

    @Test func autoKeepsEnglishNoLine() {
        let p = PromptBuilder().systemPrompt(style: .work, vocabulary: Vocabulary(), focus: .unknown, language: .auto, keepEnglishWords: true)
        #expect(p.contains(PromptBuilder.keepEnglishRule))
        #expect(!p.contains("The speaker spoke"))
    }

    @Test func keepOffNoRule() {
        let p = PromptBuilder().systemPrompt(style: .work, vocabulary: Vocabulary(), focus: .unknown, language: .vi, keepEnglishWords: false)
        #expect(!p.contains(PromptBuilder.keepEnglishRule))
    }

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
        let p = PromptBuilder(customRules: ["work": "Only lowercase."]).systemPrompt(style: .work, vocabulary: Vocabulary(), focus: .unknown)
        #expect(p.contains("Only lowercase."))
        #expect(!p.contains(PromptBuilder.defaultRules(for: .work)))
    }

    @Test func newDefaultRules() {
        #expect(PromptBuilder.defaultRules(for: .personal).hasPrefix("Casual and warm."))
        #expect(PromptBuilder.defaultRules(for: .personal).contains("No greeting or sign-off unless spoken."))
        #expect(PromptBuilder.defaultRules(for: .work).hasPrefix("Clear and short."))
        #expect(PromptBuilder.defaultRules(for: .work).contains("when the speaker lists items, use bullets"))
        #expect(PromptBuilder.defaultRules(for: .other).hasPrefix("Light touch."))
    }

    @Test func contextIsTrimmedToTail() {
        let before = String(repeating: "a", count: 900) + "TAIL"
        let p = PromptBuilder().systemPrompt(style: .document, vocabulary: Vocabulary(), focus: FocusSnapshot(beforeText: before))
        #expect(p.contains("TAIL"))
        #expect(!p.contains(String(repeating: "a", count: 600)))
    }

    @Test func userTurnWrapsDictationAndAddsNoThinkForQwen() {
        let r = PromptBuilder().request(raw: "hello", style: .personal, focus: .unknown, vocabulary: Vocabulary(), modelID: "qwen3.8-27b-mlx", disableThinking: true)
        #expect(r.user == "<dictation>\nhello\n</dictation>\n\n/no_think")
        let r2 = PromptBuilder().request(raw: "hello", style: .personal, focus: .unknown, vocabulary: Vocabulary(), modelID: "llama-3", disableThinking: true)
        #expect(r2.user == "<dictation>\nhello\n</dictation>")
        #expect(r.disableThinking)
        #expect(!r2.disableThinking)
    }

    @Test func placeholderLineOnlyWhenRequestHasPlaceholder() {
        let with = PromptBuilder().request(raw: "here is ⟦S1⟧", style: .work, focus: .unknown, vocabulary: Vocabulary(), modelID: "m", disableThinking: false)
        #expect(with.system.contains("Tokens like ⟦S1⟧ are placeholders. Keep every one exactly once, unchanged, where it belongs."))
        let without = PromptBuilder().request(raw: "here is it", style: .work, focus: .unknown, vocabulary: Vocabulary(), modelID: "m", disableThinking: false)
        #expect(!without.system.contains("placeholders"))
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
        "[BLANK_AUDIO]", " [ Silence ] ", "(breathing)", "[Music] (upbeat music)",
        "[BLANK_AUDIO] Thank you.", "thank.you", "[MUSIC PLAYING]", "(silence)", "[inaudible]",
        "Music", "♪ Music ♪",
        // Whisper writes subtitle credits in other scripts over music.
        "Субтитры сделал DimaTorzok", "Субтитры подогнал «Симон»!", "ご視聴ありがとうございました",
    ])
    func knownHallucinations(text: String) {
        #expect(HallucinationFilter.isHallucination(text))
    }

    @Test(arguments: [
        "Thank you for the review, merge it.",
        "[BLANK_AUDIO] merge the branch",
        "Mình muốn deploy cái API này",
        "The Tokyo office wrote 東京 in the ticket",
        "play the music again",
    ])
    func realSpeechIsNotHallucination(text: String) {
        #expect(!HallucinationFilter.isHallucination(text))
    }
}
