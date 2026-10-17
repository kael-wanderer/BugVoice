import Foundation
import Testing
@testable import VoiceCore

struct MeetingTextGenerationTests {
    @Test func clampsInvalidBudgetsAndStillSplitsTranscript() {
        var settings = MeetingSettings()
        settings.generationContextTokens = 0
        settings.generationOutputTokens = -40
        let budget = MeetingTextBudget(settings: settings)
        let parts = MeetingTranscriptPart.split(transcript: [segment(String(repeating: "word ", count: 4_000))], budget: budget)

        #expect(budget.contextTokens == 2_048)
        #expect(budget.outputTokens == 256)
        #expect(!parts.isEmpty)
        #expect(parts.allSatisfy { $0.estimatedTokens <= budget.inputTokens })
    }

    @Test func clampsOutputToContextHeadroom() {
        let budget = MeetingTextBudget(contextTokens: 2_048, outputTokens: 50_000)
        #expect(budget.outputTokens == 1_024)
        #expect(budget.inputTokens == 1)
    }

    @Test func splitKeepsSpeakerAndTimeOnOversizedFragments() {
        let original = segment(String(repeating: "A useful sentence. ", count: 1_200))
        let parts = MeetingTranscriptPart.split(transcript: [original], budget: .init(contextTokens: 2_048, outputTokens: 512))

        #expect(parts.count > 1)
        #expect(parts.allSatisfy { $0.segments.allSatisfy { $0.track == .mic && $0.start == 12 && $0.end == 19 } })
        #expect(parts.allSatisfy { $0.estimatedTokens <= MeetingTextBudget(contextTokens: 2_048, outputTokens: 512).inputTokens })
    }

    @Test func generatorMergesPartResultsAndReportsProgress() async throws {
        let model = MeetingTextModelProbe(responses: ["Part summary"], mergeResponse: "Merged summary")
        let transcript = [segment(String(repeating: "First sentence. ", count: 900)), segment(String(repeating: "Second sentence. ", count: 900), start: 20)]
        let events = ProgressProbe()

        let output = try await MeetingTextGenerator().generate(
            transcript: transcript, kind: .summary,
            budget: .init(contextTokens: 2_048, outputTokens: 256), model: model
        ) { events.append($0) }

        #expect(output == "Merged summary")
        #expect(await model.requests.allSatisfy { $0.maxTokens == 256 })
        // A reasoning model writes its reasoning into the reply unless thinking is off.
        #expect(await model.requests.allSatisfy { $0.disableThinking })
        #expect(events.values.contains { $0.completedParts == $0.totalParts && $0.phase == .merge })
    }

    @Test func summaryFollowsTheNotesInEveryRequest() async throws {
        let model = MeetingTextModelProbe(responses: ["Part summary"], mergeResponse: "Merged summary")
        let transcript = [segment(String(repeating: "First sentence. ", count: 900)), segment(String(repeating: "Second sentence. ", count: 900), start: 20)]
        _ = try await MeetingTextGenerator().generate(
            transcript: transcript, kind: .summary,
            budget: .init(contextTokens: 2_048, outputTokens: 512),
            notes: "## Bot results\n- resets", model: model
        )
        let requests = await model.requests
        #expect(requests.count > 1)
        #expect(requests.allSatisfy { $0.system.contains(MeetingTextGenerator.followNotesInstruction) })
        #expect(requests.allSatisfy { $0.user.hasPrefix("My notes:\n## Bot results\n- resets\n\n") })
    }

    @Test func actionItemsAndEmptyNotesIgnoreNotes() async throws {
        let model = MeetingTextModelProbe(responses: ["- a"])
        _ = try await MeetingTextGenerator().generate(
            transcript: [segment("Short")], kind: .actionItems, budget: .init(), notes: "## Mine", model: model
        )
        _ = try await MeetingTextGenerator().generate(
            transcript: [segment("Short")], kind: .summary, budget: .init(), notes: "  ", model: model
        )
        let requests = await model.requests
        #expect(requests.allSatisfy { !$0.system.contains(MeetingTextGenerator.followNotesInstruction) })
        #expect(requests.allSatisfy { !$0.user.contains("My notes:") })
    }

    @Test func actionItemMergeDeduplicatesBullets() async throws {
        let model = MeetingTextModelProbe(responses: ["- Alex: Send the draft"], mergeResponse: "- Alex: Send the draft\n- Minh: Book the room")
        let transcript = [segment(String(repeating: "Task detail. ", count: 900)), segment(String(repeating: "Another detail. ", count: 900), start: 20)]
        let output = try await MeetingTextGenerator().generate(
            transcript: transcript, kind: .actionItems,
            budget: .init(contextTokens: 2_048, outputTokens: 256), model: model
        )
        #expect(output == "- Alex: Send the draft\n- Minh: Book the room")
    }

    @Test func mergeFailsInsteadOfSendingOversizedResultsWhenModelDoesNotReduceThem() async {
        let tooLarge = String(repeating: "x", count: 5_000)
        let model = MeetingTextModelProbe(responses: [tooLarge], mergeResponse: tooLarge)
        let transcript = [segment(String(repeating: "One. ", count: 2_000)), segment(String(repeating: "Two. ", count: 2_000), start: 20)]
        do {
            _ = try await MeetingTextGenerator().generate(
                transcript: transcript, kind: .summary,
                budget: .init(contextTokens: 2_048, outputTokens: 256), model: model
            )
            Issue.record("Expected a bounded merge failure")
        } catch MeetingTextGenerationError.mergeDidNotReduceToFitContext {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        let requests = await model.requests
        #expect(requests.allSatisfy { $0.user.count < 3_000 })
    }

    @Test func cancellationDoesNotReturnPartialText() async {
        let model = MeetingTextModelProbe(responses: ["first part", ""], cancelOnCall: 2)
        let transcript = [segment(String(repeating: "One. ", count: 1_000)), segment(String(repeating: "Two. ", count: 1_000), start: 20)]
        do {
            _ = try await MeetingTextGenerator().generate(
                transcript: transcript, kind: .summary,
                budget: .init(contextTokens: 2_048, outputTokens: 256), model: model
            )
            Issue.record("Expected generation cancellation")
        } catch is CancellationError {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func segment(_ text: String, start: Double = 12) -> MeetingSegment {
        MeetingSegment(start: start, end: start + 7, text: text, track: .mic)
    }
}

private final class ProgressProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [MeetingTextProgress] = []
    var values: [MeetingTextProgress] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
    func append(_ value: MeetingTextProgress) {
        lock.lock(); defer { lock.unlock() }
        stored.append(value)
    }
}

private actor MeetingTextModelProbe: TextModel {
    private(set) var requests: [CleanupRequest] = []
    let responses: [String]
    let cancelOnCall: Int?
    let mergeResponse: String?
    init(responses: [String], mergeResponse: String? = nil, cancelOnCall: Int? = nil) {
        self.responses = responses
        self.mergeResponse = mergeResponse
        self.cancelOnCall = cancelOnCall
    }
    func clean(_ request: CleanupRequest) async throws -> String {
        requests.append(request)
        if requests.count == cancelOnCall { throw CancellationError() }
        if request.system.contains("Combine the supplied partial results") { return mergeResponse ?? "merged" }
        let index = requests.count - 1
        return responses.indices.contains(index) ? responses[index] : "partial"
    }
}
