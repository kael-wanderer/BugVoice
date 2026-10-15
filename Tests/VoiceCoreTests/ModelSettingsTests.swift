import Foundation
import Testing
@testable import VoiceCore

struct ModelSettingsTests {
    func decode(_ json: String) throws -> ModelSettings { try JSONDecoder().decode(ModelSettings.self, from: Data(json.utf8)) }
    @Test func defaultsUseLocalLMStudioForEveryFeature() {
        let s = ModelSettings()
        #expect(s.connections == [ModelSettings.defaultConnection])
        #expect(s.connections[0].baseURL == "http://localhost:1234")
        #expect(s.connections[0].model == "qwen3.8-27b-mlx")
        #expect(s.dictation == ModelUse(engine: .connection("lmstudio"), disableThinking: true))
        #expect(s.meetings.engine == .connection("lmstudio"))
        #expect(s.notes == nil)
        #expect(s.dictationTimeoutSeconds == 3)
    }
    @Test func roundTripsAndDoesNotSaveKeyMoves() throws {
        var s = ModelSettings()
        s.connections.append(ModelConnection(id: "anthropic-1a2b3c", name: "Anthropic", kind: .anthropic, baseURL: "", model: "claude-sonnet-5-5"))
        s.meetings = ModelUse(engine: .cli(.claude), effort: "high")
        s.notes = ModelUse(engine: .appleIntelligence)
        s.pendingKeyMoves = [KeyMove(from: "openai", to: "connection-lmstudio")]
        let data = try JSONEncoder().encode(s)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("pendingKeyMoves")); #expect(text.contains(#""cli":"claude""#)); #expect(text.contains(#""appleIntelligence""#))
        var expected = s; expected.pendingKeyMoves = []
        #expect(try JSONDecoder().decode(ModelSettings.self, from: data) == expected)
    }
    @Test func badConnectionsAreDroppedAlone() throws {
        let s = try decode(#"{"connections":[{"id":"ok-1","name":"A","kind":"openAI","baseURL":"","model":"m"},{"id":"bad-kind","kind":"gemini"},{"id":"cli-claude","kind":"openAI"},{"id":"Has Space","kind":"openAI"},{"id":"ok-1","name":"dup","kind":"anthropic"},{"id":"ok-2","kind":"openRouter"}]}"#)
        #expect(s.connections.map(\.id) == ["ok-1", "ok-2"]); #expect(s.connections[1].name == "OpenRouter")
    }
    @Test func atMostTwentyConnections() throws {
        let items = (1...21).map { #"{"id":"c-\#($0)","kind":"openAI"}"# }.joined(separator: ",")
        #expect(try decode(#"{"connections":[\#(items)]}"#).connections.count == 20)
    }
    @Test func cliEngineIsRefusedForDictationAndNotes() throws {
        let s = try decode(#"{"dictation":{"engine":{"cli":"codex"}},"notes":{"engine":{"cli":"pi"}},"meetings":{"engine":{"cli":"pi"}}}"#)
        #expect(s.dictation.engine == .none); #expect(s.notes?.engine == ModelEngine.none); #expect(s.meetings.engine == .cli(.pi))
    }
    @Test func unknownEngineKeepsDefault() throws {
        let s = try decode(#"{"dictation":{"engine":"gemini","model":"x"}}"#)
        #expect(s.dictation.engine == .connection("lmstudio")); #expect(s.dictation.model == "x")
    }
    @Test func connectionIDsAndKeychainAccount() {
        #expect(ModelConnection.isValidID("anthropic-1a2b3c")); #expect(!ModelConnection.isValidID("")); #expect(!ModelConnection.isValidID("cli-codex")); #expect(!ModelConnection.isValidID("A")); #expect(!ModelConnection.isValidID("a/b"))
        let id = ModelConnection.newID(for: .openRouter); #expect(id.hasPrefix("openrouter-")); #expect(ModelConnection.isValidID(id))
        #expect(ModelConnection(id: "x-1", name: "", kind: .openAI, baseURL: "", model: "").keychainAccount == "connection-x-1")
    }
    @Test(arguments: [(TextModelProvider.openAICompatible,"http://localhost:1234","LM Studio",ConnectionKind.openAICompatible,"openai"),(.openAICompatible,"http://localhost:11434","Ollama",.openAICompatible,"openai"),(.openAICompatible,"https://llm.example.com","OpenAI-compatible server",.openAICompatible,"openai"),(.anthropicCompatible,"https://api.anthropic.com","Anthropic",.anthropic,"anthropic"),(.anthropicCompatible,"https://proxy.example.com","Anthropic-compatible server",.anthropicCompatible,"anthropic")])
    func migratesHTTPProviders(provider: TextModelProvider, url: String, name: String, kind: ConnectionKind, oldAccount: String) {
        var old = TextModelSettings(); old.provider = provider; old.baseURL = url; old.model = "m1"; old.timeoutSeconds = 5; old.disableThinking = false
        let s = LegacyTextModelMigration.migrate(old)
        #expect(s.connections == [ModelConnection(id:"migrated-1",name:name,kind:kind,baseURL:url,model:"m1")])
        #expect(s.dictation == ModelUse(engine:.connection("migrated-1"),disableThinking:false)); #expect(s.meetings == ModelUse(engine:.connection("migrated-1"))); #expect(s.notes == nil); #expect(s.dictationTimeoutSeconds == 5)
        #expect(s.pendingKeyMoves == [KeyMove(from:oldAccount,to:"connection-migrated-1")])
    }
    @Test func migratesAppleIntelligenceAndNone() {
        var old = TextModelSettings(); old.provider = .appleIntelligence; var s = LegacyTextModelMigration.migrate(old)
        #expect(s.connections.isEmpty); #expect(s.dictation.engine == .appleIntelligence); #expect(s.pendingKeyMoves.isEmpty)
        old.provider = .none; s = LegacyTextModelMigration.migrate(old); #expect(s.dictation.engine == .none); #expect(s.meetings.engine == .none)
    }
    @Test func presetsHaveNoGemini() {
        #expect(ConnectionPreset.all.map(\.name) == ["LM Studio","Ollama","MLX server","Anthropic","OpenAI","OpenRouter","OpenAI-compatible server","Anthropic-compatible server"])
        #expect(!ConnectionPreset.all.contains { $0.name.lowercased().contains("gemini") })
    }
    @Test func shortNames() {
        #expect(ModelNames.short("qwen3.8-27b-mlx") == "Qwen"); #expect(ModelNames.short("claude-sonnet-5-5") == "Claude"); #expect(ModelNames.short("mlx-community/Qwen3-8B-4bit") == "Qwen"); #expect(ModelNames.short("4o-mini") == "4o-mini"); #expect(ModelNames.short("  ") == nil)
    }
}
