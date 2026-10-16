import AppKit
import SwiftUI
import VoiceCore

/// The meeting window's notes editor. Right Option dictation finds it as the
/// first responder of the key meeting window.
final class MeetingNotesTextView: NSTextView {}

/// Markdown notes editor with its own undo, Markdown styling, and Tab /
/// Shift-Tab indent on list lines, like the Scratchpad editor.
struct MeetingNotesEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let editor = MeetingNotesTextView(frame: .zero)
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.font = MarkdownTextStyler.bodyFont
        editor.typingAttributes = [.font: MarkdownTextStyler.bodyFont, .foregroundColor: NSColor.labelColor]
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 10, height: 12)
        editor.string = text
        editor.setAccessibilityLabel("My notes")

        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        // A text view made with frame .zero stays 0 pt wide unless it grows with the scroll view.
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        // Fills the pane, so a click below the last line still lands in the editor.
        editor.autoresizingMask = [.width, .height]
        editor.textContainer?.widthTracksTextView = true
        scroll.documentView = editor
        context.coordinator.editor = editor
        context.coordinator.restyle()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let editor = scroll.documentView as? MeetingNotesTextView, editor.string != text else { return }
        let selection = editor.selectedRange()
        editor.string = text
        editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        context.coordinator.restyle()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var editor: MeetingNotesTextView?

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            text.wrappedValue = editor.string
            restyle()
        }

        func restyle() {
            guard let editor, let storage = editor.textStorage else { return }
            MarkdownTextStyler.apply(to: storage)
            editor.typingAttributes = [.font: MarkdownTextStyler.bodyFont, .foregroundColor: NSColor.labelColor]
        }

        /// Tab and Shift-Tab indent list lines; elsewhere Tab types a tab.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let outdent: Bool
            switch commandSelector {
            case #selector(NSResponder.insertTab(_:)): outdent = false
            case #selector(NSResponder.insertBacktab(_:)): outdent = true
            default: return false
            }
            let range = textView.selectedRange()
            guard let edit = MarkdownCommands.indent(
                in: textView.string, selection: NotesTextRange(location: range.location, length: range.length), outdent: outdent)
            else { return outdent }
            let target = NSRange(location: edit.range.location, length: edit.range.length)
            guard textView.shouldChangeText(in: target, replacementString: edit.replacement) else { return true }
            textView.textStorage?.replaceCharacters(in: target, with: edit.replacement)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: edit.selection.location, length: edit.selection.length))
            return true
        }
    }
}
