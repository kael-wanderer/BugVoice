import AppKit

@MainActor
public final class SelectionCapture {
    private let pasteboard: NSPasteboard
    private let postCopy: @MainActor () -> Void
    public var timeout: Duration = .milliseconds(300)

    public init(pasteboard: NSPasteboard = .general, postCopy: @escaping @MainActor () -> Void = SelectionCapture.postCommandC) {
        self.pasteboard = pasteboard
        self.postCopy = postCopy
    }

    public func capture(axSelection: String?) async -> String? {
        if let axSelection, !axSelection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return axSelection }
        let saved = PasteboardSnapshot.capture(pasteboard)
        defer { saved.restore(to: pasteboard) }
        let changeCount = pasteboard.changeCount
        postCopy()
        let deadline = ContinuousClock.now + timeout
        while pasteboard.changeCount == changeCount, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard !Task.isCancelled, pasteboard.changeCount != changeCount,
              let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    public static func postCommandC() {
        PasteboardInserter.makeKeyEvent(keyCode: 8, keyDown: true, flags: .maskCommand)?.post(tap: .cghidEventTap)
        PasteboardInserter.makeKeyEvent(keyCode: 8, keyDown: false, flags: .maskCommand)?.post(tap: .cghidEventTap)
    }
}
