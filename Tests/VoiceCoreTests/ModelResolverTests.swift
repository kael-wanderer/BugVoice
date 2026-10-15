import Foundation
import Testing
@testable import VoiceCore

struct ModelResolverTests {
    let lan = ModelConnection(id: "lmstudio", name: "LM Studio", kind: .openAICompatible, baseURL: "http://localhost:1234", model: "qwen3.8-27b-mlx")
    let cloud = ModelConnection(id: "anthropic-1", name: "Anthropic", kind: .anthropic, baseURL: "", model: "claude-sonnet-5-5")

    func settings() -> ModelSettings {
        var s = ModelSettings()
        s.connections = [lan, cloud]
        s.dictation = ModelUse(engine: .connection("lmstudio"), disableThinking: true)
        s.meetings = ModelUse(engine: .connection("anthropic-1"), model: "claude-opus-5-5")
        s.dictationTimeoutSeconds = 5
        return s
    }

    func plan(_ f: ModelFeature, _ s: ModelSettings, cli: [CLITool: String] = [:], apple: Bool = false) -> ModelPlan {
        ModelResolver.plan(for: f, settings: s, cliPaths: cli, appleIntelligenceAvailable: apple)
    }

    @Test func dictationUsesConnectionDefaultModelAndDictationTimeout() {
        #expect(plan(.dictation, settings()) == .connection(lan, baseURL: URL(string: "http://localhost:1234")!, modelID: "qwen3.8-27b-mlx", disableThinking: true, timeout: 5))
    }

    @Test func notesFallBackToDictation() {
        #expect(plan(.notes, settings()) == plan(.dictation, settings()))
        var s = settings()
        s.notes = ModelUse(engine: .connection("anthropic-1"))
        if case .connection(let c, _, _, _, let timeout) = plan(.notes, s) {
            #expect(c.id == "anthropic-1")
            #expect(timeout == 5)
        } else {
            Issue.record("expected a connection")
        }
    }

    @Test func meetingsUseOverrideModelAndLongTimeouts() {
        #expect(plan(.meetings, settings()) == .connection(cloud, baseURL: URL(string: "https://api.anthropic.com")!, modelID: "claude-opus-5-5", disableThinking: false, timeout: 120))
        var s = settings()
        s.meetings = ModelUse(engine: .connection("lmstudio"))
        if case .connection(_, _, _, _, let timeout) = plan(.meetings, s) { #expect(timeout == 600) } else { Issue.record("expected a connection") }
    }

    @Test func deletedConnectionIsUnavailable() {
        var s = settings()
        s.connections = [cloud]
        #expect(plan(.dictation, s) == .unavailable("The connection for Dictation cleanup was deleted. Choose another in Settings → Models."))
    }

    @Test func badAddressIsUnavailable() {
        var s = settings()
        s.connections[0].baseURL = "http://192.168.1.5:1234"
        #expect(plan(.dictation, s) == .unavailable("The address of LM Studio is not valid."))
    }

    @Test func noneAndAppleIntelligence() {
        var s = settings()
        s.dictation = ModelUse(engine: .none)
        #expect(plan(.dictation, s) == ModelPlan.none)
        s.dictation = ModelUse(engine: .appleIntelligence)
        #expect(plan(.dictation, s, apple: true) == .appleIntelligence(timeout: 5))
        #expect(plan(.dictation, s, apple: false) == .unavailable("Apple Intelligence is not available on this Mac"))
    }

    @Test func cliOnlyForMeetingsAndOnlyWhenFound() {
        var s = settings()
        s.meetings = ModelUse(engine: .cli(.codex), model: "gpt-5.5", effort: "high")
        #expect(plan(.meetings, s, cli: [.codex: "/bin/codex"]) == .cli(.codex, path: "/bin/codex", model: "gpt-5.5", effort: "high", timeout: 600))
        #expect(plan(.meetings, s) == .unavailable("codex was not found on this Mac."))
        s.dictation = ModelUse(engine: .cli(.claude))
        #expect(plan(.dictation, s, cli: [.claude: "/bin/claude"]) == ModelPlan.none)
    }

    @Test func shortNames() {
        #expect(plan(.dictation, settings()).shortName == "Qwen")
        var s = settings()
        s.connections[0].model = ""
        #expect(plan(.dictation, s).shortName == "LM Studio")
        s.meetings = ModelUse(engine: .cli(.claude))
        #expect(plan(.meetings, s, cli: [.claude: "/c"]).shortName == "Claude Code")
        #expect(ModelPlan.none.shortName == nil)
    }

    @Test func thinkingOverrideSetsTheFlag() async throws {
        let base = RecordingModel(output: "ok")
        _ = try await ThinkingOverride(base: base, disableThinking: true).clean(CleanupRequest(system: "s", user: "u"))
        #expect(await base.requests.first?.disableThinking == true)
    }
}
