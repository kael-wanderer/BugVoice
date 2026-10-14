import Testing
@testable import VoiceCore

struct WordErrorRateTests {
    @Test func identicalIsZero() {
        #expect(WordErrorRate.compute(reference: "Xin chào, các bạn!", hypothesis: "xin chào các bạn") == 0)
    }

    @Test func oneSubstitutionInFourWords() {
        #expect(WordErrorRate.compute(reference: "deploy the api today", hypothesis: "deploy the app today") == 0.25)
    }

    @Test func diacriticsMatter() {
        #expect(WordErrorRate.compute(reference: "mình muốn", hypothesis: "minh muon") == 1)
    }

    @Test func emptyReference() {
        #expect(WordErrorRate.compute(reference: "", hypothesis: "") == 0)
        #expect(WordErrorRate.compute(reference: "", hypothesis: "extra") == 1)
    }
}
