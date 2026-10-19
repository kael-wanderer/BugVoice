import Foundation
import Testing
@testable import VoiceCore

struct FixLastTests {
    @Test func otherLanguage() {
        #expect(FixLast.otherLanguage(of: "en") == .vi)
        #expect(FixLast.otherLanguage(of: "vi") == .en)
        #expect(FixLast.otherLanguage(of: nil) == .en)
        #expect(FixLast.otherLanguage(of: "zh") == .en)
    }

    @Test func replaceCountsGraphemes() {
        var guarder = ReplacementGuard()
        let now = Date()
        guarder.recordInsertion(LastInsertion(text: "Xin chào", processID: 1, at: now))
        #expect(guarder.decide(now: now, frontProcessID: 1, sameFocus: true) == .replace(backspaces: 8))
    }

    @Test func typingBlocks() {
        var guarder = makeGuard("hello")
        guarder.keyTyped()
        #expect(guarder.decide(now: Date(), frontProcessID: 1, sameFocus: true) == .copyOnly)
    }

    @Test func recordClearsTyping() {
        var guarder = makeGuard("hello")
        guarder.keyTyped()
        guarder.recordInsertion(LastInsertion(text: "again", processID: 1, at: Date()))
        #expect(guarder.decide(now: Date(), frontProcessID: 1, sameFocus: true) == .replace(backspaces: 5))
    }

    @Test func otherAppBlocks() {
        let now = Date()
        let guarder = makeGuard("hello", at: now)
        #expect(guarder.decide(now: now, frontProcessID: 2, sameFocus: true) == .copyOnly)
        #expect(guarder.decide(now: now, frontProcessID: 1, sameFocus: false) == .copyOnly)
    }

    @Test func oldPasteBlocks() {
        let now = Date()
        let guarder = makeGuard("hello", at: now)
        #expect(guarder.decide(now: now.addingTimeInterval(120), frontProcessID: 1, sameFocus: true) == .copyOnly)
        #expect(guarder.decide(now: now.addingTimeInterval(119), frontProcessID: 1, sameFocus: true) == .replace(backspaces: 5))
    }

    @Test func multiLineIsCopied() {
        let now = Date()
        var guarder = makeGuard("a\nb", at: now)
        #expect(guarder.decide(now: now, frontProcessID: 1, sameFocus: true) == .copyOnly)
        guarder.recordInsertion(LastInsertion(text: String(repeating: "x", count: 501), processID: 1, at: now))
        #expect(guarder.decide(now: now, frontProcessID: 1, sameFocus: true) == .copyOnly)
        guarder.recordInsertion(LastInsertion(text: String(repeating: "x", count: 500), processID: 1, at: now))
        #expect(guarder.decide(now: now, frontProcessID: 1, sameFocus: true) == .replace(backspaces: 500))
    }

    @Test func nothingRecorded() {
        #expect(ReplacementGuard().decide(now: Date(), frontProcessID: 1, sameFocus: true) == nil)
    }

    @Test func countsAsTyping() {
        let control: UInt64 = 0x0004_0000
        let option: UInt64 = 0x0008_0000
        #expect(FixLast.countsAsTyping(keyCode: 0, flags: 0, userData: 0, shortcutKeyCodes: [15, 37, 9]))
        #expect(!FixLast.countsAsTyping(keyCode: 15, flags: control | option, userData: 0, shortcutKeyCodes: [15, 37, 9]))
        #expect(FixLast.countsAsTyping(keyCode: 0, flags: control | option, userData: 0, shortcutKeyCodes: [15, 37, 9]))
        #expect(FixLast.countsAsTyping(keyCode: 6, flags: 0x0010_0000, userData: 0, shortcutKeyCodes: [15, 37, 9]))
        #expect(!FixLast.countsAsTyping(keyCode: 51, flags: 0, userData: FixLast.syntheticEventMarker, shortcutKeyCodes: []))
    }

    private func makeGuard(_ text: String, at: Date = Date()) -> ReplacementGuard {
        var guarder = ReplacementGuard()
        guarder.recordInsertion(LastInsertion(text: text, processID: 1, at: at))
        return guarder
    }
}

extension FixLastTests {
    @Test func selectBackAllowsNewlines() {
        #expect(makeGuard("a\nb").decideSelectBack(now: Date(), frontProcessID: 1, sameFocus: true) == .selectBack(characters: 3))
    }
    @Test func selectBackLimit() {
        #expect(makeGuard(String(repeating: "a", count: 2001)).decideSelectBack(now: Date(), frontProcessID: 1, sameFocus: true) == .copyOnly)
        #expect(makeGuard(String(repeating: "a", count: 2000)).decideSelectBack(now: Date(), frontProcessID: 1, sameFocus: true) == .selectBack(characters: 2000))
    }
    @Test func selectBackTypingBlocks() {
        var g = makeGuard("hello")
        g.keyTyped()
        #expect(g.decideSelectBack(now: Date(), frontProcessID: 1, sameFocus: true) == .copyOnly)
    }
}
