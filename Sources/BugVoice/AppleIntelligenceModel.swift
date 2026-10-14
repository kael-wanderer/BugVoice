import Foundation
import VoiceCore
#if canImport(FoundationModels)
import FoundationModels

/// The on-device Apple Intelligence model, macOS 26 and later.
@available(macOS 26.0, *)
struct AppleIntelligenceModel: TextModel {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func clean(_ request: CleanupRequest) async throws -> String {
        let system = request.system
        let user = request.user
        let options = GenerationOptions(temperature: request.temperature, maximumResponseTokens: request.maxTokens)
        // The pipeline's timeout cancels this call. `abandoningOnCancel`
        // returns at once on cancellation even if the session keeps working,
        // so a slow on-device response never holds up the raw-text fallback.
        return try await abandoningOnCancel {
            let session = LanguageModelSession(instructions: system)
            return try await session.respond(to: user, options: options).content
        }
    }
}
#endif
