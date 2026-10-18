import Foundation
import Testing
@testable import VoiceCore

struct ScratchpadSettingsTests {
    @Test func defaultsAndRoundTrip() throws {
        let settings = AppSettings()
        #expect(settings.scratchpad == ScratchpadSettings())
        #expect(settings.scratchpad.view == .markdown)
        var changed = settings
        changed.scratchpad.openTabs = ["a", "b"]
        changed.scratchpad.activeTab = "b"
        changed.scratchpad.view = .doc
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(changed))
        #expect(decoded.scratchpad == changed.scratchpad)
    }

    @Test func unknownViewKeepsTheRest() throws {
        let json = #"{"scratchpad":{"openTabs":["a"],"activeTab":"a","view":"wysiwyg"}}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(decoded.scratchpad.openTabs == ["a"])
        #expect(decoded.scratchpad.activeTab == "a")
        #expect(decoded.scratchpad.view == .markdown)
    }

    @Test func windowKeysDefaultAndRoundTrip() throws {
        let old = #"{"scratchpad":{"openTabs":["a"],"activeTab":"a","view":"doc"}}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(decoded.scratchpad.view == .doc)
        #expect(decoded.scratchpad.keepOnTop)
        #expect(!decoded.scratchpad.sideListHidden)
        #expect(!decoded.scratchpad.compact)
        #expect(decoded.scratchpad.aiBarShown == false)
        #expect(decoded.scratchpad.sort == .editedNewest)
        var changed = decoded
        changed.scratchpad.keepOnTop = false
        changed.scratchpad.sideListHidden = true
        changed.scratchpad.compact = true
        changed.scratchpad.aiBarShown = true
        changed.scratchpad.sort = .title
        let again = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(changed))
        #expect(again.scratchpad == changed.scratchpad)
        #expect(again.scratchpad.aiBarShown == true)
    }

    @Test func unknownSortAndBarFallBack() throws {
        let json = #"{"scratchpad":{"bottomBar":"formatting","sort":"size","keepOnTop":false}}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(decoded.scratchpad.aiBarShown == false)
        #expect(decoded.scratchpad.sort == .editedNewest)
        #expect(!decoded.scratchpad.keepOnTop)
        let oldAI = #"{"scratchpad":{"bottomBar":"ai"}}"#
        let decodedAI = try JSONDecoder().decode(AppSettings.self, from: Data(oldAI.utf8))
        #expect(decodedAI.scratchpad.aiBarShown == false)
        #expect(!String(decoding: try JSONEncoder().encode(AppSettings()), as: UTF8.self).contains("bottomBar"))
    }
}
