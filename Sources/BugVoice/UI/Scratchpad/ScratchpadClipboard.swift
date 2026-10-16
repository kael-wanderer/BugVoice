import AppKit
import VoiceCore

/// Copy from the Scratchpad window: formatted text (HTML and RTF) for apps
/// that keep formatting, plain text for the rest.
@MainActor
enum ScratchpadClipboard {
    /// False when the pasteboard refused the text.
    @discardableResult
    static func copyFormatted(_ markdown: String) -> Bool {
        let html = MarkdownHTML.document(markdown)
        let plain = MarkdownPlainText.convert(markdown)
        let item = NSPasteboardItem()
        var ok = item.setString(html, forType: .html)
        if let rtf = rtf(fromHTML: html) { ok = item.setData(rtf, forType: .rtf) && ok }
        ok = item.setString(plain, forType: .string) && ok
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([item]) && ok
    }

    @discardableResult
    static func copyText(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    static func rtf(fromHTML html: String) -> Data? {
        guard let attributed = try? NSAttributedString(
            data: Data(html.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil)
        else { return nil }
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
}
