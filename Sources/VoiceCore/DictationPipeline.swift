import Foundation

public enum InsertOutcome: Sendable, Equatable {
    case pasted
    case notConsumed
    case failed
}

public enum DictationMode: Sendable, Equatable {
    case ordinary
    case notes
}

/// Where finished text goes. Dictation pastes into the focused app; Notes
/// (sub-project 3) will write into its own editor.
public protocol InsertionTarget: Sendable {
    func insert(_ text: String) async -> InsertOutcome
    /// Clipboard only, never pasted. Used for secure fields.
    func copy(_ text: String) async
}

public protocol FocusProvider: Sendable {
    func snapshot() async -> FocusSnapshot
}

public enum PipelineStage: Sendable, Equatable {
    case transcribing
    case cleaning(model: String)
    case inserting
}

public enum DictationOutcome: String, Codable, Sendable {
    case inserted, insertedInNote, noteDeleted, noteSaveFailed, copiedSecureField, copiedNotConsumed, discardedTooShort, nothingHeard, transcriptionFailed, cancelled
}

public struct DictationResult: Sendable, Equatable {
    public var command: String? = nil
    public var id = UUID()
    public var startedAt: Date
    public var appName: String?
    public var bundleID: String?
    public var style: Style
    public var language: String?
    public var requestedLanguage: SpeechLanguage = .auto
    public var raw: String
    public var cleaned: String?
    public var finalText: String
    /// What would have been pasted with cleanup off: Dictionary
    /// replacements and snippets applied, no text model. *Paste raw* uses it.
    public var uncleanedText = ""
    public var outcome: DictationOutcome
    public var rawReason: RawReason?
    public var errorMessage: String?
    public var projectName: String? = nil
    public var fidelityIssues: [FidelityIssue] = []
    public var fidelityAction: FidelityAction = .raw
    public var isFidelityFallback: Bool { rawReason == .detailChanged && cleaned != nil }
    public var timings: StageTimings

    /// What the app may keep in memory for the menu preview and *Paste last*.
    /// A secure-field result keeps its outcome and app but no text: it is
    /// likely a secret.
    public var recallable: DictationResult {
        guard outcome == .copiedSecureField else { return self }
        var redacted = self
        redacted.command = nil
        redacted.uncleanedText = ""
        redacted.raw = ""
        redacted.cleaned = nil
        redacted.fidelityIssues = []
        redacted.finalText = ""
        return redacted
    }

    /// Nil when nothing reached the user, and for secure fields: a dictation
    /// into a password field is likely a secret and is never logged.
    public var historyEntry: HistoryEntry? {
        switch outcome {
        case .discardedTooShort, .nothingHeard, .transcriptionFailed, .cancelled, .copiedSecureField, .insertedInNote, .noteDeleted, .noteSaveFailed:
            return nil
        case .inserted, .copiedNotConsumed:
            return HistoryEntry(
                id: id, startedAt: startedAt, appName: appName, bundleID: bundleID, style: style,
                language: language, raw: raw, cleaned: cleaned, text: finalText,
                outcome: outcome.rawValue, rawReason: rawReason, timings: timings, command: command,
                fidelityIssues: fidelityIssues.isEmpty ? nil : fidelityIssues
            )
        }
    }
}

public struct DictationPipeline: Sendable {
    public var transcriber: any Transcriber
    public var cleanup: CleanupModel?
    public var insertion: any InsertionTarget
    public var focus: any FocusProvider
    public var settings: AppSettings
    public var vocabulary: Vocabulary
    public var projects: [Project]
    public var minimumDuration: TimeInterval = 0.3
    /// Below this RMS the clip is treated as silence and never transcribed.
    public var silenceRMS: Float = 0.003

    public init(
        transcriber: any Transcriber,
        cleanup: CleanupModel?,
        insertion: any InsertionTarget,
        focus: any FocusProvider,
        settings: AppSettings,
        vocabulary: Vocabulary,
        projects: [Project] = []
    ) {
        self.transcriber = transcriber
        self.cleanup = cleanup
        self.insertion = insertion
        self.focus = focus
        self.settings = settings
        self.vocabulary = vocabulary
        self.projects = projects
    }

