import BugVoiceMac
import Foundation
import VoiceCore
import WhisperEngine

/// Throws on every call, so a misconfigured provider shows up as
/// *Raw text pasted — model unavailable* instead of silently skipping cleanup.
struct UnavailableModel: TextModel {
    let reason: String
    func clean(_ request: CleanupRequest) async throws -> String {
        throw ProviderError.unavailable(reason)
    }
}

@MainActor
enum ProviderFactory {
    static func textModel(_ plan: ModelPlan, credentials: CredentialStore) -> (any TextModel)? {
        switch plan {
        case .none:
            return nil
        case .unavailable(let reason):
            return UnavailableModel(reason: reason)
        case .connection(let connection, let url, let modelID, _, let timeout):
            let key = credentials.read(connection.credentialAccount)
            if connection.kind.usesAnthropicAPI {
                return AnthropicCompatibleModel(baseURL: url, model: modelID, apiKey: key, requestTimeout: timeout)
            }
            let flavor: OpenAICompatibleModel.Flavor = switch connection.kind {
            case .openAI: .openAI
            case .openRouter: .openRouter
            default: .local
            }
            return OpenAICompatibleModel(baseURL: url, model: modelID, apiKey: key, flavor: flavor, requestTimeout: timeout)
        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *), AppleIntelligenceModel.isAvailable {
                return AppleIntelligenceModel()
            }
            #endif
            return UnavailableModel(reason: "Apple Intelligence is not available on this Mac")
        case .cli(let tool, let path, let model, let effort, let timeout):
            return CLITextModel(tool: tool, executable: path, model: model, effort: effort, timeout: timeout, runner: FoundationProcessRunner())
        }
    }

    static func cleanupModel(_ plan: ModelPlan, credentials: CredentialStore, fallbackTimeout: Double) -> CleanupModel? {
        guard let model = textModel(plan, credentials: credentials) else { return nil }
        switch plan {
        case .connection(_, _, let modelID, let disableThinking, let timeout):
            return CleanupModel(model: model, modelID: modelID, shortName: plan.shortName, disableThinking: disableThinking, timeoutSeconds: timeout)
        case .appleIntelligence(let timeout):
            return CleanupModel(model: model, modelID: "apple-intelligence", shortName: plan.shortName, timeoutSeconds: timeout)
        case .none, .unavailable, .cli:
            return CleanupModel(model: model, modelID: "", shortName: nil, timeoutSeconds: fallbackTimeout)
        }
    }

    static func transcriber(_ s: SpeechSettings, whisper: WhisperKitTranscriber, credentials: CredentialStore) -> any Transcriber {
        switch s.engine {
        case .whisperKit:
            return whisper
        case .openAICompatible:
            let url = URL(string: s.serverBaseURL) ?? URL(string: "http://localhost:8000")!
            return OpenAICompatibleTranscriber(baseURL: url, model: s.serverModel, apiKey: credentials.read("speech-openai"))
        }
    }
}
