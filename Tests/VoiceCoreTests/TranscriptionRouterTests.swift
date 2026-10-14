import Foundation
import Testing
@testable import VoiceCore

struct TranscriptionRouterTests {
    @Test func replacementDrainsOldQueueBeforeRoutingHeldRequestsToNewPair() async throws {
        let oldBase = GatedTranscriber()
        let oldPair = PriorityTranscriber(base: oldBase)
        let newBase = ImmediateTranscriber(label: "new")
        let router = TranscriptionRouter(initial: oldPair)
        let clip = AudioClip(samples: [0.1])

        let first = Task { try await router.transcribe(clip, options: .init(language: .en)) }
        await oldBase.waitUntilStarted()
        let queued = Task { try await router.transcribe(clip, options: .init(language: .vi)) }
        await waitForQueue(oldPair, count: 1)
        let replacement = Task { await router.replace(with: PriorityTranscriber(base: newBase)) }
        await waitForReplacement(router)
        let duringSwap = Task { try await router.transcribe(clip, options: .init(language: .auto)) }

        #expect(await newBase.callCount == 0)
        await oldBase.release()
        let firstResult = try await first.value
        let queuedResult = try await queued.value
        await replacement.value
        let newResult = try await duringSwap.value

        #expect(firstResult.text == "old")
        #expect(queuedResult.text == "old")
        #expect(newResult.text == "new")
        #expect(await oldBase.callCount == 2)
        #expect(await newBase.callCount == 1)
    }

    private func waitForQueue(_ transcriber: PriorityTranscriber, count: Int) async {
        while await transcriber.pendingRequestCount < count { await Task.yield() }
    }

    private func waitForReplacement(_ router: TranscriptionRouter) async {
        while !(await router.isReplacing) { await Task.yield() }
    }
}

private actor GatedTranscriber: Transcriber {
    private(set) var callCount = 0
    private var started: CheckedContinuation<Void, Never>?
    private var releaseGate: CheckedContinuation<Void, Never>?
    func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript {
        callCount += 1
        if callCount == 1 {
            started?.resume()
            started = nil
            await withCheckedContinuation { releaseGate = $0 }
        }
        return Transcript(text: "old")
    }
    func waitUntilStarted() async {
        if callCount > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { releaseGate?.resume(); releaseGate = nil }
}

private actor ImmediateTranscriber: Transcriber {
    let label: String
    private(set) var callCount = 0
    init(label: String) { self.label = label }
    func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript {
        callCount += 1
        return Transcript(text: label)
    }
}
