import Foundation
import Testing
@testable import VoiceCore

struct CommandPromptTests {
    func request(_ selection: String? = "abc", language: SpeechLanguage = .auto) -> CleanupRequest {
        CommandPrompt.request(instruction: "make formal", selection: selection, style: .work,
            focus: FocusSnapshot(beforeText: "Lan: join at 3?"), vocabulary: Vocabulary(),
            language: language, keepEnglishWords: true, modelID: "qwen", disableThinking: true)
    }
    @Test func rewriteHasTextBlock() {
        let r = request()
        #expect(r.user.contains("<instruction>\nmake formal\n</instruction>"))
        #expect(r.user.contains("<text>\nabc\n</text>"))
        #expect(r.system.hasPrefix(CommandPrompt.rewriteRules))
    }
    @Test func writeHasNoTextBlock() {
        let r = request(nil)
        #expect(!r.user.contains("<text>"))
        #expect(r.system.hasPrefix(CommandPrompt.writeRules))
        #expect(r.system.contains("<before>Lan: join at 3?</before>"))
    }
    @Test func emptySelectionIsWrite() { #expect(request("").system.hasPrefix(CommandPrompt.writeRules)) }
    @Test func keepEnglishOnlyForViAndAuto() {
        for l in [SpeechLanguage.vi, .auto] { #expect(request(language: l).system.contains(PromptBuilder.keepEnglishRule)) }
        #expect(!request(language: .en).system.contains(PromptBuilder.keepEnglishRule))
    }
    @Test func includesProjectWords() {
        var vocabulary = Vocabulary()
        vocabulary.projectWords = ["AppModel", "HistoryEntry"]
        let r = CommandPrompt.request(instruction: "rewrite", selection: nil, style: .work, focus: .unknown,
            vocabulary: vocabulary, language: .en, keepEnglishWords: false, modelID: "m", disableThinking: false)
        #expect(r.system.contains("Code names from the current project. When the speaker says one as plain words, write the name exactly (for example \"app model\" is AppModel): AppModel, HistoryEntry"))
    }
    @Test func maxTokensScales() {
        #expect(request(String(repeating: "a", count: 10)).maxTokens == 1034)
        #expect(request(nil).maxTokens == 1024)
        #expect(request(String(repeating: "a", count: 9000)).maxTokens == 8192)
    }
    @Test func dropsAnnouncingLine() {
        #expect(CommandOutput.sanitize("Here is the formal version:\nDear team,", selection: nil) == .success("Dear team,"))
        #expect(CommandOutput.sanitize("Note: done", selection: nil) == .success("Note: done"))
    }
    @Test func keepsHeadingFromSelection() {
        let selection = "Agenda:\nbudget, hiring"
        #expect(CommandOutput.sanitize("Agenda:\n- budget\n- hiring", selection: selection) == .success("Agenda:\n- budget\n- hiring"))
    }
    @Test func dropsWrappingQuotes() {
        #expect(CommandOutput.sanitize("\"Hello there.\"", selection: "hello there") == .success("Hello there."))
        #expect(CommandOutput.sanitize("“Xin chào”", selection: nil) == .success("Xin chào"))
    }
    @Test func keepsQuotesFromSelection() {
        #expect(CommandOutput.sanitize("\"Quoted\"", selection: "\"quoted\"") == .success("\"Quoted\""))
    }
    @Test func rejectsEmptyAndTooLong() {
        #expect(CommandOutput.sanitize("<think>x</think>", selection: nil) == .failure(.empty))
        #expect(CommandOutput.sanitize(String(repeating: "a", count: 2005), selection: "a") == .failure(.tooLong))
        #expect(CommandOutput.sanitize(String(repeating: "a", count: 2000), selection: nil) == .success(String(repeating: "a", count: 2000)))
    }
}
