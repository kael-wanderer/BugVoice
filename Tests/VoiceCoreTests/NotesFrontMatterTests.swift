import Foundation
import Testing
@testable import VoiceCore

struct NotesFrontMatterTests {
    @Test func fileWithoutFrontMatterIsUnchanged() throws {
        let data = Data("# Ideas\n\nbody".utf8)
        let parsed = try NotesMarkdownDocument.parse(data: data, filename: "ideas.md")
        #expect(parsed.frontMatter == NoteFrontMatter())
        #expect(parsed.body == "body")
        #expect(!parsed.needsNormalization)
        #expect(NotesMarkdownDocument.serialize(title: "Ideas", body: "body", frontMatter: NoteFrontMatter()) == data)
    }

    @Test func folderAndTagsRoundTrip() throws {
        let front = NoteFrontMatter(folderID: FolderID(rawValue: "f1"), tags: ["decision", "họp"])
        let data = NotesMarkdownDocument.serialize(title: "Sprint", body: "Body\n", frontMatter: front)
        #expect(String(decoding: data, as: UTF8.self) == "---\nfolder: f1\ntags: [decision, họp]\n---\n# Sprint\n\nBody\n")
        let parsed = try NotesMarkdownDocument.parse(data: data, filename: "sprint.md")
        #expect(parsed.frontMatter == front)
        #expect(parsed.title == "Sprint")
        #expect(parsed.body == "Body\n")
        #expect(!parsed.needsNormalization)
    }

    @Test func otherAppsKeysArePreservedInOrder() throws {
        let source = "---\naliases: [VPN]\nfolder: f1\ncreated: 2026-10-01\ntags: [\"vpn\", 'Idea']\n---\n# VPN\n\nText"
        let parsed = try NotesMarkdownDocument.parse(data: Data(source.utf8), filename: "vpn.md")
        #expect(parsed.frontMatter.folderID == FolderID(rawValue: "f1"))
        #expect(parsed.frontMatter.tags == ["vpn", "idea"])
        #expect(parsed.frontMatter.extra == ["aliases: [VPN]", "created: 2026-10-01"])
        let written = NotesMarkdownDocument.serialize(title: parsed.title, body: parsed.body, frontMatter: parsed.frontMatter)
        #expect(String(decoding: written, as: UTF8.self) == "---\nfolder: f1\ntags: [vpn, idea]\naliases: [VPN]\ncreated: 2026-10-01\n---\n# VPN\n\nText")
    }

    @Test func pinnedRoundTripsAndIsAbsentWhenFalse() throws {
        let front = NoteFrontMatter(tags: ["a"], pinned: true)
        let data = NotesMarkdownDocument.serialize(title: "T", body: "B", frontMatter: front)
        #expect(String(decoding: data, as: UTF8.self) == "---\ntags: [a]\npinned: true\n---\n# T\n\nB")
        #expect(try NotesMarkdownDocument.parse(data: data, filename: "t.md").frontMatter == front)
        let plain = NotesMarkdownDocument.serialize(title: "T", body: "B", frontMatter: NoteFrontMatter(pinned: false))
        #expect(String(decoding: plain, as: UTF8.self) == "# T\n\nB")
    }

    @Test func pinnedValuesOtherThanTrueMeanNotPinned() throws {
        for value in ["false", "yes", "\"TRUE\"", ""] {
            let source = "---\npinned: \(value)\n---\n# T\n\nB"
            let parsed = try NotesMarkdownDocument.parse(data: Data(source.utf8), filename: "t.md")
            #expect(parsed.frontMatter.pinned == (value == "\"TRUE\""))
            #expect(parsed.frontMatter.extra.isEmpty)
        }
    }

    @Test func crlfFrontMatterIsAccepted() throws {
        let source = "---\r\nfolder: f1\r\ntags: [a]\r\n---\r\n# T\r\n\r\nB"
        let parsed = try NotesMarkdownDocument.parse(data: Data(source.utf8), filename: "t.md")
        #expect(parsed.frontMatter == NoteFrontMatter(folderID: FolderID(rawValue: "f1"), tags: ["a"]))
        #expect(parsed.title == "T")
        #expect(parsed.needsNormalization)
    }

    @Test func unclosedFrontMatterIsBody() throws {
        let source = "---\nfolder: f1\nno closing line"
        let parsed = try NotesMarkdownDocument.parse(data: Data(source.utf8), filename: "loose.md")
        #expect(parsed.frontMatter == NoteFrontMatter())
        #expect(parsed.title == "loose")
        #expect(parsed.body == source)
    }

    @Test func malformedTagsLineIsKeptAsExtra() throws {
        let source = "---\ntags: decision\n---\n# T\n\nB"
        let parsed = try NotesMarkdownDocument.parse(data: Data(source.utf8), filename: "t.md")
        #expect(parsed.frontMatter.tags.isEmpty)
        #expect(parsed.frontMatter.extra == ["tags: decision"])
    }

    @Test func removingLabelsRemovesFrontMatter() throws {
        let data = NotesMarkdownDocument.serialize(title: "T", body: "B", frontMatter: NoteFrontMatter())
        #expect(String(decoding: data, as: UTF8.self) == "# T\n\nB")
    }

    @Test func searchMatchesTags() {
        let item = NotesListItem(id: NoteID(rawValue: "a"), title: "Plan", body: "text", modifiedAt: .now, tags: ["acme"])
        #expect(NotesListProjection.filter([item], query: "#acme").count == 1)
        #expect(NotesListProjection.filter([item], query: "acme").count == 1)
        #expect(NotesListProjection.filter([item], query: "zzz").isEmpty)
    }
}
