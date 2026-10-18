import AppKit
import Observation
import SwiftUI
import VoiceCore

/// The meeting window's notes editor. Dictation finds it as the
/// first responder of the key meeting window.
final class MeetingNotesTextView: NSTextView {}

/// Markdown notes editor with its own undo, Markdown styling, and Tab /
/// Shift-Tab indent on list lines, like the Scratchpad editor.
struct MeetingNotesEditor: NSViewRepresentable {
    @Environment(AppearanceStore.self) private var appearance
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, appearance: appearance) }

    func makeNSView(context: Context) -> NSScrollView {
        let editor = MeetingNotesTextView(frame: .zero)
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.font = appearance.type.nsFont(.reading)
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: LayoutTokens.spacing[1], height: LayoutTokens.spacing[2])
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
        context.coordinator.observeAppearance()
        context.coordinator.observeFrame()
        context.coordinator.restyle()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.restyle()
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
        let appearance: AppearanceStore
        weak var editor: MeetingNotesTextView?
        nonisolated(unsafe) private var frameObserver: NSObjectProtocol?

        init(text: Binding<String>, appearance: AppearanceStore) { self.text = text; self.appearance = appearance }

        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            text.wrappedValue = editor.string
            restyle()
        }

        func observeAppearance() {
            withObservationTracking {
                _ = appearance.settings
                _ = appearance.systemIsDark
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.restyle()
                    self?.observeAppearance()
                }
            }
        }

        func restyle() {
            guard let editor, let storage = editor.textStorage else { return }
            let style = MarkdownTextStyle(appearance: appearance)
            editor.backgroundColor = appearance.theme.backgroundNS
            editor.drawsBackground = true
            editor.insertionPointColor = appearance.theme.textNS
            editor.textColor = style.textColor
            MarkdownTextStyler.apply(to: storage, style: style)
            editor.typingAttributes = style.typingAttributes
            updateInset()
        }

        /// Centers the text at the reading width; runs again when the editor resizes.
        func updateInset() {
            guard let editor else { return }
            let inset = NSSize(
                width: max(LayoutTokens.spacing[1], (editor.bounds.width - appearance.readingWidth) / 2),
                height: LayoutTokens.spacing[2])
            if editor.textContainerInset != inset { editor.textContainerInset = inset }
        }

        func observeFrame() {
            guard let editor, frameObserver == nil else { return }
            editor.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: editor, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateInset() }
            }
        }

        deinit {
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
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
