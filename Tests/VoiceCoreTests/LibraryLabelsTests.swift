import Foundation
import Testing
@testable import VoiceCore

struct LibraryLabelsTests {
    @Test(arguments: [
        ("#Decision", "decision"),
        ("  Họp  team ", "họp-team"),
        ("a/b", "a/b"),
        ("client_X", "client_x"),
        ("##todo", "todo"),
        ("ship🚀it", "shipit"),
        ("-edge-", "edge"),
    ])
    func normalizes(raw: String, expected: String) {
        #expect(TagName.normalize(raw) == expected)
    }

    @Test(arguments: ["###", "   ", "🚀", String(repeating: "a", count: 33)])
    func rejects(raw: String) {
        #expect(TagName.normalize(raw) == nil)
    }

    @Test func keepsThirtyTwoCharacters() {
        let name = String(repeating: "a", count: 32)
        #expect(TagName.normalize(name) == name)
    }

    @Test func folderIDEncodesAsPlainString() throws {
        let id = FolderID(rawValue: "abc")
        let data = try JSONEncoder().encode(["id": id])
        #expect(String(decoding: data, as: UTF8.self) == #"{"id":"abc"}"#)
        let fresh = FolderID.new()
        #expect(fresh.rawValue == fresh.rawValue.lowercased())
        #expect(fresh != FolderID.new())
    }

    @Test func addTagNormalizesDedupesAndKeepsOrder() {
        var labels = ItemLabels()
        #expect(labels.addTag("#Sprint") == .added)
        #expect(labels.addTag("decision") == .added)
        #expect(labels.addTag("SPRINT") == .duplicate)
        #expect(labels.addTag("###") == .invalid)
        #expect(labels.tags == ["sprint", "decision"])
        labels.removeTag("sprint")
        #expect(labels.tags == ["decision"])
    }

    @Test func eleventhTagIsRefused() {
        var labels = ItemLabels()
        for index in 0..<10 { #expect(labels.addTag("t\(index)") == .added) }
        #expect(labels.addTag("extra") == .full)
        #expect(labels.tags.count == 10)
    }
}
