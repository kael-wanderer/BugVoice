import AppKit
import CoreGraphics
import Testing
import VoiceCore
@testable import BugVoiceMac

struct PasteboardInserterTests {
    @MainActor @Test func syntheticEventsDoNotCountAsTyping() throws {
        let events = [
            try #require(PasteboardInserter.makeKeyEvent(keyCode: 9, keyDown: true, flags: .maskCommand)),
            try #require(PasteboardInserter.makeKeyEvent(keyCode: 9, keyDown: false, flags: .maskCommand)),
            try #require(PasteboardInserter.makeKeyEvent(keyCode: 51, keyDown: true, flags: [])),
            try #require(PasteboardInserter.makeKeyEvent(keyCode: 51, keyDown: false, flags: [])),
        ]
        for event in events {
            #expect(event.getIntegerValueField(.eventSourceUserData) == FixLast.syntheticEventMarker)
        }
    }
}
