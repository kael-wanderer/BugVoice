import Foundation
import Synchronization
import VoiceCore
import WhisperKit

/// On-device Whisper. Downloads the model into `downloadBase` on first use,
/// then keeps it loaded for the life of the process.
/// WhisperKit's class is not Sendable. The loading task hands the model to
/// the actor once, and only the actor uses it after that.
private final class LoadedKit: @unchecked Sendable {
    let kit: WhisperKit
    init(kit: WhisperKit) { self.kit = kit }
}

public actor WhisperKitTranscriber: Transcriber {
    public enum LoadState: Sendable, Equatable {
        case notLoaded
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    /// Whisper's prompt budget is half its 448-token context.
    static let maxPromptTokens = 224

    public let modelName: String
    private let downloadBase: URL
    private let cachedFolders: (model: URL, tokenizer: URL)?
    private var kit: WhisperKit?
    private var loading: Task<LoadedKit, Error>?
    public private(set) var state: LoadState = .notLoaded

    public init(modelName: String, downloadBase: URL) {
        self.modelName = modelName
        self.downloadBase = downloadBase
        self.cachedFolders = nil
    }

    /// Offline bench path: use existing compiled models and validate the local
    /// tokenizer before WhisperKit can fall back to its Hub loader.
    public init(modelName: String, cachedModelFolder: URL, cachedTokenizerFolder: URL) {
        self.modelName = modelName
        self.downloadBase = cachedModelFolder
        self.cachedFolders = (cachedModelFolder, cachedTokenizerFolder)
    }

    public func prepare(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        _ = try await loadedKit(progress: progress)
    }

    private func setState(_ newState: LoadState) {
        state = newState
    }

    private func loadedKit(progress: (@Sendable (Double) -> Void)? = nil) async throws -> WhisperKit {
        if let kit { return kit }
        if let loading { return try await loading.value.kit }
        let name = modelName
        let base = downloadBase
        let cached = cachedFolders
        let task = Task<LoadedKit, Error> {
            let folder: URL
            if let cached {
                // This overload parses local files only; errors propagate rather
                // than falling through to a download.
                _ = try await AutoTokenizerWrapper.from(modelFolder: cached.tokenizer)
                folder = cached.model
            } else {
                self.setState(.downloading(0))
                folder = try await WhisperKit.download(variant: name, downloadBase: base) { p in
                    progress?(p.fractionCompleted)
                    Task { await self.setState(.downloading(p.fractionCompleted)) }
                }
            }
            self.setState(.loading)
            let config = WhisperKitConfig(
                modelFolder: folder.path,
                tokenizerFolder: cached?.tokenizer,
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )
            return LoadedKit(kit: try await WhisperKit(config))
        }
        loading = task
        do {
            let loaded = try await task.value.kit
            kit = loaded
            loading = nil
            state = .ready
            return loaded
        } catch {
            loading = nil
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    public func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript {
        try Task.checkCancellation()
        let kit = try await loadedKit()
        try Task.checkCancellation()
        var decode = DecodingOptions()
        decode.verbose = false
        decode.task = .transcribe
        decode.temperature = 0
        decode.skipSpecialTokens = true
        // WhisperKit 1.1.1 returns empty text when a forced language
        // (prefill prompt) is combined with timestamp decoding. Timestamped
        // requests therefore use auto language; dictation keeps the existing
        // forced-language, no-timestamps behavior.
        decode.withoutTimestamps = !options.timestamps
        decode.chunkingStrategy = options.vadChunking ? .vad : nil
        if options.timestamps || options.language == .auto {
            decode.language = nil
            decode.detectLanguage = true
            decode.usePrefillPrompt = false
        } else {
            decode.language = options.language.rawValue
            decode.detectLanguage = false
            decode.usePrefillPrompt = true
        }
        if !options.prompt.isEmpty, let tokenizer = kit.tokenizer {
            let tokens = tokenizer.encode(text: " " + options.prompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            decode.promptTokens = Array(tokens.suffix(Self.maxPromptTokens))
        }
        // WhisperKit invokes the decoding callback in a detached task, whose
        // Task.isCancelled does not reflect our caller's cancellation.
        let cancelled = Mutex(false)
        let results = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await kit.transcribe(audioArray: clip.samples, decodeOptions: decode, callback: { _ in
                cancelled.withLock { $0 } ? false : nil
            })
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
        try Task.checkCancellation()
        let segments = results.flatMap(\.segments).map {
            TranscriptSegment(start: Double($0.start), end: Double($0.end), text: Self.strip($0.text))
        }
        let language = results.first?.language
        var languageScores: [String: Float] = [:]
        if options.language == .auto, !options.expectedLanguages.isEmpty, let language,
           !options.expectedLanguages.map(\.rawValue).contains(language) {
            languageScores = (try? await kit.detectLangauge(audioArray: clip.samples).langProbs) ?? [:]
        }
        try Task.checkCancellation()
        return Transcript(
            text: Self.strip(results.map(\.text).joined(separator: " ")),
            segments: segments,
            language: language,
            languageScores: languageScores
        )
    }

    /// Removes leftover `<|...|>` tokens and outer whitespace.
    static func strip(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
