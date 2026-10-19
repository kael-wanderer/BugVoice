import Testing
@testable import VoiceCore

struct VocabularyTests {
    let sample = """
    # names and terms
    BugVoice
    WhisperKit

    Claude Code
    BugVoice
    # replacements
    bug voice => BugVoice
    cờ lốt cốt => Claude Code
    new line => \\n
    """

    @Test func parsesTermsSkippingCommentsBlanksAndDuplicates() {
        let v = Vocabulary.parse(sample)
        #expect(v.terms == ["BugVoice", "WhisperKit", "Claude Code"])
        #expect(v.replacements.count == 3)
        #expect(v.replacements[2].written == "\n")
    }

    @Test func replacementIsCaseInsensitiveAndWholeWord() {
        let v = Vocabulary.parse(sample)
        #expect(v.applyReplacements(to: "open Bug Voice now") == "open BugVoice now")
        #expect(v.applyReplacements(to: "debug voicemail") == "debug voicemail")
    }

    @Test func replacementWorksWithVietnameseDiacritics() {
        let v = Vocabulary.parse(sample)
        #expect(v.applyReplacements(to: "mở cờ lốt cốt lên") == "mở Claude Code lên")
    }

    @Test func replacementMatchesAcrossUnicodeNormalizationForms() {
        let decomposedRule = "cờ lốt cốt".decomposedStringWithCanonicalMapping + " => Claude Code"
        let v = Vocabulary.parse(decomposedRule)
        let precomposedText = "mở cờ lốt cốt lên".precomposedStringWithCanonicalMapping
        #expect(v.applyReplacements(to: precomposedText) == "mở Claude Code lên")

        let w = Vocabulary.parse("cờ lốt cốt => Claude Code".precomposedStringWithCanonicalMapping)
        let decomposedText = "mở cờ lốt cốt lên".decomposedStringWithCanonicalMapping
        #expect(w.applyReplacements(to: decomposedText) == "mở Claude Code lên")
    }

    @Test func longerSpokenPhraseWinsOverShorter() {
        let v = Vocabulary.parse("code => CODE\nclaude code => Claude Code")
        #expect(v.applyReplacements(to: "run claude code") == "run Claude Code")
    }

    @Test func replacedTextIsNeverRescanned() {
        let v = Vocabulary.parse("alpha => beta\nbeta => gamma")
        #expect(v.applyReplacements(to: "alpha beta") == "beta gamma")
    }

    @Test func templateCharactersInWrittenAreLiteral() {
        let v = Vocabulary.parse("dollar one => $1")
        #expect(v.applyReplacements(to: "price dollar one") == "price $1")
    }

    @Test func whisperPromptListsNewestFirstWithinBudget() {
        let v = Vocabulary(terms: ["alpha", "beta", "gamma"])
        #expect(v.whisperPrompt() == "gamma, beta, alpha")
        #expect(v.whisperPrompt(maxCharacters: 14) == "gamma, beta")
    }

    @Test func exampleComesFirst() {
        let v = Vocabulary(terms: ["Orca"])
        #expect(v.whisperPrompt(example: "E") == "E, Orca")
    }

    @Test func exampleNeverCut() {
        let v = Vocabulary(terms: ["LongTerm"])
        #expect(v.whisperPrompt(maxCharacters: 10, example: "123456789") == "123456789")
    }

    @Test func builtFromDictionary() throws {
        var f = DictionaryFile()
        f.addWords("Kael")
        f.addWords("OpenWhispr")
        f.addHeardAs("open whisper", to: f.words[0].id)
        try f.addSnippet(trigger: "my linkedin", text: "linkedin.com/in/kael")
        let v = Vocabulary(dictionary: f)
        #expect(v.terms == ["Kael", "OpenWhispr"])
        #expect(v.whisperPrompt() == "OpenWhispr, Kael")
        #expect(v.applyReplacements(to: "open whisper rocks") == "OpenWhispr rocks")
        #expect(v.snippets == f.snippets)
    }
}
