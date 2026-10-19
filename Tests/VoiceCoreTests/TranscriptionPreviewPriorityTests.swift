import Foundation
import Testing
@testable import VoiceCore

struct TranscriptionPreviewPriorityTests {
    private func request(_ id: String, _ priority: TranscriptionPriority) -> ScheduledTranscription {
        .init(id: id, clip: AudioClip(samples: [0.1]), options: .init(priority: priority))
    }

    @Test func dequeueOrderDictationMeetingPreview() {
        var queue = TranscriptionPriorityQueue()
        queue.enqueue(request("d", .dictation))
        queue.enqueue(request("p", .preview))
        queue.enqueue(request("m", .meeting))
        #expect(queue.dequeue()?.id == "d")
        #expect(queue.dequeue()?.id == "m")
        #expect(queue.dequeue()?.id == "p")
    }

    @Test func secondPreviewReplacesQueued() {
        var queue = TranscriptionPriorityQueue()
        queue.enqueue(request("p1", .preview))
        #expect(queue.enqueue(request("p2", .preview)) == ["p1"])
        #expect(queue.dequeue()?.id == "p2")
        #expect(queue.dequeue() == nil)
    }

    @Test func dictationDropsQueuedPreviews() {
        var queue = TranscriptionPriorityQueue()
        queue.enqueue(request("p", .preview))
        #expect(queue.enqueue(request("d", .dictation)) == ["p"])
        #expect(queue.dequeue()?.id == "d")
        #expect(queue.dequeue() == nil)
    }

    @Test func meetingBeforePreview() {
        var queue = TranscriptionPriorityQueue()
        queue.enqueue(request("p", .preview))
        queue.enqueue(request("m", .meeting))
        #expect(queue.dequeue()?.id == "m")
        #expect(queue.dequeue()?.id == "p")
    }

    @Test func droppedPreviewThrowsCancellation() async throws {
        let base = PreviewTestTranscriber()
        let scheduler = PriorityTranscriber(base: base)
        let meeting = Task { try await scheduler.transcribe(AudioClip(samples: []), options: .init(priority: .meeting)) }
        await base.waitForStart()
        let first = Task { try await scheduler.transcribe(AudioClip(samples: []), options: .init(priority: .preview)) }
        await pending(scheduler)
        let second = Task { try await scheduler.transcribe(AudioClip(samples: []), options: .init(priority: .preview)) }
        await cancelled(first)
        second.cancel()
        await cancelled(second)
        await base.finishMeeting()
        _ = try await meeting.value
    }

    @Test func dictationCancelsRunningPreview() async throws {
        let base = PreviewTestTranscriber()
        let scheduler = PriorityTranscriber(base: base)
        let preview = Task { try await scheduler.transcribe(AudioClip(samples: []), options: .init(priority: .preview)) }
        await base.waitForStart()
        let start = ContinuousClock.now
        let result = try await scheduler.transcribe(AudioClip(samples: []), options: .init(priority: .dictation))
        await cancelled(preview)
        #expect(start.duration(to: .now) < .milliseconds(200))
        #expect(result.text == "final")
        #expect(await base.sawCancellation)
    }

    @Test func cancellingCallerStopsRunningRequest() async {
        for priority in [TranscriptionPriority.preview, .dictation, .meeting] {
            let base = PreviewTestTranscriber(sleepAll: true)
            let scheduler = PriorityTranscriber(base: base)
            let task = Task { try await scheduler.transcribe(AudioClip(samples: []), options: .init(priority: priority)) }
            await base.waitForStart()
            task.cancel()
            await cancelled(task)
            #expect(await base.sawCancellation)
            await scheduler.waitUntilIdle()
        }
    }

    @Test func runningMeetingNotCancelledByDictation() async throws {
        let base = PreviewTestTranscriber()
        let scheduler = PriorityTranscriber(base: base)
        let meeting = Task { try await scheduler.transcribe(AudioClip(samples: []), options: .init(priority: .meeting)) }
        await base.waitForStart()
        let dictation = Task { try await scheduler.transcribe(AudioClip(samples: []), options: .init(priority: .dictation)) }
        await pending(scheduler)
        #expect(await base.sawCancellation == false)
        await base.finishMeeting()
        #expect(try await meeting.value.text == "meeting")
        #expect(try await dictation.value.text == "final")
    }

    private func pending(_ scheduler: PriorityTranscriber) async {
        for _ in 0..<10_000 {
            if await scheduler.pendingRequestCount == 1 { return }
            await Task.yield()
        }
        Issue.record("Request did not queue")
    }

    private func cancelled(_ task: Task<Transcript, any Error>) async {
        do { _ = try await task.value; Issue.record("Expected CancellationError") }
        catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    }
}

private actor PreviewTestTranscriber: Transcriber {
    var sawCancellation = false
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var meeting: CheckedContinuation<Transcript, Never>?
    private let sleepAll: Bool
    init(sleepAll: Bool = false) { self.sleepAll = sleepAll }

    func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript {
        started = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        if options.priority == .preview || sleepAll {
            do { try await Task.sleep(for: .seconds(5)) }
            catch { sawCancellation = true; throw error }
        } else if options.priority == .meeting {
            return await withCheckedContinuation { meeting = $0 }
        }
        return Transcript(text: "final")
    }
    func waitForStart() async {
        if !started { await withCheckedContinuation { waiters.append($0) } }
    }
    func finishMeeting() { meeting?.resume(returning: Transcript(text: "meeting")); meeting = nil }
}
