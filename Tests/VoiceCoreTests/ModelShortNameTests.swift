import Testing
@testable import VoiceCore

struct ModelShortNameTests {
    func settings(_ provider: TextModelProvider, _ model: String) -> TextModelSettings {
        var s = TextModelSettings()
        s.provider = provider
        s.model = model
        return s
    }

    @Test func takesLeadingWordCapitalized() {
        #expect(settings(.openAICompatible, "qwen3.8-27b-mlx").shortName == "Qwen")
        #expect(settings(.anthropicCompatible, "claude-sonnet-4").shortName == "Claude")
        #expect(settings(.openAICompatible, "llama3.2:3b").shortName == "Llama")
    }

    @Test func dropsOrganizationPrefix() {
        #expect(settings(.openAICompatible, "mlx-community/Qwen3-8B-4bit").shortName == "Qwen")
    }

    @Test func fallsBackToFullIDWithoutLeadingLetters() {
        #expect(settings(.openAICompatible, "4o-mini").shortName == "4o-mini")
    }

    @Test func emptyModelHasNoName() {
        #expect(settings(.openAICompatible, "  ").shortName == nil)
    }

    @Test func appleIntelligenceAndNone() {
        #expect(settings(.appleIntelligence, "ignored").shortName == "Apple Intelligence")
        #expect(settings(.none, "qwen").shortName == nil)
    }
}
