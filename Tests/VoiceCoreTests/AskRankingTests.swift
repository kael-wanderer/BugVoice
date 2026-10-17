import Foundation
import Testing
@testable import VoiceCore

@Suite struct AskRankingTests {
    private func passage(_ i: Int, _ text: String, speaker: String? = nil) -> AskPassage {
        AskPassage(
            source: .dictations, part: .dictation, index: i, date: Date(timeIntervalSince1970: 0),
            lines: [AskLine(id: "l\(i)", speaker: speaker, text: text)])
    }

    @Test func passageWithTermOutranksWithout() {
        let a = passage(0, "budget review for the quarter")
        let b = passage(1, "lunch plans")
        let s = AskRanking.wordScores([a, b], terms: ["budget"], people: [])
        #expect((s[a.id] ?? 0) > 0)
        #expect(s[b.id] == nil)
    }

    @Test func phraseNeedsOrder() {
        let a = passage(0, "option A wins")
        let b = passage(1, "A option wins")
        let s = AskRanking.wordScores([a, b], terms: ["option a"], people: [])
        #expect((s[a.id] ?? 0) > 0)
        #expect(s[b.id] == nil)
    }

    @Test func foldedMatch() {
        let a = passage(0, "La opción dos")
        let s = AskRanking.wordScores([a], terms: ["opcion"], people: [])
        #expect((s[a.id] ?? 0) > 0)
    }

    @Test func peopleBoost() {
        let a = passage(0, "budget talk", speaker: "Dũng")
        let plain = AskRanking.wordScores([a], terms: ["budget"], people: [])
        let boosted = AskRanking.wordScores([a], terms: ["budget"], people: ["dung"])
        #expect(abs(boosted[a.id]! - plain[a.id]! * 1.2) < 1e-9)
    }

    @Test func noTermsGivesEmpty() {
        #expect(AskRanking.wordScores([passage(0, "x")], terms: [], people: ["x"]).isEmpty)
        #expect(AskRanking.wordScores([passage(0, "x")], terms: ["  "], people: []).isEmpty)
    }

    @Test func duplicateTermsCountOnce() {
        let a = passage(0, "budget")
        let one = AskRanking.wordScores([a], terms: ["budget"], people: [])
        let two = AskRanking.wordScores([a], terms: ["budget", "Budget"], people: [])
        #expect(one == two)
    }

    @Test func fusionPrefersBoth() {
        let r = AskRanking.fuse([["a", "b", "c"], ["b", "d"]])
        #expect(r.first == "b")
        #expect(Set(r) == ["a", "b", "c", "d"])
    }

    @Test func fusionSingleListKeepsOrder() {
        #expect(AskRanking.fuse([["x", "y", "z"]]) == ["x", "y", "z"])
    }

    @Test func cosineOfSame() {
        #expect(abs(AskRanking.cosine([0.6, 0.8], [0.6, 0.8]) - 1) < 1e-6)
    }
}
