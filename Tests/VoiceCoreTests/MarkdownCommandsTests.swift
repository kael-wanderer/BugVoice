import Testing
@testable import VoiceCore

struct MarkdownCommandsTests {
    private func range(_ location: Int, _ length: Int) -> NotesTextRange {
        NotesTextRange(location: location, length: length)
    }

    @Test func boldWrapsAndKeepsInnerSelected() {
        let edit = MarkdownCommands.toggleInline(.bold, in: "a word b", selection: range(2, 4))
        #expect(edit.applied(to: "a word b") == "a **word** b")
        #expect(edit.selection == range(4, 4))
    }

    @Test func boldUnwrapsMarksOutsideOrInsideSelection() {
        let outside = MarkdownCommands.toggleInline(.bold, in: "a **word** b", selection: range(4, 4))
        #expect(outside.applied(to: "a **word** b") == "a word b")
        #expect(outside.selection == range(2, 4))
        let inside = MarkdownCommands.toggleInline(.bold, in: "a **word** b", selection: range(2, 8))
        #expect(inside.applied(to: "a **word** b") == "a word b")
        #expect(inside.selection == range(2, 4))
    }

    @Test func emptySelectionInsertsPairWithCaretBetween() {
        let edit = MarkdownCommands.toggleInline(.strike, in: "ab", selection: range(1, 0))
        #expect(edit.applied(to: "ab") == "a~~~~b")
        #expect(edit.selection == range(3, 0))
    }

    @Test func codeOnSeveralLinesMakesAFence() {
        let text = "x\ny\nz"
        let edit = MarkdownCommands.toggleInline(.code, in: text, selection: range(0, 3))
        #expect(edit.applied(to: text) == "```\nx\ny\n```\nz")
        let back = MarkdownCommands.toggleInline(.code, in: "```\nx\ny\n```\nz", selection: range(0, 11))
        #expect(back.applied(to: "```\nx\ny\n```\nz") == "x\ny\nz")
    }

    @Test func linkSelectsTextOrURL() {
        let empty = MarkdownCommands.insertLink(in: "", selection: range(0, 0))
        #expect(empty.replacement == "[text](https://)")
        #expect(empty.selection == range(1, 4))
        let word = MarkdownCommands.insertLink(in: "see site", selection: range(4, 4))
        #expect(word.applied(to: "see site") == "see [site](https://)")
        #expect(word.selection == range(11, 8))
    }

    @Test func headingTogglesAndReplacesOtherPrefixes() {
        let set = MarkdownCommands.toggleLineFormat(.heading(1), in: "- Plan", selection: range(3, 0))
        #expect(set.applied(to: "- Plan") == "# Plan")
        #expect(set.selection == range(6, 0))
        let off = MarkdownCommands.toggleLineFormat(.heading(1), in: "# Plan", selection: range(2, 0))
        #expect(off.applied(to: "# Plan") == "Plan")
        let swap = MarkdownCommands.toggleLineFormat(.heading(2), in: "# Plan", selection: range(2, 0))
        #expect(swap.applied(to: "# Plan") == "## Plan")
    }

    @Test func numberedListCountsTouchedLinesAndSkipsBlanks() {
        let text = "a\n\nb\nc"
        let edit = MarkdownCommands.toggleLineFormat(.numbered, in: text, selection: range(0, 6))
        #expect(edit.applied(to: text) == "1. a\n\n2. b\n3. c")
        #expect(edit.selection == range(0, 15))
    }

    @Test func bulletRemovesWhenEveryLineHasIt() {
        let text = "- a\n  - b"
        let edit = MarkdownCommands.toggleLineFormat(.bullet, in: text, selection: range(0, 9))
        #expect(edit.applied(to: text) == "a\n  b")
    }

    @Test func checklistOnEmptyLineAddsPrefix() {
        let edit = MarkdownCommands.toggleLineFormat(.task, in: "", selection: range(0, 0))
        #expect(edit.applied(to: "") == "- [ ] ")
        #expect(edit.selection == range(6, 0))
    }

    @Test func selectionEndingAfterNewlineStaysOnItsLine() {
        let text = "a\nb"
        let edit = MarkdownCommands.toggleLineFormat(.quote, in: text, selection: range(0, 2))
        #expect(edit.applied(to: text) == "> a\nb")
    }

    @Test func toggleTaskTicksAndUnticks() {
        #expect(MarkdownCommands.toggleTask(in: "x\n- [ ] a", line: 1) == "x\n- [x] a")
        #expect(MarkdownCommands.toggleTask(in: "  - [X] a", line: 0) == "  - [ ] a")
        #expect(MarkdownCommands.toggleTask(in: "- a", line: 0) == nil)
        #expect(MarkdownCommands.toggleTask(in: "- a", line: 5) == nil)
    }

    @Test func insertBelowAddsBlankLineAfterInputLine() {
        let text = "one two\nnext"
        let mid = MarkdownCommands.insertBelow("NEW", in: text, after: 3)
        #expect(mid.applied(to: text) == "one two\n\nNEW\n\nnext")
        #expect(mid.selection == range(9, 3))
        let afterNewline = MarkdownCommands.insertBelow("NEW", in: text, after: 8)
        #expect(afterNewline.applied(to: text) == "one two\n\nNEW\n\nnext")
        let atEnd = MarkdownCommands.insertBelow("NEW", in: text, after: 12)
        #expect(atEnd.applied(to: text) == "one two\nnext\n\nNEW")
        #expect(MarkdownCommands.insertBelow("A", in: "", after: 0).applied(to: "") == "A")
    }
}
