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
