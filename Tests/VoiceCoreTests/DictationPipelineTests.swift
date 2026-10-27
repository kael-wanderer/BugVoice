import Foundation
import Testing
@testable import VoiceCore

struct DictationPipelineTests {
    static let dictionaryVocab = Vocabulary(
        terms: ["OpenWhispr"],
        replacements: [.init(spoken: "open whisper", written: "OpenWhispr")],
        snippets: [Snippet(trigger: "my linkedin", text: "linkedin.com/in/kael")]
    )
    func pipeline(
        transcriber: any Transcriber = FakeTranscriber(),
        model: (any TextModel)? = FakeModel(),
        insertion: RecordingInsertion = RecordingInsertion(),
        focusAtInsert: FocusSnapshot = notionFocus,
        settings: AppSettings = AppSettings(),
        vocabulary: Vocabulary = Vocabulary(),
        timeout: Double = 3
    ) -> DictationPipeline {
        DictationPipeline(
            transcriber: transcriber,
            cleanup: model.map { CleanupModel(model: $0, modelID: "qwen3.8-27b-mlx", shortName: "Qwen", disableThinking: true, timeoutSeconds: timeout) },
            insertion: insertion, focus: FixedFocus(focus: focusAtInsert), settings: settings, vocabulary: vocabulary
        )
    }

    @Test func ruleLanguageReachesTranscriber() async {
        var settings = AppSettings()
        settings.speech.appLanguages = [AppLanguageRule(kind: .app, id: "com.stablyai.orca", language: .en)]
        let transcriber = OptionsTranscriber()
        let model = RecordingModel()
        let focus = FocusSnapshot(bundleID: "com.stablyai.orca")
        _ = await pipeline(transcriber: transcriber, model: model, focusAtInsert: focus, settings: settings)
            .run(clip: speechClip, startFocus: focus, startedAt: Date(), onStage: { _ in })
        #expect(await transcriber.options?.language == .en)
        #expect(await model.requests.first?.system.contains(Vocabulary.mixedExample) == false)
    }

    @Test func projectWordsReachPrompts() async {
        var settings = AppSettings()
        settings.styles.cleanupEnabled[Style.terminal.rawValue] = true
        settings.speech.projectWordsScope = .codingApps
        let focus = FocusSnapshot(appName: "Ghostty", bundleID: "com.mitchellh.ghostty", windowTitle: "BugVoice")
        let project = Project(path: "/tmp/BugVoice", name: "BugVoice", words: [ProjectWord(word: "AppModel", rank: 10)])
        let transcriber = OptionsTranscriber()
        let model = RecordingModel()
        let pipeline = DictationPipeline(transcriber: transcriber,
            cleanup: CleanupModel(model: model, modelID: "test", shortName: "Test", disableThinking: false, timeoutSeconds: 3),
            insertion: RecordingInsertion(), focus: FixedFocus(focus: focus), settings: settings, vocabulary: Vocabulary(), projects: [project])
        let result = await pipeline.run(clip: speechClip, startFocus: focus, startedAt: Date(), onStage: { _ in })
        #expect(await transcriber.options?.prompt.contains("AppModel") == true)
        #expect(await model.requests.first?.system.contains("Code names from the current project.") == true)
        #expect(result.projectName == "BugVoice")
    }

    @Test func heardWordBeyondLimitReachesCleanup() async {
        var settings = AppSettings()
        settings.styles.cleanupEnabled[Style.terminal.rawValue] = true
        let focus = FocusSnapshot(appName: "Ghostty", bundleID: "com.mitchellh.ghostty", windowTitle: "BugVoice")
        var words = (0..<300).map { ProjectWord(word: "filler\($0)Name", rank: 400 - $0) }
        words.insert(ProjectWord(word: "replaceLast", rank: 1), at: 250)
        let model = RecordingModel()
        let pipeline = DictationPipeline(transcriber: TextTranscriber(text: "check replace last"),
            cleanup: CleanupModel(model: model, modelID: "test", shortName: "Test", disableThinking: false, timeoutSeconds: 3),
            insertion: RecordingInsertion(), focus: FixedFocus(focus: focus), settings: settings, vocabulary: Vocabulary(),
            projects: [Project(path: "/tmp/BugVoice", name: "BugVoice", words: words)])
        _ = await pipeline.run(clip: speechClip, startFocus: focus, startedAt: Date(), onStage: { _ in })
        let system = await model.requests.first?.system ?? ""
        #expect(system.contains("replaceLast"))
        #expect(!system.contains("filler200Name"))
    }

