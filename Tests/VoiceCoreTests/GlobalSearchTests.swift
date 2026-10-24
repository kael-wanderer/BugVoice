import Foundation
import Testing
@testable import VoiceCore

@Suite struct GlobalSearchTests {
    private func passage(
        _ source: AskSource, part: AskPart, index: Int = 0, date: Date = Date(timeIntervalSince1970: 1),
        lines: [(String, String)]
    ) -> AskPassage {
        AskPassage(
            source: source, part: part, index: index, date: date,
            lines: lines.map { AskLine(id: $0.0, text: $0.1) })
    }

    private func dictation(_ text: String, id: UUID, date: Date = Date(timeIntervalSince1970: 1), app: String? = "Notes") -> HistoryEntry {
        HistoryEntry(
            id: id, startedAt: date, appName: app, bundleID: nil, style: .other,
            language: "en", raw: text, cleaned: nil, text: text, outcome: "inserted",
            rawReason: nil, timings: StageTimings(recording: 1))
    }

    @Test func emptyQueryGivesNothing() {
        #expect(GlobalSearch.search("  ", passages: [], titles: [], first: nil) == [])
    }

    @Test func oneHitPerMeetingFromBestPassage() {
        let meeting = MeetingID(rawValue: "meeting-1")
        let date = Date(timeIntervalSince1970: 10)
        let weaker = passage(.meeting(meeting), part: .transcript, index: 0, date: date, lines: [("line-a", "budget review")])
        let stronger = passage(.meeting(meeting), part: .transcript, index: 1, date: date, lines: [("line-b", "budget budget budget review")])
        let hits = GlobalSearch.search("budget", passages: [weaker, stronger], titles: [], first: nil)
        #expect(hits.count == 1)
        #expect(hits[0].target == .meeting(meeting, part: .transcript, lineID: "line-b"))
        #expect(hits[0].kind == .meeting)
    }

    @Test func oneHitPerDictationEntry() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let passages = AskPassageBuilder.passages(dictations: [
            dictation("budget review", id: firstID), dictation("budget plans", id: secondID),
        ])
        let hits = GlobalSearch.search("budget", passages: passages, titles: [], first: nil)
        #expect(hits.count == 2)
        #expect(Set(hits.compactMap { hit -> UUID? in
            guard case .dictation(let id) = hit.target else { return nil }
            return id
        }) == [firstID, secondID])
    }

    @Test func currentPageFirst() {
        let note = NoteID(rawValue: "note-1")
        let notePassage = passage(.note(note), part: .note, lines: [("body", "budget budget budget budget")])
        let entryID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let dictationPassage = AskPassageBuilder.passages(dictations: [dictation("budget", id: entryID)])[0]
        let hits = GlobalSearch.search("budget", passages: [notePassage, dictationPassage], titles: [], first: .dictation)
        #expect(hits.count == 2)
        #expect(hits[0].kind == .dictation)
        #expect(hits[1].kind == .note)
        #expect(hits[1].score > hits[0].score)
    }

    @Test func titleMatchAddsScore() {
        let noteA = NoteID(rawValue: "note-a")
        let noteB = NoteID(rawValue: "note-b")
        let date = Date(timeIntervalSince1970: 20)
        let bodyB = passage(.note(noteB), part: .note, date: date, lines: [("body-b", "The budget is mentioned once")])
        let titleA = SearchTitle(source: .note(noteA), title: "Budget plan", date: date)
        let hits = GlobalSearch.search("budget", passages: [bodyB], titles: [titleA], first: nil)
        #expect(hits.count == 2)
        #expect(hits[0].target == .note(noteA))
        #expect(hits[1].target == .note(noteB))
        #expect(hits[0].score > hits[1].score)
    }

    @Test func unfinishedMeetingMatchesByTitle() {
        let meeting = MeetingID(rawValue: "unfinished")
        let title = SearchTitle(source: .meeting(meeting), title: "Weekly sync", date: Date(timeIntervalSince1970: 30))
        let hits = GlobalSearch.search("week", passages: [], titles: [title], first: nil)
        #expect(hits.count == 1)
        #expect(hits[0].target == .meeting(meeting, part: nil, lineID: nil))
        #expect(hits[0].snippet == "")
    }

    @Test func foldsDiacritics() {
        let meeting = MeetingID(rawValue: "vietnamese")
        let date = Date(timeIntervalSince1970: 40)
        let text = passage(.meeting(meeting), part: .transcript, date: date, lines: [("vi-line", "Tôi nói tiếng Việt")])
        let passageHits = GlobalSearch.search("tieng viet", passages: [text], titles: [], first: nil)
        #expect(passageHits.count == 1)
        #expect(passageHits[0].snippet.contains("tiếng Việt"))

        let title = SearchTitle(source: .note(NoteID(rawValue: "vi-note")), title: "Tiếng Việt notes", date: date)
        let titleHits = GlobalSearch.search("tiếng", passages: [], titles: [title], first: nil)
        #expect(titleHits.count == 1)
        #expect(titleHits[0].target == .note(NoteID(rawValue: "vi-note")))
    }

    @Test func settingsPrefixMatch() {
        let hits = GlobalSearch.search("text si", passages: [], titles: [], first: nil)
        #expect(hits.first?.title == "Text size")
        #expect(hits.first?.target == .settings(section: "editing"))
    }

    @Test func settingsListIsExact() {
        #expect(GlobalSearch.settingsEntries.count == 25)
        #expect(GlobalSearch.settingsEntries.first == SettingsSearchEntry(label: "General", section: "general"))
        #expect(GlobalSearch.settingsEntries.last == SettingsSearchEntry(label: "Check for updates", section: "general"))
    }

    @Test func limitCutsAfterOrdering() {
        let entries = (1...12).map { count in
            dictation(String(repeating: "budget ", count: count), id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", count))!)
        }
        let hits = GlobalSearch.search("budget", passages: AskPassageBuilder.passages(dictations: entries), titles: [], first: nil, limit: 8)
        #expect(hits.count == 8)
        #expect(hits[0].target == .dictation(entries[11].id))
        #expect(hits[0].score > hits[7].score)
    }

    @Test func noteTitlePassageIsNotSnippet() {
        let note = NoteID(rawValue: "note-title")
        let date = Date(timeIntervalSince1970: 50)
        let title = passage(.note(note), part: .title, index: 0, date: date, lines: [("title", "Budget plan")])
        let body = passage(.note(note), part: .note, index: 0, date: date, lines: [("body", "The body budget details")])
        let hits = GlobalSearch.search("budget", passages: [title, body], titles: [], first: nil)
        #expect(hits.count == 1)
        #expect(hits[0].snippet == "The body budget details")
    }

    @Test func snippetCentersOnMatch() {
        let text = String(repeating: "a", count: 260) + " budget " + String(repeating: "b", count: 32)
        let snippet = GlobalSearch.snippet(text, query: "budget")
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.contains("budget"))
        #expect(snippet.count <= 92)
    }

    @Test func snippetShortTextUnchanged() {
        #expect(GlobalSearch.snippet("lunch  plans\n today", query: "plans") == "lunch plans today")
    }
}
