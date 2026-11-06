import Foundation

/// The six stops of the main-window tour, in order.
public enum TourStop: String, CaseIterable, Sendable {
    case menuBar, dictation, recordMeeting, scratchpad, dictionary, style
}

public struct TourCard: Equatable, Sendable {
    public let stop: TourStop
    public let title: String
    public let body: String
}

public enum Tour {
    /// The cards in tour order. A nil shortcut (off) drops its sentence.
    public static func cards(hotkey: String, meetingShortcut: String?, scratchpadShortcut: String?) -> [TourCard] {
        let meeting = "Record a call and get a transcript, summary and action items."
            + (meetingShortcut.map { " Shortcut: \($0)." } ?? "")
        let scratchpad = scratchpadShortcut.map { "Speak into a note. \($0) opens a floating scratchpad from any app." }
            ?? "Speak into a note."
        return [
            TourCard(stop: .menuBar, title: "BugVoice lives in the menu bar",
                     body: "Click the BugVoice icon for status, quick actions and settings. The window can stay closed."),
            TourCard(stop: .dictation, title: "Dictate anywhere",
                     body: "Hold \(hotkey) in any app, speak, let go. Everything you dictated is listed here."),
            TourCard(stop: .recordMeeting, title: "Record a meeting", body: meeting),
            TourCard(stop: .scratchpad, title: "Scratchpad", body: scratchpad),
            TourCard(stop: .dictionary, title: "Your words",
                     body: "Add names and terms so they come out right every time."),
            TourCard(stop: .style, title: "Style",
                     body: "Terminal, chat and email each get their own cleanup. Change how each one reads here."),
        ]
    }

    /// The cards whose target is on screen, in the same order.
    public static func visibleStops(_ cards: [TourCard], onScreen: Set<TourStop>) -> [TourCard] {
        cards.filter { onScreen.contains($0.stop) }
    }
}