    @Test func vietnameseGetsExample() async {
        let transcriber = OptionsTranscriber()
        let model = RecordingModel()
        let focus = FocusSnapshot(bundleID: "com.anthropic.claudefordesktop")
        _ = await pipeline(transcriber: transcriber, model: model, focusAtInsert: focus)
            .run(clip: speechClip, startFocus: focus, startedAt: Date(), onStage: { _ in })
        #expect(await transcriber.options?.language == .vi)
        #expect(await transcriber.options?.prompt.hasPrefix(Vocabulary.mixedExample) == true)
        #expect(await model.requests.first?.system.contains(PromptBuilder.keepEnglishRule) == true)
    }

    @Test func autoGetsNoExample() async {
        let transcriber = OptionsTranscriber()
        let focus = notionFocus
        let result = await pipeline(transcriber: transcriber, focusAtInsert: focus)
            .run(clip: speechClip, startFocus: focus, startedAt: Date(), onStage: { _ in })
        #expect(await transcriber.options?.language == .auto)
        #expect(await transcriber.options?.prompt.contains(Vocabulary.mixedExample) == false)
        #expect(result.requestedLanguage == .auto)
    }

    @Test func choiceOverridesRule() async {
        var settings = AppSettings()
        settings.speech.appLanguages = [AppLanguageRule(kind: .app, id: "com.stablyai.orca", language: .en)]
        let transcriber = OptionsTranscriber()
        let focus = FocusSnapshot(bundleID: "com.stablyai.orca")
        let result = await pipeline(transcriber: transcriber, focusAtInsert: focus, settings: settings)
            .run(clip: speechClip, startFocus: focus, startedAt: Date(), languageChoice: .vi, onStage: { _ in })
        #expect(await transcriber.options?.language == .vi)
        #expect(result.requestedLanguage == .vi)
    }

