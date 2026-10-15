import Foundation
import Testing
@testable import VoiceCore

struct LibraryProjectionTests {
    struct Item: LibraryLabeled, Equatable {
        let name: String
        let labelFolderID: FolderID?
        let labelTags: [String]
    }

    let a = FolderID(rawValue: "a")
    let gone = FolderID(rawValue: "gone")

    var items: [Item] {
        [
            Item(name: "1", labelFolderID: a, labelTags: ["decision", "acme"]),
            Item(name: "2", labelFolderID: a, labelTags: ["decision"]),
            Item(name: "3", labelFolderID: nil, labelTags: ["acme"]),
            Item(name: "4", labelFolderID: gone, labelTags: []),
        ]
    }

    @Test func filtersByFolderTreatingUnknownAsUnfiled() {
        let known: Set<FolderID> = [a]
        #expect(LibraryProjection.filter(items, folder: .all, tags: [], known: known).map(\.name) == ["1", "2", "3", "4"])
        #expect(LibraryProjection.filter(items, folder: .folder(a), tags: [], known: known).map(\.name) == ["1", "2"])
        #expect(LibraryProjection.filter(items, folder: .unfiled, tags: [], known: known).map(\.name) == ["3", "4"])
    }

    @Test func tagChipsMustAllMatch() {
        let result = LibraryProjection.filter(items, folder: .all, tags: ["decision", "acme"], known: [a])
        #expect(result.map(\.name) == ["1"])
    }

    @Test func countsPerFolder() {
        let counts = LibraryProjection.counts(items, known: [a])
        #expect(counts.all == 4)
        #expect(counts.unfiled == 2)
        #expect(counts.count(a) == 2)
        #expect(counts.count(gone) == 0)
    }

    @Test func catalogSortsByUseThenName() {
        #expect(LibraryProjection.catalog(items) == [TagCount(name: "acme", count: 2), TagCount(name: "decision", count: 2)])
    }

    @Test func filterRawValuesRoundTrip() {
        #expect(FolderFilter(rawValue: "all") == .all)
        #expect(FolderFilter(rawValue: "unfiled") == .unfiled)
        #expect(FolderFilter(rawValue: "a") == .folder(a))
        #expect(FolderFilter.folder(a).rawValue == "a")
    }

    @Test func deletedFolderFilterFallsBackToAll() {
        #expect(FolderFilter.folder(gone).resolved(known: [a]) == .all)
        #expect(FolderFilter.folder(a).resolved(known: [a]) == .folder(a))
        #expect(FolderFilter.unfiled.resolved(known: []) == .unfiled)
    }

    @Test func newItemsGoIntoTheViewedFolder() {
        #expect(FolderFilter.folder(a).newItemFolderID == a)
        #expect(FolderFilter.all.newItemFolderID == nil)
        #expect(FolderFilter.unfiled.newItemFolderID == nil)
    }

    @Test func meetingsAndNotesAreLabeled() {
        var meeting = MeetingManifest(startedAt: Date())
        meeting.folderID = a
        meeting.tags = ["x"]
        #expect(meeting.labelFolderID == a)
        #expect(meeting.labelTags == ["x"])
        let note = NoteDocument(title: "T", body: "", frontMatter: NoteFrontMatter(folderID: a, tags: ["y"]))
        #expect(note.labelFolderID == a)
        #expect(note.labelTags == ["y"])
    }
}
