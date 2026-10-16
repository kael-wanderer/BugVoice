import Testing
@testable import VoiceCore

struct NoteTransformTests {
    @Test func requestWrapsTextAndAddsInstruction() {
        let request = NoteTransformPrompt.request(.concise, text: "a b c", modelID: "gpt-4.1", disableThinking: false)
        #expect(request.system.hasPrefix("You rewrite a passage from the user's note."))
        #expect(request.system.hasSuffix("Make it shorter. Keep every fact and decision; drop filler and repetition."))
        #expect(request.user == "<text>\na b c\n</text>")
        #expect(request.maxTokens == 512)
        #expect(!request.disableThinking)
    }

    @Test func maxTokensScaleWithWordsAndCap() {
        let words = Array(repeating: "w", count: 1_000).joined(separator: " ")
        #expect(NoteTransformPrompt.request(.polish, text: words, modelID: "m", disableThinking: false).maxTokens == 4_000)
        let many = Array(repeating: "w", count: 3_000).joined(separator: " ")
        #expect(NoteTransformPrompt.request(.polish, text: many, modelID: "m", disableThinking: false).maxTokens == 8_192)
    }

    @Test func qwenWithThinkingOffGetsNoThink() {
        let request = NoteTransformPrompt.request(.polish, text: "x", modelID: "qwen3.8-27b-mlx", disableThinking: true)
        #expect(request.user.hasSuffix("\n\n/no_think"))
        #expect(request.disableThinking)
        let other = NoteTransformPrompt.request(.polish, text: "x", modelID: "llama", disableThinking: true)
        #expect(!other.user.contains("/no_think"))
        #expect(other.disableThinking)
    }

    @Test func askRequestPutsNoteThenQuestion() {
        let request = NoteTransformPrompt.askRequest(question: "Who owns it?", note: "Kael owns it.", modelID: "m", disableThinking: false)
        #expect(request.system.hasPrefix("Answer the question using only the note inside <note> tags."))
        #expect(request.user == "<note>\nKael owns it.\n</note>\n\nQuestion: Who owns it?")
        #expect(request.maxTokens == 1_024)
    }

    @Test func cleanStripsThinkingTagsFenceAndQuotes() {
        #expect(NoteTransformPrompt.clean("<think>hm</think>\n<text>Done.</text>") == "Done.")
        #expect(NoteTransformPrompt.clean("reasoning</think>Result") == "Result")
        #expect(NoteTransformPrompt.clean("```markdown\n- a\n- b\n```") == "- a\n- b")
        #expect(NoteTransformPrompt.clean("“Quoted.”") == "Quoted.")
        #expect(NoteTransformPrompt.clean("\"a\" and \"b\"") == "\"a\" and \"b\"")
        #expect(NoteTransformPrompt.clean("<think>only") == nil)
        #expect(NoteTransformPrompt.clean("  ") == nil)
    }

    @Test func limitsAndCounts() {
        #expect(NoteTransformPrompt.wordCount(" one\ntwo  three ") == 3)
        #expect(!NoteTransformPrompt.isTooLong(String(repeating: "a", count: 12_000)))
        #expect(NoteTransformPrompt.isTooLong(String(repeating: "a", count: 12_001)))
    }

    @Test func transformsHaveTitlesAndShortcuts() {
        #expect(NoteTransform.allCases.map(\.title) == ["Polish", "More concise", "More professional", "Bullet points"])
        #expect(NoteTransform.allCases.map(\.shortcutKey) == ["1", "2", "3", "4"])
    }
}
