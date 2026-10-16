import Testing
@testable import VoiceCore

struct MarkdownHTMLTests {
    @Test func blocks() {
        let text = "# Title\nLine one\nline two\n\n> said\n---\n```\n<b>\n```"
        #expect(MarkdownHTML.render(text) ==
            "<h1>Title</h1><p>Line one<br>line two</p><blockquote><p>said</p></blockquote><hr><pre><code>&lt;b&gt;</code></pre>")
    }

    @Test func inlineMarks() {
        let text = "**b** _i_ *j* ~~s~~ <u>u</u> `**c**` [site](https://a.b?x=1&y=2)"
        #expect(MarkdownHTML.render(text) ==
            "<p><strong>b</strong> <em>i</em> <em>j</em> <s>s</s> <u>u</u> <code>**c**</code> <a href=\"https://a.b?x=1&amp;y=2\">site</a></p>")
    }

    @Test func textIsEscapedAndOnlySafeLinksStay() {
        #expect(MarkdownHTML.render("a < b & \"c\" <script>") == "<p>a &lt; b &amp; &quot;c&quot; &lt;script&gt;</p>")
        #expect(MarkdownHTML.render("[x](javascript:alert(1)) [m](mailto:a@b.c) [r](notes/a.md)") ==
            "<p>x) <a href=\"mailto:a@b.c\">m</a> r</p>")
    }

    @Test func nestedListsAndTasks() {
        let text = "- a\n  - b\n- [x] c\n1. d\n2. e\npara"
        #expect(MarkdownHTML.render(text) ==
            "<ul><li>a<ul><li>b</li></ul></li><li>☑ c</li></ul><ol><li>d</li><li>e</li></ol><p>para</p>")
    }

    @Test func deepIndentWithoutParentNestsOneLevel() {
        #expect(MarkdownHTML.render("    - deep") == "<ul><li>deep</li></ul>")
    }

    @Test func table() {
        let text = "| A | **B** |\n| --- | --- |\n| 1 | 2 |"
        #expect(MarkdownHTML.render(text) ==
            "<table><thead><tr><th>A</th><th><strong>B</strong></th></tr></thead><tbody><tr><td>1</td><td>2</td></tr></tbody></table>")
    }

    @Test func documentWrapsWithCharset() {
        #expect(MarkdownHTML.document("x") == "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body><p>x</p></body></html>")
    }
}
