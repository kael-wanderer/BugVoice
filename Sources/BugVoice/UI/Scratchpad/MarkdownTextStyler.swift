import AppKit
import VoiceCore

/// Draws the Markdown view: headings, emphasis and grey marks on top of the
/// plain text. Only attributes change; the characters never do.
@MainActor
enum MarkdownTextStyler {
    static func apply(to storage: NSTextStorage, style: MarkdownTextStyle) {
        let text = storage.string
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes(style.typingAttributes, range: whole)
        for span in MarkdownStyler.spans(in: text) {
            let range = NSRange(location: span.location, length: span.length)
            guard NSMaxRange(range) <= storage.length, range.length > 0 else { continue }
            switch span.kind {
            case .mark:
                storage.addAttribute(.foregroundColor, value: style.secondaryColor, range: range)
            case .heading(let level):
                let font: NSFont = switch level {
                case 1: style.titleFont
                case 2: style.headingFont
                default: style.subheadingFont
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
                    .font: style.codeFont,
                    .backgroundColor: style.codeBackground,
                ], range: range)
            case .quote:
                storage.addAttribute(.foregroundColor, value: style.secondaryColor, range: range)
                addTrait(.italicFontMask, to: storage, range: range)
            case .link:
                storage.addAttribute(.foregroundColor, value: style.accentColor, range: range)
            case .doneTask:
                storage.addAttributes([
                    .foregroundColor: style.secondaryColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                ], range: range)
            case .underline:
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .table:
                storage.addAttribute(.font, value: style.codeFont, range: range)
            }
        }
    }

    /// Bold inside a heading stays heading-sized: the trait is added to
    /// whatever font each run already has.
    private static func addTrait(_ trait: NSFontTraitMask, to storage: NSTextStorage, range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: run)
        }
    }
}

struct MarkdownTextStyle {
    let bodyFont: NSFont
    let codeFont: NSFont
    let titleFont: NSFont
    let headingFont: NSFont
    let subheadingFont: NSFont
    let textColor: NSColor
    let secondaryColor: NSColor
    let accentColor: NSColor
    let codeBackground: NSColor
    let lineHeightMultiple: CGFloat

    @MainActor init(appearance: AppearanceStore) {
        bodyFont = appearance.type.nsFont(.reading)
        codeFont = appearance.type.nsCodeFont(.body)
        titleFont = appearance.type.nsFont(.title2)
        headingFont = appearance.type.nsFont(.title3)
        subheadingFont = appearance.type.nsFont(.bodyStrong)
        textColor = appearance.theme.textNS
        secondaryColor = appearance.theme.secondaryTextNS
        accentColor = appearance.theme.accentNS
        codeBackground = appearance.theme.hoverNS
        lineHeightMultiple = appearance.lineSpacingMultiple
    }
    var typingAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = lineHeightMultiple
        return [.font: bodyFont, .foregroundColor: textColor, .paragraphStyle: paragraph]
    }
}
