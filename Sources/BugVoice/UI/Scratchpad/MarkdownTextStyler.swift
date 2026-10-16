import AppKit
import VoiceCore

/// Draws the Markdown view: headings, emphasis and grey marks on top of the
/// plain text. Only attributes change; the characters never do.
@MainActor
enum MarkdownTextStyler {
    static let bodySize: CGFloat = 14
    static let codeSize: CGFloat = 13
    static var bodyFont: NSFont { .systemFont(ofSize: bodySize) }
    static var codeBackground: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.12) }

    static func apply(to storage: NSTextStorage) {
        let text = storage.string
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes([.font: bodyFont, .foregroundColor: NSColor.labelColor], range: whole)
        for span in MarkdownStyler.spans(in: text) {
            let range = NSRange(location: span.location, length: span.length)
            guard NSMaxRange(range) <= storage.length, range.length > 0 else { continue }
            switch span.kind {
            case .mark:
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            case .heading(let level):
                let font: NSFont = switch level {
                case 1: .systemFont(ofSize: 20, weight: .bold)
                case 2: .systemFont(ofSize: 17, weight: .bold)
                default: .systemFont(ofSize: 15, weight: .semibold)
                }
                storage.addAttribute(.font, value: font, range: range)
            case .bold:
                addTrait(.boldFontMask, to: storage, range: range)
            case .italic:
                addTrait(.italicFontMask, to: storage, range: range)
            case .strike:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .code, .codeBlock:
                storage.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: codeSize, weight: .regular),
                    .backgroundColor: codeBackground,
                ], range: range)
            case .quote:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                addTrait(.italicFontMask, to: storage, range: range)
            case .link:
                storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
            case .doneTask:
                storage.addAttributes([
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                ], range: range)
            case .underline:
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .table:
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: codeSize, weight: .regular), range: range)
            }
        }
    }

    /// Bold inside a heading stays heading-sized: the trait is added to
    /// whatever font each run already has.
    private static func addTrait(_ trait: NSFontTraitMask, to storage: NSTextStorage, range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            let font = (value as? NSFont) ?? bodyFont
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: run)
        }
    }
}
