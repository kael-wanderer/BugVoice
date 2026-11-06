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

struct TransformPlanTests {
    let lan = ModelConnection(id: "lmstudio", name: "LM Studio", kind: .openAICompatible, baseURL: "http://localhost:1234", model: "qwen3.8-27b-mlx")
    let cloud = ModelConnection(id: "anthropic-1", name: "Anthropic", kind: .anthropic, baseURL: "", model: "claude-sonnet-5-5")

    func plan(_ s: ModelSettings, apple: Bool = false) -> ModelPlan {
        ModelResolver.transformPlan(settings: s, cliPaths: [:], appleIntelligenceAvailable: apple)
    }

    @Test func usesNotesModelWithLongTimeouts() {
        var s = ModelSettings()
        s.connections = [lan, cloud]
        s.dictation = ModelUse(engine: .connection("lmstudio"), disableThinking: true)
        s.dictationTimeoutSeconds = 5
        #expect(plan(s) == .connection(lan, baseURL: URL(string: "http://localhost:1234")!, modelID: "qwen3.8-27b-mlx", disableThinking: true, timeout: 600))
        s.notes = ModelUse(engine: .connection("anthropic-1"))
        #expect(plan(s) == .connection(cloud, baseURL: URL(string: "https://api.anthropic.com")!, modelID: "claude-sonnet-5-5", disableThinking: false, timeout: 120))
    }

    @Test func appleIntelligenceAndNone() {
        var s = ModelSettings()
        s.dictation = ModelUse(engine: .appleIntelligence)
        #expect(plan(s, apple: true) == .appleIntelligence(timeout: 120))
        s.dictation = ModelUse(engine: .none)
        #expect(plan(s) == ModelPlan.none)
    }
}

@Suite struct BuiltInResolverTests {
    let id = "qwen3-4b-q4_k_m"
    func settings(dictation: ModelEngine, notes: ModelEngine? = nil, meetings: ModelEngine = .none) -> ModelSettings {
        var s = ModelSettings()
        s.dictation = ModelUse(engine: dictation)
        s.notes = notes.map { ModelUse(engine: $0) }
        s.meetings = ModelUse(engine: meetings)
        s.dictationTimeoutSeconds = 4
        return s
    }
    func plan(_ f: ModelFeature, _ s: ModelSettings, installed: Set<String>) -> ModelPlan {
        ModelResolver.plan(for: f, settings: s, cliPaths: [:], appleIntelligenceAvailable: false, builtInInstalled: installed)
    }

    @Test func installedModelResolves() {
        let model = BuiltInCatalog.model(id: id)!
        let p = plan(.dictation, settings(dictation: .builtIn(id)), installed: [id])
        #expect(p == .builtIn(model, timeout: 4))
        #expect(p.shortName == "Medium")
    }

    @Test func notInstalledIsUnavailable() {
        #expect(plan(.dictation, settings(dictation: .builtIn(id)), installed: []) == .unavailable("Medium is not downloaded. Download it in Settings → Models."))
    }

    @Test func unknownIDIsUnavailable() {
        #expect(plan(.dictation, settings(dictation: .builtIn("gone")), installed: ["gone"]) == .unavailable("This built-in model is no longer offered. Choose another in Settings → Models."))
    }

    @Test func askAndTransformsRefuseBuiltIn() {
        let s = settings(dictation: .builtIn(id))
        #expect(ModelResolver.transformPlan(settings: s, cliPaths: [:], appleIntelligenceAvailable: false, builtInInstalled: [id])
            == .unavailable("Built-in models clean dictation only. Choose a model for Ask and Transforms in Settings → Models."))
        // Notes dictation cleanup still uses the built-in model.
        #expect(plan(.notes, s, installed: [id]) == .builtIn(BuiltInCatalog.model(id: id)!, timeout: 4))
    }

    @Test func meetingsRefuseBuiltIn() {
        #expect(plan(.meetings, settings(dictation: .none, meetings: .builtIn(id)), installed: [id]) == .unavailable("Built-in models are for Dictation and Notes."))
    }

    @Test func notesMustMatchDictation() {
        let s = settings(dictation: .builtIn(id), notes: .builtIn("qwen3-8b-q4_k_m"))
        #expect(plan(.notes, s, installed: [id, "qwen3-8b-q4_k_m"]) == .unavailable("Notes must use the same built-in model as Dictation."))
        let same = settings(dictation: .builtIn(id))
        #expect(plan(.notes, same, installed: [id]) == plan(.dictation, same, installed: [id]))
    }
}
