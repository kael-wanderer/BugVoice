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

    @Test func cyclesThroughSpanish() {
        var c = LanguageKeyCycler(start: .auto, languages: [.en, .vi, .es])
        c.tap(); #expect(c.current == .en)
        c.tap(); #expect(c.current == .vi)
        c.tap(); #expect(c.current == .es)
        c.tap(); #expect(c.current == .auto)
    }

    /// A per-app rule can name a language that is no longer ticked; the
    /// dictation still uses it, so the HUD shows it until the first tap.
    @Test func untickedStartShowsUntilFirstTap() {
        var c = LanguageKeyCycler(start: .es, languages: [.en, .vi])
        #expect(c.current == .es)
        c.tap(); #expect(c.current == .auto)
        c.tap(); #expect(c.current == .en)
        c.tap(); c.tap(); #expect(c.current == .auto)
    }

    @Test func spanishOnlyCycle() {
        var c = LanguageKeyCycler(start: .es, languages: [.es])
        #expect(c.current == .es)
        c.tap(); #expect(c.current == .auto)
        c.tap(); #expect(c.current == .es)
    }
}
