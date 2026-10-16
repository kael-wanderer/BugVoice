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

    @Test func tableWithHeaderSeparatorAndRows() {
        let text = "Intro\n| Item | Owner |\n| --- | :-: |\n| Icons | Linh |\n| Copy |\n| a | b | c |\nafter"
        #expect(MarkdownBlocks.parse(text) == [
            .paragraph("Intro"),
            .table(header: ["Item", "Owner"], rows: [["Icons", "Linh"], ["Copy", ""], ["a", "b"]]),
            .paragraph("after"),
        ])
    }

    @Test func pipeLinesWithoutASeparatorStayParagraphs() {
        #expect(MarkdownBlocks.parse("| a | b |\n| c | d |") == [.paragraph("| a | b |\n| c | d |")])
        #expect(MarkdownBlocks.parse("| --- |") == [.paragraph("| --- |")])
    }

    @Test func tableInsideAFenceIsCode() {
        #expect(MarkdownBlocks.parse("```\n| a |\n| --- |\n```") == [.code("| a |\n| --- |")])
    }

    @Test func emptyTableFromTheToolbarParses() {
        #expect(MarkdownBlocks.parse("|  |  |\n| --- | --- |\n|  |  |") == [.table(header: ["", ""], rows: [["", ""]])])
    }

    @Test func plainTextDropsUnderlineTagsAndFlattensTables() {
        let text = "<u>Key</u> point\n| Item | **Owner** |\n| --- | --- |\n| Icons | Linh |"
        #expect(MarkdownPlainText.convert(text) == "Key point\nItem | Owner\nIcons | Linh")
    }
}
