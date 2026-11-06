import AppKit
import SwiftUI
import VoiceCore

/// The Try it box. A class of its own so dictation can tell it has the keyboard.
final class TryItTextView: NSTextView {}

/// A plain text box that takes the keyboard when it appears, so the first
/// dictation pastes here (a normal ⌘V into BugVoice's own window).
private struct TryItTextBox: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let view = TryItTextView(frame: .zero)
        // Long text wraps to the box's width and scrolls down.
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.font = .systemFont(ofSize: NSFont.systemFontSize + 1)
        view.textContainerInset = NSSize(width: 6, height: 6)
        view.setAccessibilityLabel("Try dictation here")
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TryItTextBox
        init(_ parent: TryItTextBox) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

struct OnboardingTryItStep: View {
    @Bindable var model: AppModel
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                Text("Try it here").bvFont(.title1)
                Text("Click the box, hold \(model.settings.hotkey.spokenName), say a sentence, let go.")
                    .bvFont(.reading).foregroundStyle(.bvSecondary)
                Text("Try: \"Remind me to send the report to Lan before Friday, cảm ơn nhé.\"")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
            TryItTextBox(text: $text)
                .frame(minHeight: 90, maxHeight: 130)
            HStack(alignment: .firstTextBaseline) {
                status
                Spacer()
                Button("Try again") {
                    text = ""
                    model.lastTryItResult = nil
                }
                .disabled(text.isEmpty && model.lastTryItResult == nil)
            }
        }
        .onAppear {
            model.hotkeyProbe = nil
            model.lastTryItResult = nil
            model.tryItActive = true
        }
        .onDisappear { model.tryItActive = false }
    }

    @ViewBuilder private var status: some View {
        if let result = model.lastTryItResult {
            if let problem = result.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .bvFont(.footnote).foregroundStyle(.bvWarning)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Label("It works", systemImage: "checkmark.circle.fill").foregroundStyle(.bvSuccess)
                    Text(summary(result)).bvFont(.footnote).foregroundStyle(.bvSecondary)
                }
            }
        } else if case .downloading(let fraction) = model.speechState {
            Text("The speech model is still downloading, \(Int(fraction * 100))%. Dictation works when it finishes.")
                .bvFont(.footnote).foregroundStyle(.bvWarning)
        } else if case .failed(let message) = model.speechState {
            Text("The speech model is not ready: \(message)").bvFont(.footnote).foregroundStyle(.bvWarning)
        } else if model.speechState != .ready {
            Text("The speech model is getting ready. Dictation works when it finishes.")
                .bvFont(.footnote).foregroundStyle(.bvSecondary)
        } else {
            Text(" ").bvFont(.footnote)
        }
    }

    private func summary(_ result: TryItResult) -> String {
        var line = String(format: "Heard in %.1f s", result.speechSeconds)
        if let cleanup = result.cleanupSeconds {
            line += String(format: ", cleaned in %.1f s", cleanup)
            if let name = result.cleanupName { line += " by \(name)" }
        } else {
            line += ", no cleanup"
        }
        return line
    }
}
