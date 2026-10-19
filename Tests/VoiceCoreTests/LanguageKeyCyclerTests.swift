import Testing
@testable import VoiceCore

struct LanguageKeyCyclerTests {
    @Test func cyclesFromEnglish() {
        var cycler = LanguageKeyCycler(start: .en)
        #expect(!cycler.changed)
        cycler.tap(); #expect(cycler.current == .vi)
        cycler.tap(); #expect(cycler.current == .auto)
        cycler.tap(); #expect(cycler.current == .en)
        #expect(cycler.changed)
    }

    @Test func autoStartsAtEnglish() {
        var cycler = LanguageKeyCycler(start: .auto)
        cycler.tap()
        #expect(cycler.current == .en)
    }
}
