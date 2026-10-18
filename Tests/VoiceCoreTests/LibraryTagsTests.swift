import Foundation
import Testing
@testable import VoiceCore

struct LibraryTagsTests {
@Test func oldFileWithoutTagsLoads() throws {
    let json = #"{"version":1,"folders":[{"id":"f1","name":"Client A","createdAt":"2026-10-01T00:00:00Z"}]}"#
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    let file = try d.decode(LibraryFile.self, from: Data(json.utf8))
    #expect(file.folders.map(\.name) == ["Client A"])
    #expect(file.tags.isEmpty)
}
@Test func unknownColourReadsAsNone() throws {
    let json = #"{"version":1,"folders":[],"tags":[{"name":"client","color":"magenta"}]}"#
    let file = try JSONDecoder().decode(LibraryFile.self, from: Data(json.utf8))
    #expect(file.tags == [LibraryTag(name: "client", color: nil)])
}
@Test func tagsRoundTrip() throws {
    var file = LibraryFile(); LibraryTags.setColor(.blue, for: "client", in: &file)
    let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    #expect(try d.decode(LibraryFile.self, from: e.encode(file)) == file)
}
@Test func renameReplacesInPlace() {
    #expect(TagEdit.rename("followup", to: "follow-up", in: ["a", "followup", "b"]) == ["a", "follow-up", "b"])
    #expect(TagEdit.rename("x", to: "y", in: ["a"]) == ["a"])
}
@Test func mergeKeepsOneCopyInOrder() {
    #expect(TagEdit.rename("old", to: "new", in: ["old", "a", "new", "b"]) == ["a", "new", "b"])
}
@Test func renameToSameNameIsNoChange() {
    #expect(TagEdit.rename("client", to: "client", in: ["client", "a"]) == ["client", "a"])
}
@Test func filterFollowsRenameAndDelete() {
    #expect(TagEdit.rename("old", to: "new", in: ["old"]) == ["new"])
    #expect(TagEdit.remove("old", from: ["a", "old"]) == ["a"])
}
@Test func createNormalizesAndReportsExisting() {
    var file = LibraryFile()
    #expect(LibraryTags.create("#Draft Notes", inUse: [], in: &file) == .created("draft-notes"))
    #expect(LibraryTags.create("draft-notes", inUse: [], in: &file) == .exists("draft-notes"))
    #expect(LibraryTags.create("client", inUse: ["client"], in: &file) == .exists("client"))
    #expect(LibraryTags.create("  ", inUse: [], in: &file) == .invalid)
    #expect(file.tags == [LibraryTag(name: "draft-notes", color: nil)])
}
@Test func renameMovesColourAndMergeKeepsTargetColour() {
    var file = LibraryFile()
    LibraryTags.setColor(.red, for: "old", in: &file)
    LibraryTags.rename("old", to: "new", in: &file)
    #expect(file.tags == [LibraryTag(name: "new", color: .red)])
    LibraryTags.setColor(.blue, for: "other", in: &file)
    LibraryTags.rename("new", to: "other", in: &file)
    #expect(file.tags == [LibraryTag(name: "other", color: .blue)])
}
@Test func deleteRemovesEntry() {
    var file = LibraryFile(); LibraryTags.setColor(.green, for: "a", in: &file)
    LibraryTags.delete("a", in: &file)
    #expect(file.tags.isEmpty)
}
@Test func tagRowsUnionSortedWithCounts() {
    var file = LibraryFile()
    _ = LibraryTags.create("draft", inUse: [], in: &file)
    LibraryTags.setColor(.teal, for: "client", in: &file)
    let rows = LibraryProjection.tagRows(
        notes: [TagCount(name: "client", count: 2), TagCount(name: "idea", count: 1)],
        meetings: [TagCount(name: "client", count: 1)], file: file)
    #expect(rows.map(\.name) == ["client", "draft", "idea"])
    #expect(rows[0] == TagRow(name: "client", color: .teal, notes: 2, meetings: 1))
    #expect(rows.map(\.countText) == ["2 notes · 1 meeting", "not used", "1 note"])
}
}
