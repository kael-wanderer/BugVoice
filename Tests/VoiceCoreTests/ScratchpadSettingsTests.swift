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
}
