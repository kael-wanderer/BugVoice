import Testing
@testable import VoiceCore

struct NotesSpacingTests {
    @Test func addsSpaceAfterPreviousWord() {
        #expect(NotesSpacing.fit("Hello, how are you?", into: "more feature", at: 12) == " Hello, how are you?")
    }

    @Test func noSpaceAtStartOrAfterWhitespace() {
        #expect(NotesSpacing.fit("Hello.", into: "", at: 0) == "Hello.")
        #expect(NotesSpacing.fit("Hello.", into: "Title\n", at: 6) == "Hello.")
        #expect(NotesSpacing.fit("Hello.", into: "word ", at: 5) == "Hello.")
    }

    @Test func noSpaceAfterOpeningBracketOrBeforePunctuation() {
        #expect(NotesSpacing.fit("note", into: "(", at: 1) == "note")
        #expect(NotesSpacing.fit(", then more", into: "first", at: 5) == ", then more")
    }

    @Test func addsSpaceBeforeFollowingWord() {
        #expect(NotesSpacing.fit("new idea", into: "one two", at: 4) == "new idea ")
        #expect(NotesSpacing.fit("new idea", into: "onetwo", at: 3) == " new idea ")
    }

    @Test func noTrailingSpaceBeforePunctuationOrEnd() {
        #expect(NotesSpacing.fit("idea", into: "word.", at: 4) == " idea")
    }

    @Test func emptyTextStaysEmpty() {
        #expect(NotesSpacing.fit("", into: "word", at: 4) == "")
    }

    @Test func countsUTF16Offsets() {
        // "Mình" is 4 UTF-16 units; offset 4 is after it.
        #expect(NotesSpacing.fit("ổn", into: "Mình", at: 4) == " ổn")
    }
}
