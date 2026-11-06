import Foundation
import Testing
@testable import VoiceCore

@Suite struct OnboardingTests {
    @Test func stepsRunInOrder() {
        #expect(OnboardingStep.allCases.map(\.number) == [1, 2, 3, 4, 5, 6, 7])
        #expect(OnboardingStep.welcome.previous == nil)
        #expect(OnboardingStep.finish.next == nil)
        #expect(OnboardingStep.allCases.filter(\.probesHotkey) == [.hotkey])
        #expect(OnboardingStep.allCases.filter { !$0.showsSkip } == [.welcome, .speech, .finish])
    }

    @Test func connectionChoiceSetsDictationAndMeetings() {
        var m = AppSettings.freshInstall().models
        let c = ModelConnection(id: "server-abc123", name: "LM Studio", kind: .openAICompatible, baseURL: "http://localhost:1234/v1", model: "qwen3-4b")
        OnboardingSetup.apply(.connection(c, local: true), to: &m)
        #expect(m.connections == [c])
        #expect(m.dictation.engine == .connection("server-abc123"))
        #expect(m.dictation.disableThinking == true)
        #expect(m.notes == nil)
        #expect(m.meetings.engine == .connection("server-abc123"))
    }

    @Test func cloudConnectionKeepsThinking() {
        var m = AppSettings.freshInstall().models
        let c = ModelConnection(id: "cloud-1", name: "Cloud", kind: .openAICompatible, baseURL: "https://api.example.com/v1", model: "m")
        OnboardingSetup.apply(.connection(c, local: false), to: &m)
        #expect(m.dictation.disableThinking == false)
    }

    @Test func reapplyingSameConnectionReplacesIt() {
        var m = AppSettings.freshInstall().models
        var c = ModelConnection(id: "server-abc123", name: "LM Studio", kind: .openAICompatible, baseURL: "http://localhost:1234/v1", model: "old")
        OnboardingSetup.apply(.connection(c, local: true), to: &m)
        c.model = "new"
        OnboardingSetup.apply(.connection(c, local: true), to: &m)
        #expect(m.connections.count == 1)
        #expect(m.connections.first?.model == "new")
    }

    @Test func appleIntelligenceLeavesMeetingsAlone() {
        var m = AppSettings.freshInstall().models
        OnboardingSetup.apply(.appleIntelligence, to: &m)
        #expect(m.dictation.engine == .appleIntelligence)
        #expect(m.meetings.engine == .none)
    }

    @Test func noneTurnsCleanupOff() {
        var m = AppSettings.freshInstall().models
        let c = ModelConnection(id: "server-abc123", name: "LM Studio", kind: .openAICompatible, baseURL: "http://localhost:1234/v1", model: "m")
        OnboardingSetup.apply(.connection(c, local: true), to: &m)
        OnboardingSetup.apply(.none, to: &m)
        #expect(m.dictation.engine == .none)
        #expect(m.connections == [c])
    }

    @Test func choicesHideUnavailableKinds() {
        #expect(OnboardingSetup.choices(appleIntelligence: false, builtInEnabled: false) == [.localApp, .cloud, .none])
        #expect(OnboardingSetup.choices(appleIntelligence: true, builtInEnabled: true) == [.builtIn, .appleIntelligence, .localApp, .cloud, .none])
    }
}

@Suite struct TryItResultTests {
    private func result(_ outcome: DictationOutcome, cleaned: String? = "Hello.", rawReason: RawReason? = nil, error: String? = nil) -> DictationResult {
        DictationResult(
            startedAt: Date(), style: .document, raw: "hello", cleaned: cleaned, finalText: cleaned ?? "hello",
            outcome: outcome, rawReason: rawReason, errorMessage: error,
            timings: StageTimings(recording: 2, transcribe: 0.6, clean: 0.8, insert: 0.1))
    }

    @Test func successCarriesTimesAndModel() {
        let r = TryItResult(result(.inserted), cleanupName: "Qwen3 4B")
        #expect(r.problem == nil)
        #expect(r.speechSeconds == 0.6)
        #expect(r.cleanupSeconds == 0.8)
        #expect(r.cleanupName == "Qwen3 4B")
        #expect(r.text == "Hello.")
    }

    @Test func noCleanupModelHasNoCleanupTime() {
        let r = TryItResult(result(.inserted, cleaned: nil, rawReason: .cleanupOff), cleanupName: nil)
        #expect(r.problem == nil)
        #expect(r.cleanupSeconds == nil)
    }

    @Test func cleanupFailureNamesTheReason() {
        let r = TryItResult(result(.inserted, cleaned: nil, rawReason: .modelError, error: "connection refused"), cleanupName: "x")
        #expect(r.problem?.contains("connection refused") == true)
        #expect(r.cleanupSeconds == nil)
    }

    @Test func copiedAndFailedOutcomesExplainThemselves() {
        #expect(TryItResult(result(.copiedNotConsumed), cleanupName: nil).problem != nil)
        #expect(TryItResult(result(.transcriptionFailed, error: "no model"), cleanupName: nil).problem == "no model")
        #expect(TryItResult(result(.nothingHeard, cleaned: nil), cleanupName: nil).problem != nil)
    }
}
