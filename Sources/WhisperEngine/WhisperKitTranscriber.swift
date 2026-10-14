import Foundation
import VoiceCore
import WhisperKit

/// On-device Whisper. Downloads the model into `downloadBase` on first use,
/// then keeps it loaded for the life of the process.
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
    private var kit: WhisperKit?
    private var loading: Task<WhisperKit, Error>?
    public private(set) var state: LoadState = .notLoaded

    public init(modelName: String, downloadBase: URL) {
        self.modelName = modelName
        self.downloadBase = downloadBase
    }

    public func prepare(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        _ = try await loadedKit(progress: progress)
    }

    private func setState(_ newState: LoadState) {
        state = newState
    }

    private func loadedKit(progress: (@Sendable (Double) -> Void)? = nil) async throws -> WhisperKit {
        if let kit { return kit }
        if let loading { return try await loading.value }
        let name = modelName
        let base = downloadBase
        let task = Task<WhisperKit, Error> {
            self.setState(.downloading(0))
            let folder = try await WhisperKit.download(variant: name, downloadBase: base) { p in
                progress?(p.fractionCompleted)
                Task { await self.setState(.downloading(p.fractionCompleted)) }
            }
            self.setState(.loading)
            let config = WhisperKitConfig(
                modelFolder: folder.path,
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )
            return try await WhisperKit(config)
        }
        loading = task
        do {
            let loaded = try await task.value
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
        let kit = try await loadedKit()
        var decode = DecodingOptions()
        decode.verbose = false
        decode.task = .transcribe
        decode.temperature = 0
        decode.skipSpecialTokens = true
        decode.withoutTimestamps = false
        decode.chunkingStrategy = .vad
        if options.language == .auto {
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
        let results = try await kit.transcribe(audioArray: clip.samples, decodeOptions: decode)
        let segments = results.flatMap(\.segments).map {
            TranscriptSegment(start: Double($0.start), end: Double($0.end), text: Self.strip($0.text))
        }
        return Transcript(
            text: Self.strip(results.map(\.text).joined(separator: " ")),
            segments: segments,
            language: results.first?.language
        )
    }

    /// Removes leftover `<|...|>` tokens and outer whitespace.
    static func strip(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
