import AppKit
import Testing
@testable import BugVoiceMac

@MainActor
struct PasteboardSnapshotTests {
    func scratch() -> NSPasteboard { NSPasteboard(name: .init("bugvoice-test-\(UUID().uuidString)")) }

    @Test func snapshotRestoresAllTypes() {
        let pb = scratch()
        let item = NSPasteboardItem()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        item.setData(png, forType: .png)
        item.setString("file:///tmp/a.txt", forType: .fileURL)
        item.setString("caption", forType: .string)
        pb.clearContents()
        pb.writeObjects([item])

        let snapshot = PasteboardSnapshot.capture(pb)
        pb.clearContents()
        pb.setString("dictated", forType: .string)
        snapshot.restore(to: pb)

        let restored = pb.pasteboardItems?.first
        #expect(restored?.data(forType: .png) == png)
        #expect(restored?.string(forType: .fileURL) == "file:///tmp/a.txt")
        #expect(restored?.string(forType: .string) == "caption")
    }

    @Test func restoreSkipsWhenClipboardChangedSincePaste() {
        let pb = scratch()
        pb.clearContents()
        pb.setString("previous", forType: .string)
        let snapshot = PasteboardSnapshot.capture(pb)
        pb.clearContents()
        pb.setString("dictated", forType: .string)
        let pasteChangeCount = pb.changeCount

        pb.clearContents()
        pb.setString("user copy", forType: .string)
        #expect(!snapshot.restore(to: pb, ifChangeCountIs: pasteChangeCount))
        #expect(pb.string(forType: .string) == "user copy")

        let unchanged = pb.changeCount
        #expect(snapshot.restore(to: pb, ifChangeCountIs: unchanged))
        #expect(pb.string(forType: .string) == "previous")
    }

    @Test func fulfillingDelayedDataKeepsChangeCount() {
        let pb = scratch()
        let provider = DelayedTextProvider(text: "dictated")
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        pb.writeObjects([item])
        let pasteChangeCount = pb.changeCount
        #expect(pb.string(forType: .string) == "dictated")
        #expect(provider.wasRequested)
        #expect(pb.changeCount == pasteChangeCount)
    }

    @Test func emptySnapshotClears() {
        let pb = scratch()
        pb.clearContents()
        let snapshot = PasteboardSnapshot.capture(pb)
        #expect(snapshot.isEmpty)
        pb.setString("x", forType: .string)
        snapshot.restore(to: pb)
        #expect(pb.string(forType: .string) == nil)
    }

    @Test func copyPutsPlainText() async {
        let pb = scratch()
        let inserter = PasteboardInserter(pasteboard: pb)
        await inserter.copy("xin chào")
        #expect(pb.string(forType: .string) == "xin chào")
    }
}
