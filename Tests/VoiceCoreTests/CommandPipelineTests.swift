import Foundation
import Testing
@testable import VoiceCore

struct CommandPipelineTests {
    func pipeline(transcriber: any Transcriber = FakeTranscriber(text: "make it formal"), model: (any TextModel)? = FakeModel(output: "Hello team."), timeout: Double = 30) -> CommandPipeline {
        CommandPipeline(transcriber: transcriber, model: model.map {
            CleanupModel(model: $0, modelID: "qwen", disableThinking: true, timeoutSeconds: 3)
        }, settings: AppSettings(), vocabulary: Vocabulary(), timeout: timeout)
    }
    func run(_ p: CommandPipeline, selection: String? = "hi team", clip: AudioClip = speechClip, focus: FocusSnapshot = notionFocus) async -> CommandRun {
        await p.run(clip: clip, selection: selection, startFocus: focus, startedAt: Date(), onStage: { _ in })
    }
    @Test func rewriteReady() async throws {
        guard case .ready(let r) = await run(pipeline()) else { Issue.record("Not ready"); return }
        #expect(r.command == "make it formal")
        #expect(r.raw == "hi team")
        #expect(r.uncleanedText == "hi team")
        #expect(r.finalText == "Hello team.")
    }
    @Test func writeReady() async {
        guard case .ready(let r) = await run(pipeline(), selection: nil) else { Issue.record("Not ready"); return }
        #expect(r.raw == "")
    }
    @Test func noModelFails() async { #expect(await run(pipeline(model: nil)) == .failed(.noModel)) }
    @Test func tooLongSelectionFailsBeforeTranscribing() async {
        let t = CommandOptionsTranscriber()
        #expect(await run(pipeline(transcriber: t), selection: String(repeating: "a", count: 8001)) == .failed(.selectionTooLong))
        #expect(await t.options == nil)
    }
    @Test func silenceIsNothingHeard() async {
        #expect(await run(pipeline(), clip: AudioClip(samples: Array(repeating: 0, count: 16000))) == .nothingHeard)
    }
    @Test func modelErrorFails() async {
        #expect(await run(pipeline(model: FakeModel(error: ProviderError.unavailable("offline")))) == .failed(.modelFailed))
    }
    @Test func slowModelTimesOut() async {
        let start = Date()
        #expect(await run(pipeline(model: FakeModel(delay: 5), timeout: 0.05)) == .failed(.modelFailed))
        #expect(Date().timeIntervalSince(start) < 2)
    }
    @Test func preambleRemoved() async {
        guard case .ready(let r) = await run(pipeline(model: FakeModel(output: "Here is the rewrite:\nHello team."))) else { Issue.record("Not ready"); return }
        #expect(r.finalText == "Hello team.")
    }
    @Test func languageRuleApplies() async {
        let t = CommandOptionsTranscriber()
        _ = await run(pipeline(transcriber: t), focus: FocusSnapshot(bundleID: "com.anthropic.claudefordesktop"))
        #expect(await t.options?.language == .vi)
        #expect(await t.options?.prompt.contains(Vocabulary.mixedExample) == false)
    }
    @Test func pastesWhenUnchanged() { #expect(CommandPaste.decide(start: FocusSnapshot(selectedText: "a"), now: FocusSnapshot(selectedText: "a"), sameElement: true, style: .document) == .paste) }
    @Test func changedSelectionCopies() { #expect(CommandPaste.decide(start: FocusSnapshot(selectedText: "a"), now: FocusSnapshot(selectedText: "b"), sameElement: true, style: .document) == .copy(reason: CommandPaste.selectionChanged)) }
    @Test func otherElementCopies() { #expect(CommandPaste.decide(start: .unknown, now: .unknown, sameElement: false, style: .document) == .copy(reason: CommandPaste.selectionChanged)) }
    @Test func terminalCopies() { #expect(CommandPaste.decide(start: .unknown, now: .unknown, sameElement: true, style: .terminal) == .copy(reason: CommandPaste.terminal)) }
    @Test func secureWins() { #expect(CommandPaste.decide(start: .unknown, now: FocusSnapshot(isSecure: true), sameElement: false, style: .terminal) == .secure) }
    @Test func unreadableSelectionTrustsElement() { #expect(CommandPaste.decide(start: .unknown, now: .unknown, sameElement: true, style: .document) == .paste) }
}
private actor CommandOptionsTranscriber: Transcriber {
    private(set) var options: TranscriptionOptions?
    func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript {
        self.options = options
        return Transcript(text: "make it formal", language: "en")
    }
}
