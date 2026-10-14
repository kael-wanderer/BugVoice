import Foundation
import Testing
@testable import VoiceCore

struct NotesListProjectionTests {
    @Test func literalSearchMatchesTitleAndBodyCaseAndDiacriticInsensitively() {
        let items = [
            item("one", title: "Ý tưởng", body: "Local-first note"),
            item("two", title: "Release", body: "Mixed English and Vietnamese")
        ]
        #expect(NotesListProjection.filter(items, query: "y tuong").map(\.id.rawValue) == ["one"])
        #expect(NotesListProjection.filter(items, query: "LOCAL-FIRST").map(\.id.rawValue) == ["one"])
        #expect(NotesListProjection.filter(items, query: "VIETNAMESE").map(\.id.rawValue) == ["two"])
        #expect(NotesListProjection.filter(items, query: "local OR Vietnamese").isEmpty)
    }

    @Test func emptyOrWhitespaceQueryReturnsAllNewestFirst() {
        let older = item("older", title: "Older", body: "", modifiedAt: Date(timeIntervalSince1970: 10))
        let newer = item("newer", title: "Newer", body: "", modifiedAt: Date(timeIntervalSince1970: 20))
        let tied = item("tied", title: "Alpha", body: "", modifiedAt: Date(timeIntervalSince1970: 20))
        #expect(NotesListProjection.filter([older, newer, tied], query: "  \n").map(\.id.rawValue) == ["tied", "newer", "older"])
    }

    private func item(_ id: String, title: String, body: String, modifiedAt: Date = Date()) -> NotesListItem {
        NotesListItem(id: NoteID(rawValue: id), title: title, body: body, modifiedAt: modifiedAt)
    }
}
