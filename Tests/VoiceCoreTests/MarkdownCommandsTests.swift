import Foundation
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

    @Test func underlineWrapsUnwrapsAndInsertsPair() {
        let wrap = MarkdownCommands.toggleUnderline(in: "a word b", selection: range(2, 4))
        #expect(wrap.applied(to: "a word b") == "a <u>word</u> b")
        #expect(wrap.selection == range(5, 4))
        let outside = MarkdownCommands.toggleUnderline(in: "a <u>word</u> b", selection: range(5, 4))
        #expect(outside.applied(to: "a <u>word</u> b") == "a word b")
        #expect(outside.selection == range(2, 4))
        let inside = MarkdownCommands.toggleUnderline(in: "a <u>word</u> b", selection: range(2, 11))
        #expect(inside.applied(to: "a <u>word</u> b") == "a word b")
        #expect(inside.selection == range(2, 4))
        let empty = MarkdownCommands.toggleUnderline(in: "ab", selection: range(1, 0))
        #expect(empty.applied(to: "ab") == "a<u></u>b")
        #expect(empty.selection == range(4, 0))
    }

    @Test func underlineCountsUTF16() {
        let text = "Việt 😀 x"
        let edit = MarkdownCommands.toggleUnderline(in: text, selection: range(5, 2))
        #expect(edit.applied(to: text) == "Việt <u>😀</u> x")
    }

    @Test func indentOnlyTouchesListLines() {
        let text = "- a\nplain\n1. b\n- [ ] c"
        let edit = MarkdownCommands.indent(in: text, selection: range(0, (text as NSString).length), outdent: false)
        #expect(edit?.applied(to: text) == "  - a\nplain\n  1. b\n  - [ ] c")
        #expect(edit?.selection == range(0, 28))
    }

    @Test func indentMovesTheCaretWithItsLine() {
        let edit = MarkdownCommands.indent(in: "x\n- item", selection: range(5, 0), outdent: false)
        #expect(edit?.applied(to: "x\n- item") == "x\n  - item")
        #expect(edit?.selection == range(7, 0))
        let back = MarkdownCommands.indent(in: "x\n  - item", selection: range(7, 0), outdent: true)
        #expect(back?.applied(to: "x\n  - item") == "x\n- item")
        #expect(back?.selection == range(5, 0))
    }

    @Test func outdentRemovesAtMostTwoSpacesOrOneTab() {
        let text = "   - a\n\t- b\n- c"
        let edit = MarkdownCommands.indent(in: text, selection: range(0, (text as NSString).length), outdent: true)
        #expect(edit?.applied(to: text) == " - a\n- b\n- c")
    }

    @Test func indentReturnsNilWhenNothingChanges() {
        #expect(MarkdownCommands.indent(in: "plain", selection: range(2, 0), outdent: false) == nil)
        #expect(MarkdownCommands.indent(in: "- flush", selection: range(2, 0), outdent: true) == nil)
    }

    @Test func tableGoesAfterATextLineWithABlankLine() {
        let text = "Plan\nnext"
        let edit = MarkdownCommands.insertTable(columns: 3, rows: 2, in: text, selection: range(2, 0))
        #expect(edit.applied(to: text) == "Plan\n\n|  |  |  |\n| --- | --- | --- |\n|  |  |  |\n\nnext")
        #expect(edit.selection == range(8, 0))
    }

    @Test func tableFillsABlankLine() {
        let text = "a\n\nb"
        let edit = MarkdownCommands.insertTable(columns: 1, rows: 1, in: text, selection: range(2, 0))
        #expect(edit.applied(to: text) == "a\n|  |\n| --- |\n\nb")
        #expect(edit.selection == range(4, 0))
        let start = MarkdownCommands.insertTable(columns: 2, rows: 1, in: "", selection: range(0, 0))
        #expect(start.applied(to: "") == "|  |  |\n| --- | --- |")
        #expect(start.selection == range(2, 0))
    }

    @Test func tableSizeIsClamped() {
        let edit = MarkdownCommands.insertTable(columns: 20, rows: 0, in: "", selection: range(0, 0))
        let lines = edit.replacement.components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines[0] == "|" + String(repeating: "  |", count: 8))
    }
}
