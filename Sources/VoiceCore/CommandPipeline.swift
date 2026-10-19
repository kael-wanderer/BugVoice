import Foundation

public enum CommandFailure: Equatable, Sendable {
    case noModel, selectionTooLong, transcriptionFailed, modelFailed, outputTooLong, emptyOutput
    public var title: String {
        switch self {
        case .noModel: "Command mode needs a text model"
        case .selectionTooLong: "Selection too long"
        case .outputTooLong: "The model's answer was too long"
        case .transcriptionFailed, .modelFailed, .emptyOutput: "Command failed"
        }
    }
    public var detail: String? {
        switch self {
        case .noModel: "choose one in Settings › Models"
        case .selectionTooLong: "8,000 characters at most"
        case .transcriptionFailed: "could not transcribe"
        case .modelFailed: "model unavailable"
        case .outputTooLong: "nothing was changed"
        case .emptyOutput: "the model returned nothing"
        }
    }
}
public enum CommandRun: Equatable, Sendable {
    case ready(DictationResult)
    case failed(CommandFailure)
    case nothingHeard
    case cancelled
}
public struct CommandPipeline: Sendable {
    public static let timeoutSeconds: Double = 30
    private let transcriber: any Transcriber
    private let model: CleanupModel?
    private let settings: AppSettings
    private let vocabulary: Vocabulary
    private let timeout: Double
    public init(transcriber: any Transcriber, model: CleanupModel?, settings: AppSettings, vocabulary: Vocabulary,
                timeout: Double = CommandPipeline.timeoutSeconds) {
        self.transcriber = transcriber
        self.model = model
        self.settings = settings
        self.vocabulary = vocabulary
        self.timeout = timeout
    }
    public func run(clip: AudioClip, selection: String?, startFocus: FocusSnapshot, startedAt: Date,
                    languageChoice: SpeechLanguage? = nil,
                    onStage: @escaping @Sendable (PipelineStage) -> Void) async -> CommandRun {
        guard let model else { return .failed(.noModel) }
        guard (selection?.count ?? 0) <= CommandPrompt.maxSelection else { return .failed(.selectionTooLong) }
        guard !Task.isCancelled else { return .cancelled }
        guard clip.duration >= 0.3, clip.rms >= 0.003 else { return .nothingHeard }
        let language = LanguageResolver(settings: settings.speech).language(for: startFocus, keyChoice: languageChoice)
        let style = StyleRouter(overrides: settings.styles.appOverrides).style(for: startFocus)
        var timings = StageTimings(recording: clip.duration)
        onStage(.transcribing)
        var mark = Date()
        let transcript: Transcript
        do {
            transcript = try await transcriber.transcribe(clip, options: TranscriptionOptions(
                language: language, prompt: settings.speech.useVocabularyHints ? vocabulary.whisperPrompt() : ""))
            try Task.checkCancellation()
        } catch {
            return DictationPipeline.isCancellation(error) ? .cancelled : .failed(.transcriptionFailed)
        }
        timings.transcribe = Date().timeIntervalSince(mark)
        let instruction = HallucinationFilter.strip(DictationPipeline.stripPlaceholders(transcript.text))
        guard !instruction.isEmpty, !HallucinationFilter.isHallucination(instruction) else { return .nothingHeard }
        let request = CommandPrompt.request(instruction: instruction, selection: selection, style: style, focus: startFocus,
            vocabulary: vocabulary, language: language, keepEnglishWords: settings.speech.keepEnglishWords,
            modelID: model.modelID, disableThinking: model.disableThinking)
        onStage(.cleaning(model: model.modelID))
        mark = Date()
        let output: String
        do {
            output = try await withTimeout(seconds: timeout) { try await model.model.clean(request) }
            try Task.checkCancellation()
        } catch {
            return DictationPipeline.isCancellation(error) ? .cancelled : .failed(.modelFailed)
        }
        timings.clean = Date().timeIntervalSince(mark)
        switch CommandOutput.sanitize(output, selection: selection) {
        case .failure(.empty): return .failed(.emptyOutput)
        case .failure(.tooLong): return .failed(.outputTooLong)
        case .success(let text):
            return .ready(DictationResult(command: instruction, startedAt: startedAt, appName: startFocus.appName,
                bundleID: startFocus.bundleID, style: style, language: transcript.language, requestedLanguage: language,
                raw: selection ?? "", cleaned: text, finalText: text, uncleanedText: selection ?? "",
                outcome: .nothingHeard, rawReason: nil, errorMessage: nil, timings: timings))
        }
    }
}
public enum CommandPasteDecision: Equatable, Sendable {
    case paste
    case copy(reason: String)
    case secure
}
public enum CommandPaste {
    public static let selectionChanged = "the selection changed while rewriting"
    public static let terminal = "terminals do not replace a selection"
    public static func decide(start: FocusSnapshot, now: FocusSnapshot, sameElement: Bool, style: Style) -> CommandPasteDecision {
        if now.isSecure { return .secure }
        if style == .terminal { return .copy(reason: terminal) }
        if !sameElement { return .copy(reason: selectionChanged) }
        if let selected = start.selectedText, selected != now.selectedText { return .copy(reason: selectionChanged) }
        return .paste
    }
}