    @Test func documentHappyPathCleansAndPastes() async {
        let insertion = RecordingInsertion()
        let r = await pipeline(insertion: insertion).run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .inserted)
        #expect(r.style == .document)
        #expect(r.raw == "hello world")
        #expect(r.cleaned == "Hello world.")
        #expect(r.finalText == "Hello world.")
        #expect(r.rawReason == nil)
        #expect(await insertion.inserted == ["Hello world."])
        #expect(r.historyEntry?.text == "Hello world.")
    }

    @Test func ordinaryDictationPreservesPasteTextBytesOutsideBugVoice() async {
        var settings = AppSettings()
        settings.cleanupEnabled = false
        let insertion = RecordingInsertion()
        let safari = FocusSnapshot(appName: "Safari", bundleID: "com.apple.Safari")
        let result = await pipeline(
            transcriber: FakeTranscriber(text: "xin chào world"),
            model: nil,
            insertion: insertion,
            focusAtInsert: safari,
            settings: settings
        ).run(
            clip: speechClip,
            startFocus: safari,
            startedAt: Date(),
            onStage: { _ in }
        )

        let expected = "xin chào world"
        #expect(result.outcome == .inserted)
        #expect(Array(result.finalText.utf8) == Array(expected.utf8))
        #expect(await insertion.inserted.count == 1)
        #expect(await insertion.inserted.first.map { Array($0.utf8) } == Array(expected.utf8))
        #expect(await insertion.copied.isEmpty)
    }

    @Test func terminalSkipsModelAndDropsTrailingPeriod() async {
        let insertion = RecordingInsertion()
        let r = await pipeline(transcriber: FakeTranscriber(text: "run swift test."), insertion: insertion, focusAtInsert: terminalFocus)
            .run(clip: speechClip, startFocus: terminalFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.style == .terminal)
        #expect(r.rawReason == .cleanupOff)
        #expect(r.finalText == "run swift test")
        #expect(await insertion.inserted == ["run swift test"])
    }

    @Test func uncleanedTextMatchesCleanupOffPaste() async {
        let r = await pipeline(transcriber: FakeTranscriber(text: "run swift test."), focusAtInsert: terminalFocus)
            .run(clip: speechClip, startFocus: terminalFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.uncleanedText == r.finalText)
    }

    @Test func uncleanedTextKeepsReplacementsWithoutCleanup() async {
        let v = Vocabulary.parse("hello => Xin chào")
        let r = await pipeline(model: FakeModel(output: "Greetings, world."), vocabulary: v)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.finalText == "Greetings, world.")
        #expect(r.uncleanedText == "Xin chào world")
    }

    @Test func terminalKeepsEllipsis() async {
        let r = await pipeline(transcriber: FakeTranscriber(text: "wait..."), focusAtInsert: terminalFocus)
            .run(clip: speechClip, startFocus: terminalFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.finalText == "wait...")
    }

    @Test func masterSwitchOffSkipsModel() async {
        var s = AppSettings()
        s.cleanupEnabled = false
        let r = await pipeline(settings: s).run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.rawReason == .cleanupOff)
        #expect(r.finalText == "hello world")
    }

    @Test func shortClipIsDiscarded() async {
        let insertion = RecordingInsertion()
        let r = await pipeline(insertion: insertion).run(clip: AudioClip(samples: Array(repeating: 0.3, count: 3_000)), startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .discardedTooShort)
        #expect(r.historyEntry == nil)
        #expect(await insertion.inserted.isEmpty)
    }

    @Test func silentClipIsNothingHeard() async {
        let r = await pipeline().run(clip: AudioClip(samples: Array(repeating: 0.0001, count: 16_000)), startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .nothingHeard)
    }

    @Test func emptyTranscriptIsNothingHeard() async {
        let r = await pipeline(transcriber: FakeTranscriber(text: "  ")).run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .nothingHeard)
    }

    @Test func hallucinationIsNothingHeard() async {
        let insertion = RecordingInsertion()
        let r = await pipeline(transcriber: FakeTranscriber(text: "Thank you."), insertion: insertion).run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .nothingHeard)
        #expect(await insertion.inserted.isEmpty)
    }

    @Test func transcriptionErrorIsReported() async {
        struct Boom: Error {}
        let r = await pipeline(transcriber: FakeTranscriber(error: Boom())).run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .transcriptionFailed)
        #expect(r.errorMessage != nil)
    }

    @Test func urlSessionCancellationIsQuietCancellation() async {
        let r = await pipeline(transcriber: FakeTranscriber(error: URLError(.cancelled))).run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .cancelled)
        #expect(r.errorMessage == nil)
    }

    @Test func anyErrorAfterTaskCancellationIsQuietCancellation() async {
        struct EngineStopped: Error {}
        let pipeline = pipeline(transcriber: FakeTranscriber(error: EngineStopped()))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await pipeline.run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        }
        let result = await task.value
        #expect(result.outcome == .cancelled)
        #expect(result.errorMessage == nil)
    }

    @Test func cancelledPriorityRequestIsQuietCancellation() async {
        let stages = StageRecorder()
        let pipeline = pipeline(transcriber: PriorityTranscriber(base: FakeTranscriber()))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await pipeline.run(
                clip: speechClip,
                startFocus: notionFocus,
                startedAt: Date(),
                onStage: { stages.add($0) }
            )
        }

        let result = await task.value

        #expect(result.outcome == .cancelled)
        #expect(result.errorMessage == nil)
        #expect(stages.all == [.transcribing])
        #expect(result.historyEntry == nil)
    }

    @Test func slowModelTimesOutToRaw() async {
        let start = Date()
        let r = await pipeline(model: FakeModel(delay: 5), timeout: 0.2).run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.rawReason == .modelTimeout)
        #expect(r.finalText == "hello world")
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test func longDictationGetsMoreTimeToClean() async {
        let raw = Array(repeating: "note", count: 20).joined(separator: " ")
        let cleaned = "Note " + Array(repeating: "note", count: 19).joined(separator: " ") + "."
        // 0.2 s base + 0.1 s per word = 2.2 s, so a 1 s model still finishes.
        let r = await pipeline(
            transcriber: FakeTranscriber(text: raw),
            model: FakeModel(output: cleaned, delay: 1),
            timeout: 0.2
        ).run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.rawReason == nil)
        #expect(r.finalText == cleaned)
    }

    @Test func modelErrorFallsBackToRaw() async {
        let r = await pipeline(model: FakeModel(error: ProviderError.http(status: 500, body: "x"))).run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.rawReason == .modelError)
        #expect(r.outcome == .inserted)
        #expect(r.finalText == "hello world")
    }

    @Test func modelChatterFallsBackToRaw() async {
        let chatter = String(repeating: "Sure! Here is a poem about the sea. ", count: 5)
        let r = await pipeline(model: FakeModel(output: chatter)).run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.rawReason == .tooLong)
        #expect(r.finalText == "hello world")
    }

    @Test func noModelConfiguredIsCleanupOff() async {
        let r = await pipeline(model: nil).run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.rawReason == .cleanupOff)
    }

    @Test func secureFieldAtInsertTimeCopiesOnly() async {
        let insertion = RecordingInsertion()
        let r = await pipeline(insertion: insertion, focusAtInsert: FocusSnapshot(bundleID: "com.apple.Safari", isSecure: true))
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .copiedSecureField)
        #expect(await insertion.inserted.isEmpty)
        #expect(await insertion.copied == ["Hello world."])
    }

    @Test func secureFieldAtStartCopiesOnlyEvenWhenFocusMoves() async {
        let insertion = RecordingInsertion()
        let r = await pipeline(insertion: insertion, focusAtInsert: notionFocus)
            .run(clip: speechClip, startFocus: FocusSnapshot(bundleID: "com.apple.Safari", isSecure: true),
                 startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .copiedSecureField)
        #expect(await insertion.inserted.isEmpty)
        #expect(await insertion.copied.count == 1)
        #expect(r.historyEntry == nil)
        #expect(r.recallable.finalText.isEmpty)
    }

    @Test func secureFieldResultHasNoHistoryEntry() async {
        let r = await pipeline(focusAtInsert: FocusSnapshot(bundleID: "com.apple.Safari", isSecure: true))
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .copiedSecureField)
        #expect(r.historyEntry == nil)
    }

    @Test func notesModeForcesDocumentStyleAndNeverCopiesAfterFocusChanges() async {
        var settings = AppSettings()
        settings.cleanupEnabled = false
        let insertion = RecordingInsertion()
        let result = await pipeline(
            model: nil,
            insertion: insertion,
            focusAtInsert: FocusSnapshot(bundleID: "com.apple.Safari", isSecure: true),
            settings: settings
        ).run(
            clip: speechClip,
            startFocus: terminalFocus,
            startedAt: Date(),
            mode: .notes,
            onStage: { _ in }
        )

        #expect(result.style == .document)
        #expect(result.finalText == "hello world")
        #expect(result.outcome == .insertedInNote)
        #expect(result.historyEntry == nil)
        #expect(await insertion.inserted == ["hello world"])
        #expect(await insertion.copied.isEmpty)
    }

    @Test func notesTargetNotConsumedMeansCapturedNoteWasDeleted() async {
        var settings = AppSettings()
        settings.cleanupEnabled = false
        let result = await pipeline(
            model: nil,
            insertion: RecordingInsertion(outcome: .notConsumed),
            settings: settings
        ).run(
            clip: speechClip,
            startFocus: notionFocus,
            startedAt: Date(),
            mode: .notes,
            onStage: { _ in }
        )
        #expect(result.outcome == .noteDeleted)
        #expect(result.historyEntry == nil)
    }

    @Test func notesInsertionFailureKeepsTextOutOfHistoryAndClipboard() async {
        var settings = AppSettings()
        settings.cleanupEnabled = false
        let insertion = RecordingInsertion(outcome: .failed)
        let result = await pipeline(model: nil, insertion: insertion, settings: settings).run(
            clip: speechClip,
            startFocus: notionFocus,
            startedAt: Date(),
            mode: .notes,
            onStage: { _ in }
        )
        #expect(result.outcome == .noteSaveFailed)
        #expect(result.finalText == "hello world")
        #expect(result.historyEntry == nil)
        #expect(await insertion.copied.isEmpty)
    }

    @Test func notConsumedIsReported() async {
        let r = await pipeline(insertion: RecordingInsertion(outcome: .notConsumed)).run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .copiedNotConsumed)
        #expect(r.historyEntry != nil)
    }

    @Test func replacementsApplyAfterCleanup() async {
        let v = Vocabulary.parse("hello => Xin chào")
        let r = await pipeline(model: FakeModel(output: "hello world."), vocabulary: v).run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.finalText == "Xin chào world.")
    }

    @Test func stagesAreReportedInOrder() async {
        let stages = StageRecorder()
        _ = await pipeline().run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { stage in stages.add(stage) })
        #expect(stages.all == [.transcribing, .cleaning(model: "qwen3.8-27b-mlx"), .inserting])
    }

    @Test func cleanupUsesResolvedModelIDAndThinkingFlag() async {
        let model = RecordingModel()
        let p = DictationPipeline(
            transcriber: FakeTranscriber(), cleanup: CleanupModel(model: model, modelID: "llama-3", disableThinking: false, timeoutSeconds: 3),
            insertion: RecordingInsertion(), focus: FixedFocus(focus: notionFocus), settings: AppSettings(), vocabulary: Vocabulary()
        )
        let stages = StageRecorder()
        _ = await p.run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { stages.add($0) })
        let request = await model.requests.first
        #expect(request?.disableThinking == false)
        #expect(request?.user.hasSuffix("/no_think") == false)
        #expect(stages.all.contains(.cleaning(model: "llama-3")))
    }

    @Test func unavailableModelPastesRawWithModelError() async {
        let reason = "The connection for Dictation cleanup was deleted. Choose another in Settings → Models."
        let r = await pipeline(model: FakeModel(error: ProviderError.unavailable(reason)))
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.rawReason == .modelError)
        #expect(r.finalText == "hello world")
    }

    @Test func whisperPlaceholdersAreStrippedBeforePasting() async {
        var s = AppSettings()
        s.cleanupEnabled = false
        let insertion = RecordingInsertion()
        let r = await pipeline(transcriber: FakeTranscriber(text: "[BLANK_AUDIO] merge the  branch [Music]"), insertion: insertion, settings: s)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.raw == "merge the branch")
        #expect(r.finalText == "merge the branch")
        #expect(await insertion.inserted == ["merge the branch"])
        #expect(r.historyEntry?.raw == "merge the branch")
    }

    @Test func placeholderStripWorksWithEchoingModel() async {
        let model = RecordingModel()
        let r = await pipeline(transcriber: FakeTranscriber(text: "[BLANK_AUDIO] merge the branch"), model: model)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.finalText == "merge the branch")
        #expect(await model.requests.first?.user.contains("[BLANK_AUDIO]") == false)
    }

    @Test func parenthesesAreKept() async {
        var s = AppSettings()
        s.cleanupEnabled = false
        let r = await pipeline(transcriber: FakeTranscriber(text: "call foo (the old one) now"), settings: s)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.finalText == "call foo (the old one) now")
    }

    @Test func placeholderOnlyTranscriptIsNothingHeard() async {
        let insertion = RecordingInsertion()
        let r = await pipeline(transcriber: FakeTranscriber(text: "[BLANK_AUDIO]"), insertion: insertion)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .nothingHeard)
        #expect(await insertion.inserted.isEmpty)
    }

    @Test func maxTokensScalesWithRawLength() async {
        let short = RecordingModel()
        _ = await pipeline(transcriber: FakeTranscriber(text: "hello world"), model: short)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(await short.requests.first?.maxTokens == 2 * 11 + 50)

        let long = RecordingModel()
        _ = await pipeline(transcriber: FakeTranscriber(text: String(repeating: "a", count: 600)), model: long)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(await long.requests.first?.maxTokens == 1024)
    }

    @Test func timeoutCancelsInFlightModelCall() async {
        let model = RecordingModel(delay: 5)
        let r = await pipeline(model: model, timeout: 0.1).run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.rawReason == .modelTimeout)
        #expect(await model.wasCancelled)
    }

    @Test func heardAsIsFixedBeforeCleanupAndRawStaysOriginal() async {
        let model = RecordingModel()
        let r = await pipeline(transcriber: FakeTranscriber(text: "open whisper is great"), model: model, vocabulary: Self.dictionaryVocab)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(await model.requests.first?.user.contains("OpenWhispr is great") == true)
        #expect(r.raw == "open whisper is great")
        #expect(r.finalText == "OpenWhispr is great")
    }

    @Test func snippetSurvivesCleanupAndNeverReachesModel() async {
        let model = RecordingModel(output: "Here is ⟦S1⟧.")
        let r = await pipeline(transcriber: FakeTranscriber(text: "here is my linkedin"), model: model, vocabulary: Self.dictionaryVocab)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        let request = await model.requests.first
        #expect(request?.user.contains("⟦S1⟧") == true)
        #expect(request?.user.contains("linkedin.com") == false)
        #expect(request?.system.contains("linkedin.com") == false)
        #expect(request?.system.contains("Tokens like ⟦S1⟧ are placeholders") == true)
        #expect(r.rawReason == nil)
        #expect(r.cleaned == "Here is linkedin.com/in/kael.")
        #expect(r.finalText == "Here is linkedin.com/in/kael.")
        #expect(r.raw == "here is my linkedin")
    }

    @Test(arguments: ["Here is my profile.", "Here is ⟦S1⟧ ⟦S1⟧.", "Here is [S1].", "Here is ⟦S1⟧ and ⟦S2⟧."])
    func mangledPlaceholderDiscardsCleanedText(output: String) async {
        let insertion = RecordingInsertion()
        let r = await pipeline(transcriber: FakeTranscriber(text: "here is my linkedin"), model: FakeModel(output: output), insertion: insertion, vocabulary: Self.dictionaryVocab)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .inserted)
        #expect(r.rawReason == .placeholderLost)
        #expect(r.cleaned == nil)
        #expect(r.finalText == "here is linkedin.com/in/kael")
        #expect(await insertion.inserted == ["here is linkedin.com/in/kael"])
    }

    @Test func cleanupOffStillFillsSnippet() async {
        var s = AppSettings()
        s.cleanupEnabled = false
        let r = await pipeline(transcriber: FakeTranscriber(text: "here is my linkedin"), settings: s, vocabulary: Self.dictionaryVocab)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.rawReason == .cleanupOff)
        #expect(r.finalText == "here is linkedin.com/in/kael")
    }

    @Test func terminalCleansWhenItsSwitchIsOn() async {
        var s = AppSettings()
        s.styles.cleanupEnabled[Style.terminal.rawValue] = true
        let model = RecordingModel(output: "git status")
        let r = await pipeline(transcriber: FakeTranscriber(text: "um git status"), model: model, focusAtInsert: terminalFocus, settings: s)
            .run(clip: speechClip, startFocus: terminalFocus, startedAt: Date(), onStage: { _ in })
        #expect(await model.requests.count == 1)
        #expect(r.rawReason == nil)
        #expect(r.finalText == "git status")
    }

    @Test func terminalFillsSnippetWithoutModelCall() async {
        let model = RecordingModel()
        let r = await pipeline(transcriber: FakeTranscriber(text: "open my linkedin"), model: model, focusAtInsert: terminalFocus, vocabulary: Self.dictionaryVocab)
            .run(clip: speechClip, startFocus: terminalFocus, startedAt: Date(), onStage: { _ in })
        #expect(await model.requests.isEmpty)
        #expect(r.finalText == "open linkedin.com/in/kael")
    }

    @Test func secureFieldCopiesFilledTextOnly() async {
        let insertion = RecordingInsertion()
        let r = await pipeline(transcriber: FakeTranscriber(text: "here is my linkedin"), model: nil, insertion: insertion,
                               focusAtInsert: FocusSnapshot(bundleID: "com.apple.Safari", isSecure: true), vocabulary: Self.dictionaryVocab)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .copiedSecureField)
        #expect(r.historyEntry == nil)
        #expect(await insertion.inserted.isEmpty)
        #expect(await insertion.copied == ["here is linkedin.com/in/kael"])
    }
}

