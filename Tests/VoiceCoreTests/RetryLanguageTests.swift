import Testing
@testable import VoiceCore

struct RetryLanguageTests {
    @Test func choicesFollowEnabledLanguagesAndIncludeAuto() {
        let items = RetryLanguage.options([.en, .vi, .es])
        #expect(items.map(\.language) == [.en, .vi, .es, .auto])
        #expect(items.map(\.label) == ["Retry in English", "Retry in Vietnamese", "Retry in Spanish", "Retry with automatic language"])
    }
}
