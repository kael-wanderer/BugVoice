import AppKit
import Testing
import VoiceCore
@testable import BugVoiceMac

@MainActor
struct SelectionCaptureTests {
    func board() -> NSPasteboard { NSPasteboard(name: .init("bv-command-\(UUID().uuidString)")) }
    @Test func axSelectionWins() async {
        let p = board()
        defer { p.releaseGlobally() }
        var called = false
        let capture = SelectionCapture(pasteboard: p, postCopy: { called = true })
        #expect(await capture.capture(axSelection: "abc") == "abc")
        #expect(!called)
    }
    @Test func fallbackReadsCopiedText() async {
        let p = board()
        defer { p.releaseGlobally() }
        p.setString("old", forType: .string)
        let capture = SelectionCapture(pasteboard: p, postCopy: { p.clearContents(); p.setString("picked", forType: .string) })
        #expect(await capture.capture(axSelection: nil) == "picked")
        #expect(p.string(forType: .string) == "old")
    }
    @Test func fallbackRestoresClipboard() async {
        let p = board()
        defer { p.releaseGlobally() }
        let custom = NSPasteboard.PasteboardType("com.bugvoice.test")
        let item = NSPasteboardItem()
        item.setString("old", forType: .string)
        item.setData(Data([1, 2, 3]), forType: custom)
        p.writeObjects([item])
        let capture = SelectionCapture(pasteboard: p, postCopy: { p.clearContents(); p.setString("picked", forType: .string) })
        #expect(await capture.capture(axSelection: nil) == "picked")
        #expect(p.string(forType: .string) == "old")
        #expect(p.data(forType: custom) == Data([1, 2, 3]))
    }
    @Test func emptyReadableSelectionSkipsCopy() async {
        // Editors such as VS Code copy the whole line on ⌘C with nothing selected.
        let p = board()
        defer { p.releaseGlobally() }
        var called = false
        let capture = SelectionCapture(pasteboard: p, postCopy: { called = true })
        #expect(await capture.capture(axSelection: "") == nil)
        #expect(await capture.capture(axSelection: " \n") == nil)
        #expect(!called)
    }
    @Test func noChangeMeansNoSelection() async {
        let p = board()
        defer { p.releaseGlobally() }
        p.setString("old", forType: .string)
        let capture = SelectionCapture(pasteboard: p, postCopy: {})
        capture.timeout = .milliseconds(50)
        #expect(await capture.capture(axSelection: nil) == nil)
        #expect(p.string(forType: .string) == "old")
    }
    @Test func markedEvents() {
        let event = PasteboardInserter.makeKeyEvent(keyCode: 123, keyDown: true, flags: .maskShift)
        #expect(event?.getIntegerValueField(.eventSourceUserData) == FixLast.syntheticEventMarker)
    }
}
