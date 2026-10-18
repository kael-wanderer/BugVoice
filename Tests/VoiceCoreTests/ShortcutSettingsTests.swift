import Foundation
import Testing
@testable import VoiceCore

struct ShortcutSettingsTests {
    @Test func defaults() {
        let settings = ShortcutSettings()
        #expect(settings.letter(for: .pasteLast) == "V")
        #expect(settings.letter(for: .toggleMeeting) == "M")
        #expect(settings.letter(for: .openApp) == "B")
        #expect(settings.letter(for: .newNote) == "N")
    }

    @Test func setLetter() {
        var settings = ShortcutSettings()
        let accepted = settings.setLetter("K", for: .pasteLast)
        #expect(accepted)
        #expect(settings.letter(for: .pasteLast) == "K")
        let duplicateAccepted = settings.setLetter("B", for: .pasteLast)
        #expect(!duplicateAccepted)
        #expect(settings.letter(for: .pasteLast) == "K")
        let digitAccepted = settings.setLetter("7", for: .pasteLast)
        #expect(!digitAccepted)
        let lowercaseAccepted = settings.setLetter("k", for: .pasteLast)
        #expect(lowercaseAccepted)
        #expect(settings.letter(for: .pasteLast) == "K")
    }

    @Test func decodingDuplicateKeepsDefaultsAndMissingKeys() throws {
        let duplicate = try JSONDecoder().decode(ShortcutSettings.self, from: Data(#"{"pasteLast":"B"}"#.utf8))
        #expect(duplicate.letter(for: .pasteLast) == "V")
        #expect(duplicate.letter(for: .openApp) == "B")
        let missing = try JSONDecoder().decode(ShortcutSettings.self, from: Data("{}".utf8))
        #expect(missing == ShortcutSettings())
    }

    @Test func keyCodes() {
        #expect(ShortcutKeys.keyCode(forLetter: "V") == 9)
        #expect(ShortcutKeys.keyCode(forLetter: "N") == 45)
        #expect(ShortcutKeys.keyCode(forLetter: "é") == nil)
    }
}
