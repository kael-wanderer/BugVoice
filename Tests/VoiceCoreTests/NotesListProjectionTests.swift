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

    @Test func pinnedComeFirstInEverySort() {
        let a = item("a", title: "Beta", body: "", modifiedAt: Date(timeIntervalSince1970: 30))
        let b = item("b", title: "alpha", body: "", modifiedAt: Date(timeIntervalSince1970: 10))
        let c = item("c", title: "Gamma", body: "", modifiedAt: Date(timeIntervalSince1970: 20), pinned: true)
        let d = item("d", title: "Delta", body: "", modifiedAt: Date(timeIntervalSince1970: 5), pinned: true)
        #expect(NotesListProjection.filter([a, b, c, d], query: "").map(\.id.rawValue) == ["c", "d", "a", "b"])
        #expect(NotesListProjection.filter([a, b, c, d], query: "", sort: .editedOldest).map(\.id.rawValue) == ["d", "c", "b", "a"])
        #expect(NotesListProjection.filter([a, b, c, d], query: "", sort: .title).map(\.id.rawValue) == ["d", "c", "b", "a"])
    }

    @Test func titleSortIgnoresCaseAndDiacritics() {
        let one = item("1", title: "Ý tưởng", body: "", modifiedAt: Date(timeIntervalSince1970: 1))
        let two = item("2", title: "an", body: "", modifiedAt: Date(timeIntervalSince1970: 2))
        let three = item("3", title: "An", body: "", modifiedAt: Date(timeIntervalSince1970: 3))
        #expect(NotesListProjection.filter([one, two, three], query: "", sort: .title).map(\.id.rawValue) == ["2", "3", "1"])
    }

    private func item(_ id: String, title: String, body: String, modifiedAt: Date = Date(), pinned: Bool = false) -> NotesListItem {
        NotesListItem(id: NoteID(rawValue: id), title: title, body: body, modifiedAt: modifiedAt, pinned: pinned)
    }
}
