import Foundation
import Testing
@testable import VoiceCore

struct LibrarySettingsTests {
    @Test func defaultsToAllAndToleratesMissingKeys() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.library.meetingsFolderFilter == "all")
        #expect(settings.library.notesFolderFilter == "all")
        let partial = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"library":{"notesFolderFilter":"f1"}}"#.utf8))
        #expect(partial.library.notesFolderFilter == "f1")
        #expect(partial.library.meetingsFolderFilter == "all")
    }
}
