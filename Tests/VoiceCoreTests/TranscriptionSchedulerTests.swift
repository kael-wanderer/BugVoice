import Testing
@testable import VoiceCore

struct TranscriptionSchedulerTests {
    @Test func dictationIsDequeuedBeforeTheNextMeetingChunk() {
        var queue = TranscriptionPriorityQueue()
        let audio = AudioClip(samples: [0.1])
        queue.enqueue(.init(id: "meeting-1", clip: audio, options: .init(
            language: .auto, timestamps: true, priority: .meeting
        )))
        queue.enqueue(.init(id: "meeting-2", clip: audio, options: .init(
            language: .auto, timestamps: true, priority: .meeting
        )))
        queue.enqueue(.init(id: "dictation-1", clip: audio, options: .init(
            language: .vi, priority: .dictation
        )))

        #expect(queue.dequeue()?.id == "dictation-1")
        #expect(queue.dequeue()?.id == "meeting-1")
        #expect(queue.dequeue()?.id == "meeting-2")
    }

    @Test func transcriptionDefaultsKeepDictationMode() {
        let options = TranscriptionOptions(language: .vi)
        #expect(options.timestamps == false)
        #expect(options.priority == .dictation)
    }

    @Test func dictationRunsBetweenMeetingChunksAndUnderlyingTranscriberIsSerial() async throws {
        let base = ControlledTranscriber()
        let scheduler = PriorityTranscriber(base: base)
        let audio = AudioClip(samples: [0.1])
        let meetingOptions = TranscriptionOptions(timestamps: true, priority: .meeting)
        let dictationOptions = TranscriptionOptions(language: .vi, priority: .dictation)

        let firstMeeting = Task { try await scheduler.transcribe(audio, options: meetingOptions) }
        await base.waitForStartedCount(1)
        let secondMeeting = Task { try await scheduler.transcribe(audio, options: meetingOptions) }
        let dictation = Task { try await scheduler.transcribe(audio, options: dictationOptions) }
        await waitForPending(scheduler, count: 2)

        await base.finishNext()
        await base.waitForStartedCount(2)
        #expect(await base.startedPriorities == [.meeting, .dictation])
        await base.finishNext()
        await base.waitForStartedCount(3)
        #expect(await base.startedPriorities == [.meeting, .dictation, .meeting])
        #expect(await base.maximumConcurrentCalls == 1)
        await base.finishNext()

        _ = try await firstMeeting.value
        _ = try await dictation.value
        _ = try await secondMeeting.value
    }

    @Test func cancellingQueuedDictationResumesWithCancellationError() async throws {
        let base = ControlledTranscriber()
        let scheduler = PriorityTranscriber(base: base)
        let audio = AudioClip(samples: [0.1])
        let meeting = Task { try await scheduler.transcribe(audio, options: .init(priority: .meeting)) }
        await base.waitForStartedCount(1)
        let dictation = Task { try await scheduler.transcribe(audio, options: .init(priority: .dictation)) }
        await waitForPending(scheduler, count: 1)

        dictation.cancel()
        do {
            _ = try await dictation.value
            Issue.record("Expected queued dictation cancellation")
        } catch is CancellationError {
            // Expected: queued work is removed without reaching the base engine.
        }

        #expect(await scheduler.pendingRequestCount == 0)
        await base.finishNext()
        _ = try await meeting.value
        #expect(await base.startedPriorities == [.meeting])
    }

    private func waitForPending(_ scheduler: PriorityTranscriber, count: Int) async {
        for _ in 0..<10_000 {
            if await scheduler.pendingRequestCount == count { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for transcription requests to queue")
    }
}

private actor ControlledTranscriber: Transcriber {
    private(set) var startedPriorities: [TranscriptionPriority] = []
    private(set) var maximumConcurrentCalls = 0
    private var currentCalls = 0
    private var completions: [CheckedContinuation<Transcript, any Error>] = []
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript {
        currentCalls += 1
        maximumConcurrentCalls = max(maximumConcurrentCalls, currentCalls)
        startedPriorities.append(options.priority)
        let ready = startWaiters.filter { startedPriorities.count >= $0.0 }
        startWaiters.removeAll { startedPriorities.count >= $0.0 }
        ready.forEach { $0.1.resume() }
        let result = try await withCheckedThrowingContinuation { completions.append($0) }
        currentCalls -= 1
        return result
    }

    func waitForStartedCount(_ count: Int) async {
        if startedPriorities.count >= count { return }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func finishNext() {
        guard !completions.isEmpty else {
            Issue.record("No transcription request is waiting for completion")
            return
        }
        completions.removeFirst().resume(returning: Transcript(text: "ok", language: "en"))
    }
}
