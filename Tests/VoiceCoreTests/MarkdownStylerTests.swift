import Foundation
import Testing
@testable import VoiceCore

struct MarkdownStylerTests {
    /// Spans as (kind, covered text), easier to read than offsets.
    private func styled(_ text: String) -> [String] {
        let ns = text as NSString
        return MarkdownStyler.spans(in: text).map { span in
            "\(span.kind):\(ns.substring(with: NSRange(location: span.location, length: span.length)))"
        }
    }

    @Test func parsesLinePrefixes() {
        #expect(MarkdownLine.parse("## Next").kind == .heading(2))
        #expect(MarkdownLine.parse("## Next").content == "Next")
        #expect(MarkdownLine.parse("  - item").indent == "  ")
        #expect(MarkdownLine.parse("  - item").kind == .bullet)
        #expect(MarkdownLine.parse("- [x] done").kind == .task(checked: true))
        #expect(MarkdownLine.parse("* [ ] open").kind == .task(checked: false))
        #expect(MarkdownLine.parse("12. twelve").kind == .numbered)
        #expect(MarkdownLine.parse("> said").kind == .quote)
        #expect(MarkdownLine.parse("#tag only").kind == .plain)
        #expect(MarkdownLine.parse("  # not a heading").kind == .plain)
        #expect(MarkdownLine.parse("---").kind == .plain)
        let line = MarkdownLine.parse("\t- [ ] x")
        #expect(line.indent + line.prefix + line.content == "\t- [ ] x")
    }

    @Test func recognizesFencesAndRules() {
        #expect(MarkdownLine.isFence("```swift"))
        #expect(MarkdownLine.isFence("  ```"))
        #expect(!MarkdownLine.isFence("`code`"))
        #expect(MarkdownLine.isRule("---"))
        #expect(MarkdownLine.isRule("***"))
        #expect(!MarkdownLine.isRule("--"))
        #expect(!MarkdownLine.isRule("- - -x"))
    }

    @Test func headingMarksAndText() {
        #expect(styled("## Next") == ["mark:## ", "heading(2):Next"])
    }

    @Test func boldItalicStrikeAndCode() {
        #expect(styled("a **b** c") == ["mark:**", "bold:b", "mark:**"])
        #expect(styled("a _i_ and *j*") == ["mark:*", "italic:j", "mark:*", "mark:_", "italic:i", "mark:_"])
        #expect(styled("~~gone~~") == ["mark:~~", "strike:gone", "mark:~~"])
        #expect(styled("run `a **b**`") == ["mark:`", "code:a **b**", "mark:`"])
    }

    @Test func snakeCaseIsNotItalic() {
        #expect(styled("file_name_here") == [])
        #expect(styled("2 * 3 * 4") == [])
    }

    @Test func linkTextIsBlueAndTargetGrey() {
        #expect(styled("see [mockup](docs/a.html)") == ["mark:[", "link:mockup", "mark:](docs/a.html)"])
    }

    @Test func tasksQuotesAndLists() {
        #expect(styled("- [x] done") == ["mark:- [x] ", "doneTask:done"])
        #expect(styled("- [ ] open") == ["mark:- [ ] "])
        #expect(styled("> said") == ["mark:> ", "quote:said"])
        #expect(styled("  1. one") == ["mark:1. "])
    }

    @Test func fencedCodeIsNotParsedInside() {
        let text = "```\n**x**\n```\nafter **y**"
        #expect(styled(text) == [
            "codeBlock:```", "mark:```", "codeBlock:**x**", "codeBlock:```", "mark:```",
            "mark:**", "bold:y", "mark:**",
        ])
    }

    @Test func offsetsCountUTF16AcrossLines() {
        let text = "Việt 🚀\n**b**"
        let spans = MarkdownStyler.spans(in: text)
        #expect(spans.first == MarkdownSpan(.mark, 8, 2))
    }

    @Test func underlineTagsAreMarks() {
        #expect(styled("a <u>b c</u>") == ["mark:<u>", "underline:b c", "mark:</u>"])
    }

    @Test func tableLinesAreMonospacedWithGreyPipes() {
        let spans = styled("| A | **B** |\n| --- | --- |\n| c | d |\nend")
        #expect(spans.filter { $0.hasPrefix("table:") } == ["table:| A | **B** |", "table:| --- | --- |", "table:| c | d |"])
        #expect(spans.contains("mark:| --- | --- |"))
        #expect(spans.filter { $0 == "mark:|" }.count == 6)
        #expect(spans.contains("bold:B"))
        #expect(!spans.contains { $0.hasSuffix("end") })
    }
}