    /// Removes Whisper annotations such as `[BLANK_AUDIO]` or `[Music]`.
    /// Parentheses stay: dictated text may use them.
    static func stripPlaceholders(_ text: String) -> String {
        text.replacing(/\[[^\]]*\]/, with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    public func run(
        clip: AudioClip,
        startFocus: FocusSnapshot,
        startedAt: Date,
        mode: DictationMode = .ordinary,
        languageChoice: SpeechLanguage? = nil,
        onStage: @escaping @Sendable (PipelineStage) -> Void
    ) async -> DictationResult {
        let style = mode == .notes
            ? Style.document
            : StyleRouter(overrides: settings.styles.appOverrides).style(for: startFocus)
        let projectMatch = ProjectMatcher.match(focus: startFocus, style: style, projects: projects,
            scope: settings.speech.projectWordsScope, excluding: vocabulary.terms, limit: ProjectWordExtractor.maxWords)
        let vocabulary = vocabulary.with(projectWords: projectMatch.words)
        let requestedLanguage = LanguageResolver(settings: settings.speech).language(for: startFocus, keyChoice: languageChoice)
        var result = DictationResult(
            startedAt: startedAt, appName: startFocus.appName, bundleID: startFocus.bundleID,
            style: style, language: nil, requestedLanguage: requestedLanguage, raw: "", cleaned: nil, finalText: "",
            outcome: .nothingHeard, rawReason: nil, errorMessage: nil,
            timings: StageTimings(recording: clip.duration)
        )
        result.projectName = projectMatch.projectName
        result.fidelityAction = settings.styles.fidelityAction

        guard clip.duration >= minimumDuration else {
            result.outcome = .discardedTooShort
            return result
        }
        guard clip.rms >= silenceRMS else {
            result.outcome = .nothingHeard
            return result
        }

        // Transcribe
        onStage(.transcribing)
        var mark = Date()
        let options = TranscriptionOptions(
            language: requestedLanguage,
            prompt: settings.speech.useVocabularyHints
                ? vocabulary.whisperPrompt(example: requestedLanguage == .vi && settings.speech.keepEnglishWords ? Vocabulary.mixedExample : nil)
                : ""
        )
        let transcript: Transcript
        do {
            transcript = try await transcriber.transcribe(clip, options: options)
        } catch where Self.isCancellation(error) {
            result.outcome = .cancelled
            result.timings.transcribe = Date().timeIntervalSince(mark)
            return result
        } catch {
            result.outcome = .transcriptionFailed
            result.errorMessage = error.localizedDescription
            result.timings.transcribe = Date().timeIntervalSince(mark)
            return result
        }
        result.timings.transcribe = Date().timeIntervalSince(mark)
        result.language = transcript.language
        let raw = HallucinationFilter.strip(Self.stripPlaceholders(transcript.text))
        result.raw = raw
        guard !raw.isEmpty, !HallucinationFilter.isHallucination(raw) else {
            result.outcome = .nothingHeard
            return result
        }

        // Apply Dictionary corrections before protecting snippets. The
        // snippet text itself remains outside the text model request.
        let protected = SnippetExpander.protect(vocabulary.applyReplacements(to: raw), snippets: vocabulary.snippets)
        var text = protected.text
        var cleanedAccepted = false
        var heldCleaned: String?

        // Clean
        if let cleanup, settings.cleanupEnabled, settings.styles.isCleanupEnabled(for: style) {
            onStage(.cleaning(model: cleanup.modelID))
            mark = Date()
            var built = PromptBuilder(customRules: settings.styles.customRules).request(
                raw: protected.text, style: style, focus: startFocus,
                vocabulary: vocabulary.with(projectWords: ProjectMatcher.prioritized(vocabulary.projectWords, heard: raw)),
                modelID: cleanup.modelID, disableThinking: cleanup.disableThinking,
                language: requestedLanguage, keepEnglishWords: settings.speech.keepEnglishWords
            )
            built.maxTokens = min(1024, 2 * protected.text.count + 50)
            let request = built
            do {
                let output = try await withTimeout(seconds: CleanupTimeout.limit(base: cleanup.timeoutSeconds, raw: protected.text)) {
                    try await cleanup.model.clean(request)
                }
                switch OutputSanitizer.sanitize(output, raw: protected.text) {
                case .accepted(let cleaned) where protected.isIntact(cleaned):
                    let issues = FidelityCheck.issues(raw: protected.text, cleaned: cleaned)
                    result.fidelityIssues = issues
                    if !issues.isEmpty && result.fidelityAction == .raw {
                        result.rawReason = .detailChanged
                        heldCleaned = cleaned
                    } else {
                        text = cleaned
                        cleanedAccepted = true
                    }
                case .accepted:
                    result.rawReason = .placeholderLost
                case .rejected(let reason):
                    result.rawReason = reason
                }
            } catch is TimeoutError {
                result.rawReason = .modelTimeout
            } catch {
                result.rawReason = .modelError
                result.errorMessage = error.localizedDescription
            }
            result.timings.clean = Date().timeIntervalSince(mark)
        } else {
            result.rawReason = .cleanupOff
        }

        text = protected.fill(vocabulary.applyReplacements(to: text))
        if cleanedAccepted { result.cleaned = text }
        if let heldCleaned { result.cleaned = protected.fill(vocabulary.applyReplacements(to: heldCleaned)) }
        result.finalText = Self.trimmed(text, style: style)
        result.uncleanedText = Self.trimmed(protected.fill(vocabulary.applyReplacements(to: protected.text)), style: style)
        text = result.finalText

        // Insert
        onStage(.inserting)
        mark = Date()
        if mode == .notes {
            switch await insertion.insert(text) {
            case .pasted: result.outcome = .insertedInNote
            case .notConsumed: result.outcome = .noteDeleted
            case .failed: result.outcome = .noteSaveFailed
            }
        } else {
            let current = await focus.snapshot()
            // A run that began in a secure field stays secure even if focus moved.
            if startFocus.isSecure || current.isSecure {
                await insertion.copy(text)
                result.outcome = .copiedSecureField
            } else {
                switch await insertion.insert(text) {
                case .pasted: result.outcome = .inserted
                case .notConsumed: result.outcome = .copiedNotConsumed
                case .failed: result.outcome = .copiedNotConsumed
                }
            }
        }
        result.timings.insert = Date().timeIntervalSince(mark)
        return result
    }

    /// Terminal text drops a single trailing period.
    static func trimmed(_ text: String, style: Style) -> String {
        guard style == .terminal, text.hasSuffix("."), !text.hasSuffix("..") else { return text }
        return String(text.dropLast())
    }

    /// Cancellation by type, never by error text: Swift's `CancellationError`,
    /// URLSession's `.cancelled`, or any error thrown after the task was
    /// cancelled (engines that report a stop as their own error).
    static func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled || error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}
