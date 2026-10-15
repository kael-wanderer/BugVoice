import Foundation
import Testing
@testable import VoiceCore

struct SnippetExpanderTests {
    let linkedin = Snippet(trigger: "my linkedin", text: "linkedin.com/in/kael")
    let signOff = Snippet(trigger: "sign off", text: "Best,\nKael")

    @Test func singleTrigger() {
        let p = SnippetExpander.protect("here is my linkedin thanks", snippets: [linkedin])
        #expect(p.text == "here is ⟦S1⟧ thanks")
        #expect(p.fills == ["⟦S1⟧": "linkedin.com/in/kael"])
    }

    @Test func multipleTriggersNumberedInOrderOfAppearance() {
        let p = SnippetExpander.protect("sign off then my linkedin", snippets: [linkedin, signOff])
        #expect(p.text == "⟦S1⟧ then ⟦S2⟧")
        #expect(p.fills == ["⟦S1⟧": "Best,\nKael", "⟦S2⟧": "linkedin.com/in/kael"])
    }

    @Test func sameTriggerTwiceGetsTwoPlaceholders() {
        let p = SnippetExpander.protect("my linkedin and my linkedin", snippets: [linkedin])
        #expect(p.text == "⟦S1⟧ and ⟦S2⟧")
    }

    @Test func caseInsensitive() {
        #expect(SnippetExpander.protect("My LinkedIn", snippets: [linkedin]).text == "⟦S1⟧")
    }

    @Test func vietnameseTriggerMatchesInEitherNormalForm() {
        let s = Snippet(trigger: "chữ ký", text: "Kael")
        let decomposed = "gửi chữ ký".decomposedStringWithCanonicalMapping
        #expect(SnippetExpander.protect(decomposed, snippets: [s]).text == "gửi ⟦S1⟧".precomposedStringWithCanonicalMapping)
    }

    @Test(arguments: ["sign-off", "sign  off", "Sign - off"])
    func spacesOrHyphensBetweenWords(spoken: String) {
        #expect(SnippetExpander.protect("ok \(spoken) now", snippets: [signOff]).text == "ok ⟦S1⟧ now")
    }

    @Test func punctuationAfterTriggerStays() {
        #expect(SnippetExpander.protect("my linkedin.", snippets: [linkedin]).text == "⟦S1⟧.")
    }

    @Test func longestTriggerFirst() {
        let short = Snippet(trigger: "sign", text: "X")
        let p = SnippetExpander.protect("sign off now", snippets: [short, signOff])
        #expect(p.text == "⟦S1⟧ now")
        #expect(p.fills["⟦S1⟧"] == "Best,\nKael")
    }

    @Test(arguments: ["mylinkedin", "my linkedins", "cosign off"])
    func noMatchInsideLongerWords(text: String) {
        let p = SnippetExpander.protect(text, snippets: [linkedin, signOff])
        #expect(p.fills.isEmpty)
        #expect(p.text == text)
    }

    @Test func noSnippetsLeavesTextUnchanged() {
        let p = SnippetExpander.protect("hello", snippets: [])
        #expect(p == ProtectedText(text: "hello", fills: [:]))
    }

    @Test func isIntactNeedsEachPlaceholderExactlyOnceAndNoOthers() {
        let p = SnippetExpander.protect("a my linkedin b sign off", snippets: [linkedin, signOff])
        #expect(p.isIntact("A ⟦S1⟧ b ⟦S2⟧."))
        #expect(p.isIntact("⟦S2⟧ first, then ⟦S1⟧"))
        #expect(!p.isIntact("A b ⟦S2⟧."))
        #expect(!p.isIntact("⟦S1⟧ ⟦S1⟧ ⟦S2⟧"))
        #expect(!p.isIntact("[S1] ⟦S2⟧"))
        #expect(!p.isIntact("⟦S1⟧ ⟦S2⟧ ⟦S3⟧"))
        #expect(ProtectedText(text: "hi", fills: [:]).isIntact("Hi."))
    }

    @Test func fillRestoresMultiLineTextExactlyInOnePass() {
        let p = ProtectedText(text: "", fills: ["⟦S1⟧": "a ⟦S2⟧", "⟦S2⟧": "Best,\nKael"])
        #expect(p.fill("Thanks. ⟦S2⟧") == "Thanks. Best,\nKael")
        #expect(p.fill("⟦S1⟧ ⟦S2⟧") == "a ⟦S2⟧ Best,\nKael")
    }

    @Test func placeholdersInText() {
        #expect(SnippetExpander.placeholders(in: "x ⟦S1⟧ y ⟦S12⟧") == ["⟦S1⟧", "⟦S12⟧"])
        #expect(SnippetExpander.placeholders(in: "nothing").isEmpty)
    }
}
