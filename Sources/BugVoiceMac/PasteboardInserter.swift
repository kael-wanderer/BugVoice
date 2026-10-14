import AppKit
import Synchronization
import VoiceCore

/// Pastes by publishing the text as *delayed* pasteboard data and posting ⌘V.
/// The paste counts as consumed only if the target app actually asks for the
/// data. On success the previous clipboard is restored unless something else
/// wrote to it in the meantime; on failure the text
/// stays on the clipboard so the user can press ⌘V.
@MainActor
public final class PasteboardInserter: InsertionTarget {
    private let pasteboard: NSPasteboard
    public var restoreClipboard = true
    public var consumeTimeout: Double = 1.0
    public var restoreDelay: Double = 0.3

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func insert(_ text: String) async -> InsertOutcome {
        let saved = PasteboardSnapshot.capture(pasteboard)
        let provider = DelayedTextProvider(text: text)
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        pasteboard.writeObjects([item])
        let pasteChangeCount = pasteboard.changeCount

        Self.postCommandV()

        let deadline = Date().addingTimeInterval(consumeTimeout)
        while !provider.wasRequested, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        guard provider.wasRequested else {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .notConsumed
        }
        if restoreClipboard {
            try? await Task.sleep(for: .seconds(restoreDelay))
            saved.restore(to: pasteboard, ifChangeCountIs: pasteChangeCount)
        }
        return .pasted
    }

    public func copy(_ text: String) async {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// ⌘V with explicit flags, so a still-held hotkey modifier is not added.
    static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyV: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

final class DelayedTextProvider: NSObject, NSPasteboardItemDataProvider, Sendable {
    let text: String
    private let requested = Mutex(false)

    init(text: String) {
        self.text = text
    }

    var wasRequested: Bool { requested.withLock { $0 } }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        item.setString(text, forType: type)
        requested.withLock { $0 = true }
    }
}
