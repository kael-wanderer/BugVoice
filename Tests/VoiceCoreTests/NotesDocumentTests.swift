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
