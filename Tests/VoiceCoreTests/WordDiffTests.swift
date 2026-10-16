import Testing
@testable import VoiceCore

struct WordDiffTests {
    @Test func marksRemovedAndAddedWords() {
        #expect(WordDiff.diff("we should of done it", "we should have done it") == [
            .same("we should "), .removed("of "), .added("have "), .same("done it"),
        ])
    }

    @Test func keepsLineBreaksOfTheNewText() {
        #expect(WordDiff.diff("a b", "a\nb") == [.same("a\nb")])
        #expect(WordDiff.diff("", "- a\n- b") == [.added("- a\n- b")])
    }

    @Test func identicalTextIsOneSamePiece() {
        #expect(WordDiff.diff("one two", "one two") == [.same("one two")])
    }

    @Test func longTextFallsBackToWholeReplacement() {
        let old = Array(repeating: "w", count: WordDiff.maxWords + 1).joined(separator: " ")
        #expect(WordDiff.diff(old, "short") == [.removed(old), .added("short")])
    }
}
