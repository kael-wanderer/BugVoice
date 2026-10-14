import Foundation
import Testing
@testable import VoiceCore

struct NotesExportTests {
    @Test func exportsCanonicalMarkdownWithVietnameseAndTrailingNewline() {
        #expect(NotesExporter.markdown(title: "Đường đi", body: "Ghi chú\n") == "# Đường đi\n\nGhi chú\n")
    }

    @Test func emptyBodyStillHasCanonicalTitleSeparator() {
        #expect(NotesExporter.markdown(title: "Quick note", body: "") == "# Quick note\n\n")
    }
}
