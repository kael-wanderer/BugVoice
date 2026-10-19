import Foundation
import Testing
@testable import VoiceCore

struct DiagnosticsTests {
    @Test func dictationSummaryCarriesOutcomeAndTimingsButNoText() {
        let result = DictationResult(
            startedAt: Date(timeIntervalSince1970: 0), appName: "Terminal", bundleID: "com.apple.Terminal",
            style: .terminal, language: "vi", raw: "secret raw words", cleaned: "Secret cleaned words.",
            finalText: "Secret cleaned words.", outcome: .inserted, rawReason: .modelTimeout, errorMessage: nil,
            timings: StageTimings(recording: 3.21, transcribe: 0.84, clean: 6.2, insert: 0.05)
        )
        let line = Diagnostics.dictationSummary(result)
        #expect(line == "outcome=inserted raw=modelTimeout app=com.apple.Terminal style=terminal lang=vi words=3 rec=3.21s stt=0.84s clean=6.20s insert=0.05s")
        #expect(!line.localizedCaseInsensitiveContains("secret"))
    }

    @Test func dictationSummaryOmitsMissingFields() {
        let result = DictationResult(
            startedAt: Date(timeIntervalSince1970: 0), appName: nil, bundleID: nil,
            style: .work, language: nil, raw: "", cleaned: nil, finalText: "",
            outcome: .nothingHeard, rawReason: nil, errorMessage: "Speech engine stopped",
            timings: StageTimings(recording: 1)
        )
        #expect(Diagnostics.dictationSummary(result)
            == "outcome=nothingHeard style=work words=0 rec=1.00s stt=0.00s clean=0.00s insert=0.00s")
    }

    @Test func reportListsSystemThenNewestLastEntries() {
        let report = Diagnostics.report(
            appVersion: "1.4 (19)", system: "macOS 27.0", hardware: "arm64",
            facts: ["Speech engine": "whisperKit", "Dictation model": "oMLX / qwen3"],
            entries: [
                .init(date: Date(timeIntervalSince1970: 60), level: "error", category: "meeting", message: "tap failed"),
                .init(date: Date(timeIntervalSince1970: 0), level: "info", category: "dictation", message: "outcome=inserted"),
            ],
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        #expect(report == """
            BugVoice diagnostics
            App: 1.4 (19)
            System: macOS 27.0 (arm64)
            Dictation model: oMLX / qwen3
            Speech engine: whisperKit

            Log (this launch, 2 entries)
            00:00:00 info dictation: outcome=inserted
            00:01:00 error meeting: tap failed

            """)
    }

    @Test func reportCountsOneEntryInTheSingular() {
        let report = Diagnostics.report(appVersion: "1", system: "macOS", hardware: "arm64", facts: [:],
                                        entries: [.init(date: Date(timeIntervalSince1970: 0), level: "notice", category: "app", message: "launch")],
                                        timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(report.contains("Log (this launch, 1 entry)\n"))
    }

    @Test func reportSaysWhenLogIsEmpty() {
        let report = Diagnostics.report(appVersion: "1", system: "macOS", hardware: "arm64", facts: [:], entries: [],
                                        timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(report.hasSuffix("Log (this launch, 0 entries)\nNo entries.\n"))
    }

    @Test func factsNameEnginesAndModelsButNoAddressesOrKeys() {
        var settings = AppSettings()
        settings.models.connections = [
            ModelConnection(id: "omlx", name: "oMLX", kind: .openAICompatible, baseURL: "http://user:pw@localhost:8000", model: "Qwen3"),
        ]
        settings.models.dictation = ModelUse(engine: .connection("omlx"), model: "Qwen3-small")
        settings.models.notes = nil
        settings.models.meetings = ModelUse(engine: .cli(.claude))
        let facts = Diagnostics.facts(settings)
        #expect(facts["Speech"] == "whisperKit large-v3-v20240930_turbo, language auto")
        #expect(facts["Dictation model"] == "oMLX (openAICompatible) Qwen3-small")
        #expect(facts["Notes model"] == "same as Dictation")
        #expect(facts["Meetings model"] == "claude CLI")
        #expect(facts["Hotkey"] == "rightControl")
        #expect(!facts.values.contains { $0.contains("localhost") || $0.contains("pw") })
    }

    @Test func factsNameMissingConnection() {
        var settings = AppSettings()
        settings.models.dictation = ModelUse(engine: .connection("gone"))
        settings.models.meetings = ModelUse(engine: .none)
        #expect(Diagnostics.facts(settings)["Dictation model"] == "missing connection gone")
        #expect(Diagnostics.facts(settings)["Meetings model"] == "none")
    }
}
