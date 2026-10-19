import Foundation
import Testing
@testable import VoiceCore

struct CorrectionsTests {
    func kept(_ a: String, _ b: String) -> [CorrectionCandidate] {
        CorrectionFilter.keep(CorrectionDiff.candidates(pasted: a, edited: b), pasted: a)
    }
    @Test func regionBetweenAnchors() { #expect(CorrectionRegion.find(value: "Hi team. Thanks Kael, I'll review the build. Bye", before: "Hi team. ", after: " Bye") == "Thanks Kael, I'll review the build.") }
    @Test func regionUsesAnchorsNotText() { #expect(CorrectionRegion.find(value: "ok ok. A: ok ok. B", before: "A: ", after: " B") == "ok ok.") }
    @Test func regionNilWhenAnchorGone() { #expect(CorrectionRegion.find(value: "", before: "A", after: "B") == nil) }
    @Test func emptyAnchorsMeanEnds() { #expect(CorrectionRegion.find(value: " hi ", before: "", after: "") == "hi") }
    @Test func regionNilWhenTooLong() { #expect(CorrectionRegion.find(value: String(repeating: "a", count: 100001), before: "", after: "") == nil) }
    @Test func nameFix() { #expect(kept("Thanks Kale, I'll review the build after lunch.", "Thanks Kael, I'll review the build after lunch.") == [CorrectionCandidate(heard: "Kale", written: "Kael")]) }
    @Test func toneFixKept() { #expect(kept("đi ăn bun cha nhé", "đi ăn bún chả nhé") == [CorrectionCandidate(heard: "bun cha", written: "bún chả")]); #expect(CorrectionFilter.similarity("bun cha", "bún chả") == 1) }
    @Test func rewordIgnored() { #expect(kept("That looks good.", "That looks great.").isEmpty) }
    @Test func sentenceCaseIgnored() { #expect(kept("the build is ready", "The build is ready").isEmpty) }
    @Test func punctuationOnlyIgnored() { #expect(kept("ok, ship it", "ok — ship it").isEmpty) }
    @Test func textAddedAfterPasteIgnored() { #expect(kept("fix the bug", "fix the bug in AppModel").isEmpty) }
    @Test func rewriteIgnored() { #expect(kept("cat dog bat hat mat one two three four five", "cats dogs bats hats mats one two three four five").isEmpty) }
    @Test func moreThanThreeIgnored() { #expect(kept("cat a dog b bat c hat d e f g h i j k l m n o p", "cats a dogs b bats c hats d e f g h i j k l m n o p").isEmpty) }
    @Test func fourWordRunSkipped() { #expect(CorrectionDiff.candidates(pasted: "cat dog bat hat end", edited: "cats dogs bats hats end").isEmpty) }
    @Test func foldHandlesD() { #expect(CorrectionFilter.fold("Đường") == "duong") }
}

struct CorrectionWatchTests {
    @Test func watchUsesLatestRegion() {
        var w = CorrectionWatch(pasted: "Thanks Kale for the build", before: "Hi ", after: " Bye")
        let observed1 = w.observe(value: "Hi Thanks Kale for the build Bye"); #expect(observed1)
        let observed2 = w.observe(value: "Hi Thanks Kael for the build Bye"); #expect(observed2)
        #expect(w.result() == [CorrectionCandidate(heard: "Kale", written: "Kael")])
    }
    @Test func clearedFieldUsesLastSeenRegion() {
        var w = CorrectionWatch(pasted: "Thanks Kale for the build", before: "Hi ", after: " Bye")
        let observed3 = w.observe(value: "Hi Thanks Kael for the build Bye"); #expect(observed3)
        let observed4 = w.observe(value: ""); #expect(!observed4)
        #expect(w.result() == [CorrectionCandidate(heard: "Kale", written: "Kael")])
    }
    @Test func unchangedGivesNothing() {
        var w = CorrectionWatch(pasted: "Thanks Kale for the build", before: "", after: "")
        let observed5 = w.observe(value: "Thanks Kale for the build"); #expect(observed5); #expect(w.result().isEmpty)
    }
    @Test func nilValueEnds() {
        var w = CorrectionWatch(pasted: "Thanks Kale", before: "", after: "")
        let observed6 = w.observe(value: nil); #expect(!observed6); #expect(w.result().isEmpty)
    }
}
