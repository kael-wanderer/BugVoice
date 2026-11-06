import Testing
@testable import VoiceCore

@Suite struct TourTests {
    private func cards(meeting: String? = "⌃⌥M", pad: String? = "⌃⌥N") -> [TourCard] {
        Tour.cards(hotkey: "Right Control", meetingShortcut: meeting, scratchpadShortcut: pad)
    }

    @Test func sixStopsInSpecOrderWithExactCopy() {
        let c = cards()
        #expect(c.map(\.stop) == [.menuBar, .dictation, .recordMeeting, .scratchpad, .dictionary, .style])
        #expect(c.map(\.title) == ["BugVoice lives in the menu bar", "Dictate anywhere", "Record a meeting", "Scratchpad", "Your words", "Style"])
        #expect(c.map(\.body) == [
            "Click the BugVoice icon for status, quick actions and settings. The window can stay closed.",
            "Hold Right Control in any app, speak, let go. Everything you dictated is listed here.",
            "Record a call and get a transcript, summary and action items. Shortcut: ⌃⌥M.",
            "Speak into a note. ⌃⌥N opens a floating scratchpad from any app.",
            "Add names and terms so they come out right every time.",
            "Terminal, chat and email each get their own cleanup. Change how each one reads here.",
        ])
    }

    @Test func offShortcutsDropTheSentence() {
        let c = cards(meeting: nil, pad: nil)
        #expect(c[2].body == "Record a call and get a transcript, summary and action items.")
        #expect(c[3].body == "Speak into a note.")
    }

    @Test func visibleStopsKeepsOrderAndDropsHidden() {
        let c = cards()
        let v = Tour.visibleStops(c, onScreen: [.style, .dictation, .scratchpad])
        #expect(v.map(\.stop) == [.dictation, .scratchpad, .style])
        #expect(Tour.visibleStops(c, onScreen: []).isEmpty)
    }
}
