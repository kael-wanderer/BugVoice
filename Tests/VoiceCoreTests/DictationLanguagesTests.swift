import Foundation
import Testing
@testable import VoiceCore

struct DictationLanguagesTests {
    @Test func normalizedKeepsFixedOrder() {
        #expect(DictationLanguages.normalized([.es, .auto, .en, .es]) == [.en, .es])
        #expect(DictationLanguages.normalized([]) == [.en, .vi])
        #expect(DictationLanguages.normalized([.auto]) == [.en, .vi])
    }

    /// Settings › Speech and Dictation options have always listed Vietnamese before English.
    @Test func settingsOrderKeepsVietnameseFirst() {
        #expect(DictationLanguages.settingsOrder([.en, .vi, .es]) == [.vi, .en, .es])
        #expect(DictationLanguages.settingsOrder([.es, .en]) == [.en, .es])
    }

    /// Settings › Speech footnote: someone who never ticks Spanish keeps "English or Vietnamese".
    @Test func orListReadsInCycleOrder() {
        #expect(DictationLanguages.orList([.vi, .en]) == "English or Vietnamese")
        #expect(DictationLanguages.orList([.en, .vi, .es]) == "English, Vietnamese or Spanish")
        #expect(DictationLanguages.orList([.es]) == "Spanish")
    }

    @Test func shortCodes() {
        #expect(SpeechLanguage.allCases.map(\.shortCode) == ["Auto", "VI", "EN", "ES"])
    }

    @Test func defaultsAndUntickReset() {
        var s = SpeechSettings()
        #expect(s.dictationLanguages == [.en, .vi])
        s.dictationLanguages = [.en, .vi, .es]
        s.language = .es
        #expect(s.language == .es)
        s.dictationLanguages = [.en, .vi]
        #expect(s.language == .auto)
    }

    @Test func untickedSwitchChoiceFallsBackToAuto() {
        var s = SpeechSettings()
        s.language = .es
        #expect(s.language == .auto)
    }

    @Test func legacyFileKeepsLanguage() throws {
        let s = try JSONDecoder().decode(SpeechSettings.self, from: Data(#"{"language":"vi"}"#.utf8))
        #expect(s.dictationLanguages == [.en, .vi])
        #expect(s.language == .vi)
    }

    @Test func spanishSwitchWithoutSpanishTickedFallsBack() throws {
        let s = try JSONDecoder().decode(SpeechSettings.self, from: Data(#"{"language":"es"}"#.utf8))
        #expect(s.language == .auto)
    }

    @Test func decodingNormalizesLanguages() throws {
        let json = #"{"dictationLanguages":["es","auto","en"],"language":"es"}"#
        let s = try JSONDecoder().decode(SpeechSettings.self, from: Data(json.utf8))
        #expect(s.dictationLanguages == [.en, .es])
        #expect(s.language == .es)
    }

    @Test func spanishRuleSurvivesWhenUnticked() throws {
        let json = #"{"appLanguages":[{"kind":"website","id":"web.whatsapp.com","language":"es"},{"kind":"app","id":"x","language":"auto"}]}"#
        let s = try JSONDecoder().decode(SpeechSettings.self, from: Data(json.utf8))
        #expect(s.appLanguages == [AppLanguageRule(kind: .website, id: "web.whatsapp.com", language: .es)])
        #expect(s.dictationLanguages == [.en, .vi])
        #expect(LanguageResolver(settings: s).language(for: FocusSnapshot(url: "https://web.whatsapp.com/")) == .es)
    }

    @Test func roundTripsSpanish() throws {
        var s = SpeechSettings()
        s.dictationLanguages = [.en, .vi, .es]
        s.language = .es
        #expect(try JSONDecoder().decode(SpeechSettings.self, from: JSONEncoder().encode(s)) == s)
    }
}
