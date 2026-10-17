import Foundation
import Testing
@testable import VoiceCore

struct NotesDocumentTests {
    @Test func parsesCanonicalH1AndPreservesBodyBytes() throws {
        let parsed = try NotesMarkdownDocument.parse(data: Data("# Release notes\n\nFirst line.\nSecond line.\n".utf8), filename: "release-notes.md")
        #expect(parsed.title == "Release notes")
        #expect(parsed.body == "First line.\nSecond line.\n")
        #expect(!parsed.needsNormalization)
    }

    @Test func nonH1FileUsesFilenameTitleAndKeepsWholeFileAsBody() throws {
        let source = "Heading without marker\n\nBody line.\n"
        let parsed = try NotesMarkdownDocument.parse(data: Data(source.utf8), filename: "Release-notes.md")
        #expect(parsed.title == "Release notes")
        #expect(parsed.body == source)
        #expect(parsed.needsNormalization)
    }

    @Test func emptyFileUsesFilenameTitleAndEmptyBody() throws {
        let parsed = try NotesMarkdownDocument.parse(data: Data(), filename: "Travel-plan.md")
        #expect(parsed.title == "Travel plan")
        #expect(parsed.body.isEmpty)
        #expect(parsed.needsNormalization)
    }

    @Test func emptyH1TitleIsTreatedAsBody() throws {
        let source = "# \nBody\n"
        let parsed = try NotesMarkdownDocument.parse(data: Data(source.utf8), filename: "Empty-heading.md")
        #expect(parsed.title == "Empty heading")
        #expect(parsed.body == source)
        #expect(parsed.needsNormalization)
    }

    @Test func canonicalSerializationIncludesTitleAndBlankLine() {
        let data = NotesMarkdownDocument.serialize(title: "Ý tưởng", body: "Nội dung\n")
        #expect(String(decoding: data, as: UTF8.self) == "# Ý tưởng\n\nNội dung\n")
    }

    @Test func vietnameseDStrokeMapsExplicitlyBeforeSlugFolding() {
        #expect(NotesSlug.make("Đường đi") == "duong-di")
        #expect(NotesSlug.make("đường ĐI") == "duong-di")
    }

    @Test func slugFoldsAccentsAndReplacesPunctuationRuns() {
        #expect(NotesSlug.make("Café / Notes, v2!") == "cafe-notes-v2")
    }

    @Test func emptySlugFallsBackToNote() {
        #expect(NotesSlug.make("你好") == "note")
        #expect(NotesSlug.make("   ... ") == "note")
    }

    @Test func longSlugIsCappedOnAWordBoundary() {
        let title = String(repeating: "what did we decide about ", count: 20)
        let slug = NotesSlug.make(title)
        #expect(slug.count <= NotesSlug.maxLength)
        #expect(slug.count > 60)
        #expect(!slug.hasSuffix("-"))
        #expect(title.lowercased().replacingOccurrences(of: " ", with: "-").hasPrefix(slug + "-"))
    }

    @Test func longSingleWordSlugIsCutAtTheCap() {
        let slug = NotesSlug.make(String(repeating: "a", count: 300))
        #expect(slug == String(repeating: "a", count: NotesSlug.maxLength))
    }

    @Test func shortSlugIsUnchangedByTheCap() {
        let title = String(repeating: "b", count: 80)
        #expect(NotesSlug.make(title) == title)
    }

    @Test func cappedSlugKeepsRoomForCollisionSuffix() {
        let title = String(repeating: "word ", count: 100)
        let slug = NotesSlug.available(title, existingFilenames: [NotesSlug.make(title) + ".md"])
        #expect(slug.hasSuffix("-2"))
        #expect((slug + ".md").utf8.count < 255)
    }

    @Test func collisionAllocationIsCaseInsensitiveAndSkipsExistingSuffixes() {
        #expect(NotesSlug.available("Notes", existingFilenames: ["notes.md", "NOTES-2.MD"]) == "notes-3")
        #expect(NotesSlug.available("Notes", existingFilenames: ["notes.md", "notes-3.md"]) == "notes-2")
    }

    @Test func renameMayReuseItsCurrentSlug() {
        #expect(NotesSlug.available("release-notes", existingFilenames: ["release-notes.md", "other.md"], excludingFilename: "RELEASE-NOTES.MD") == "release-notes")
    }

    @Test func appPathsCreatesNotesDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        try paths.ensureExists()
        #expect(FileManager.default.fileExists(atPath: paths.notes.path))
    }
}