private struct TextTranscriber: Transcriber {
    let text: String
    func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript {
        Transcript(text: text, language: "en")
    }
}

private actor OptionsTranscriber: Transcriber {
    private(set) var options: TranscriptionOptions?
    func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript {
        self.options = options
        return Transcript(text: "hello world", language: options.language == .auto ? "en" : options.language.rawValue)
    }
}

final class StageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stages: [PipelineStage] = []
    func add(_ s: PipelineStage) { lock.withLock { stages.append(s) } }
    var all: [PipelineStage] { lock.withLock { stages } }
}

extension DictationPipelineTests {
    @Test func fallbackPastesRawAndKeepsCleaned() async {
        let insertion = RecordingInsertion()
        let r = await pipeline(transcriber: FakeTranscriber(text: "we should not ship Friday"), model: FakeModel(output: "We should ship Friday."), insertion: insertion)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.rawReason == .detailChanged)
        #expect(r.finalText == "we should not ship Friday")
        #expect(r.cleaned == "We should ship Friday.")
        #expect(r.fidelityIssues.map(\.kind) == [.negation])
        #expect(r.isFidelityFallback)
        #expect(await insertion.inserted == [r.uncleanedText])
        #expect(r.historyEntry?.cleaned == r.cleaned)
        #expect(r.historyEntry?.fidelityIssues == r.fidelityIssues)
    }

    @Test func warnPastesCleaned() async {
        var settings = AppSettings(); settings.styles.fidelityAction = .warn
        let r = await pipeline(transcriber: FakeTranscriber(text: "we should not ship Friday"), model: FakeModel(output: "We should ship Friday."), settings: settings)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.rawReason == nil && r.finalText == "We should ship Friday." && r.fidelityIssues.count == 1 && r.fidelityAction == .warn)
    }

    @Test func offStillRecords() async {
        var settings = AppSettings(); settings.styles.fidelityAction = .off
        let r = await pipeline(transcriber: FakeTranscriber(text: "we should not ship Friday"), model: FakeModel(output: "We should ship Friday."), settings: settings)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.rawReason == nil && r.finalText == "We should ship Friday.")
        #expect(r.fidelityIssues.count == 1 && r.fidelityAction == .off)
    }

    @Test func cleanPassHasNoIssues() async {
        let r = await pipeline().run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.fidelityIssues.isEmpty && r.rawReason == nil)
    }

    @Test func secureFieldDropsIssues() async {
        let r = await pipeline(transcriber: FakeTranscriber(text: "we should not ship Friday"), model: FakeModel(output: "We should ship Friday."), focusAtInsert: FocusSnapshot(isSecure: true))
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .copiedSecureField)
        #expect(r.fidelityIssues.count == 1)
        #expect(r.recallable.fidelityIssues.isEmpty)
        #expect(r.recallable.cleaned == nil && r.historyEntry == nil)
    }

    @Test func notesReceiveFidelityFallback() async {
        let insertion = RecordingInsertion()
        let r = await pipeline(transcriber: FakeTranscriber(text: "we should not ship Friday"), model: FakeModel(output: "We should ship Friday."), insertion: insertion)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), mode: .notes, onStage: { _ in })
        #expect(r.outcome == .insertedInNote && r.isFidelityFallback)
        #expect(await insertion.inserted == [r.uncleanedText])
    }

    @Test func fidelityRunsOnProtectedDictionaryText() async {
        let r = await pipeline(transcriber: FakeTranscriber(text: "open whisper my linkedin"), model: FakeModel(output: "OpenWhispr ⟦S1⟧"), vocabulary: Self.dictionaryVocab)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.fidelityIssues.isEmpty && r.rawReason == nil)
        #expect(r.finalText == "OpenWhispr linkedin.com/in/kael")
    }
}
