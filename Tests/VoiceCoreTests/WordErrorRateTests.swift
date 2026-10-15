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

    @Test func editDistanceIdenticalIsZero() {
        #expect(WordErrorRate.editDistance(reference: "Hello, world.", hypothesis: "hello world") == 0)
    }

    @Test func editDistanceCountsInsertDeleteSubstitute() {
        #expect(WordErrorRate.editDistance(reference: "a b c", hypothesis: "a b c d") == 1)
        #expect(WordErrorRate.editDistance(reference: "a b c", hypothesis: "a c") == 1)
        #expect(WordErrorRate.editDistance(reference: "a b c", hypothesis: "a x c") == 1)
        #expect(WordErrorRate.editDistance(reference: "um so the meeting is friday", hypothesis: "the meeting is thursday") == 3)
    }

    @Test func editDistanceWithEmptySide() {
        #expect(WordErrorRate.editDistance(reference: "", hypothesis: "one two") == 2)
        #expect(WordErrorRate.editDistance(reference: "one two", hypothesis: "") == 2)
        #expect(WordErrorRate.editDistance(reference: "", hypothesis: "") == 0)
    }
