import Foundation
import Testing
@testable import VoiceCore

struct NoteAIChangeTests {
    private let note = NoteID(rawValue: "n1")

    @Test func titlesAndNotices() {
        #expect(NoteAIChangeKind.transform(.polish).historyTitle == "Before Polish")
        #expect(NoteAIChangeKind.instruction("shorter,\n add a  greeting").historyTitle == "Before “shorter, add a greeting”")
        let long = String(repeating: "a", count: 45)
        #expect(NoteAIChangeKind.instruction(long).historyTitle == "Before “\(String(repeating: "a", count: 40))…”")
        #expect(NoteAIChangeKind.transform(.casual).notice(words: 28) == "Made more casual · 28 words")
        #expect(NoteAIChangeKind.instruction("x").notice(words: 3) == "Changed · 3 words")
        #expect(NoteAIChangeKind.transform(.polish).notice(words: 1) == "Polished · 1 word")
        #expect(NoteAIHistoryEntry(title: "t", body: "one", date: Date()).wordsLabel == "1 word")
        #expect(NoteAIHistoryEntry(title: "t", body: "one two", date: Date()).wordsLabel == "2 words")
    }

    @Test func runAgainOnlyWhileTheNoteIsUnchanged() {
        let change = NoteAIChange(
            noteID: note, kind: .transform(.polish), original: "a", range: NotesTextRange(location: 0, length: 1), revision: 7)
        #expect(change.canRunAgain(noteID: note, revision: 7))
        #expect(!change.canRunAgain(noteID: note, revision: 8))
        #expect(!change.canRunAgain(noteID: NoteID(rawValue: "n2"), revision: 7))
    }

    @Test func historyIsPerNoteNewestFirstAndCapped() {
        var history = NoteAIHistory()
        for index in 0..<25 {
            history.add(NoteAIHistoryEntry(title: "t\(index)", body: "b \(index)", date: Date(timeIntervalSince1970: Double(index))), to: note)
        }
        history.add(NoteAIHistoryEntry(title: "other", body: "x", date: Date()), to: NoteID(rawValue: "n2"))
        let list = history.entries(for: note)
        #expect(list.count == 20)
        #expect(list.first?.title == "t24")
        #expect(list.last?.title == "t5")
        #expect(list.first?.words == 2)
        #expect(history.entries(for: NoteID(rawValue: "n2")).map(\.title) == ["other"])
        #expect(history.entries(for: NoteID(rawValue: "none")).isEmpty)
    }
}
