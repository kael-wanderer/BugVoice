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
    static func textModel(_ s: TextModelSettings, keychain: Keychain) -> (any TextModel)? {
        switch s.provider {
        case .none:
            return nil
        case .openAICompatible:
            guard let url = URL(string: s.baseURL), url.scheme != nil else { return UnavailableModel(reason: "Invalid base URL") }
            return OpenAICompatibleModel(baseURL: url, model: s.model, apiKey: keychain.read("openai"))
        case .anthropicCompatible:
            guard let url = URL(string: s.baseURL), url.scheme != nil else { return UnavailableModel(reason: "Invalid base URL") }
            return AnthropicCompatibleModel(baseURL: url, model: s.model, apiKey: keychain.read("anthropic"), version: s.anthropicVersion)
        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *), AppleIntelligenceModel.isAvailable {
                return AppleIntelligenceModel()
            }
            #endif
            return UnavailableModel(reason: "Apple Intelligence is not available on this Mac")
        }
    }

    static func transcriber(_ s: SpeechSettings, whisper: WhisperKitTranscriber, keychain: Keychain) -> any Transcriber {
        switch s.engine {
        case .whisperKit:
            return whisper
        case .openAICompatible:
            let url = URL(string: s.serverBaseURL) ?? URL(string: "http://localhost:8000")!
            return OpenAICompatibleTranscriber(baseURL: url, model: s.serverModel, apiKey: keychain.read("speech-openai"))
        }
    }
}
