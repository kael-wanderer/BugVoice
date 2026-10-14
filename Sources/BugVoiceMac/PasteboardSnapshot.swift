import AppKit

/// Every item and every type on a pasteboard, copied as data so it can be put
/// back after a paste (images, file URLs, rich text, not only strings).
public struct PasteboardSnapshot: @unchecked Sendable {
    let items: [[(NSPasteboard.PasteboardType, Data)]]

    public var isEmpty: Bool { items.isEmpty }

    @MainActor
    public static func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        return PasteboardSnapshot(items: items.filter { !$0.isEmpty })
    }

    @MainActor
    public func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { pairs -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in pairs { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
