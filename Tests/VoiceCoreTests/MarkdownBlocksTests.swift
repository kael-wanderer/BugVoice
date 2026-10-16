import Testing
@testable import VoiceCore

struct MarkdownBlocksTests {
    @Test func parsesEveryBlockKind() {
        let text = """
        ## Idea
        First line
        second line

        - one
          - nested
        3. three
        - [x] done
        - [ ] open
        > quoted
        > more
        ---
        ```
        let a = 1

        ```
        """
        #expect(MarkdownBlocks.parse(text) == [
            .heading(level: 2, text: "Idea"),
            .paragraph("First line\nsecond line"),
            .bullet(indent: 0, text: "one"),
            .bullet(indent: 1, text: "nested"),
            .numbered(indent: 0, number: "3.", text: "three"),
            .task(indent: 0, checked: true, text: "done", line: 7),
            .task(indent: 0, checked: false, text: "open", line: 8),
            .quote("quoted\nmore"),
            .rule,
            .code("let a = 1\n"),
        ])
    }

    @Test func unclosedFenceKeepsItsLines() {
        #expect(MarkdownBlocks.parse("```\nx") == [.code("x")])
    }

    @Test func emptyTextHasNoBlocks() {
        #expect(MarkdownBlocks.parse("").isEmpty)
        #expect(MarkdownBlocks.parse("\n\n").isEmpty)
    }

    @Test func plainTextRemovesMarks() {
        let text = "# Title\nSee **bold**, _it_, ~~old~~, `code` and [site](https://a.b).\n> quote\n- [ ] task\n```\n**raw**\n```"
        #expect(MarkdownPlainText.convert(text) == "Title\nSee bold, it, old, code and site (https://a.b).\nquote\n- [ ] task\n**raw**")
    }
}
