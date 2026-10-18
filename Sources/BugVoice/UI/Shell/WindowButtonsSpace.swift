import AppKit
import SwiftUI
import VoiceCore

struct WindowButtonsSpace: View {
    @State private var size: CGSize = .zero
    var body: some View {
        Color.clear.frame(width: size.width, height: size.height)
            .background(ButtonFrameReader(size: $size))
            .accessibilityHidden(true)
    }
}

private struct ButtonFrameReader: NSViewRepresentable {
    @Binding var size: CGSize
    func makeNSView(context: Context) -> Reader {
        let view = Reader()
        view.changed = { value in
            DispatchQueue.main.async { if size != value { size = value } }
        }
        return view
    }
    func updateNSView(_ view: Reader, context: Context) { view.measure() }
    final class Reader: NSView {
        var changed: ((CGSize) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); measure() }
        func measure() {
            guard let window, let button = window.standardWindowButton(.zoomButton), let parent = button.superview,
                  let content = window.contentView else { return }
            let frame = parent.convert(button.frame, to: content)
            changed?(CGSize(width: frame.maxX + LayoutTokens.spacing[1], height: content.bounds.maxY - frame.minY + LayoutTokens.spacing[1]))
        }
    }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) }
            else { window?.performDrag(with: event) }
        }
    }
}
