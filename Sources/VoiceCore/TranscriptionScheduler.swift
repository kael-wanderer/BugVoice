import Foundation

public struct ScheduledTranscription: Sendable, Identifiable {
    public var id: String
    public var clip: AudioClip
    public var options: TranscriptionOptions

    public init(id: String, clip: AudioClip, options: TranscriptionOptions) {
        self.id = id
        self.clip = clip
        self.options = options
    }
}

/// FIFO within each priority: dictation, meeting, then replaceable preview work.
public struct TranscriptionPriorityQueue: Sendable {
    private var requests: [ScheduledTranscription] = []

    public init() {}

    public var count: Int { requests.count }

    @discardableResult
    public mutating func enqueue(_ request: ScheduledTranscription) -> [String] {
        var dropped: [String] = []
        if request.options.priority == .preview || request.options.priority == .dictation {
            dropped = requests.filter { $0.options.priority == .preview }.map(\.id)
            requests.removeAll { $0.options.priority == .preview }
        }
        requests.append(request)
        return dropped
    }

    public mutating func dequeue() -> ScheduledTranscription? {
        guard !requests.isEmpty else { return nil }
        let index = requests.firstIndex { $0.options.priority == .dictation }
            ?? requests.firstIndex { $0.options.priority == .meeting }
            ?? requests.startIndex
        return requests.remove(at: index)
    }

    @discardableResult
    public mutating func remove(id: String) -> Bool {
        guard let index = requests.firstIndex(where: { $0.id == id }) else { return false }
        requests.remove(at: index)
        return true
    }
}

/// Serializes access to one underlying transcriber and lets dictation jump ahead
/// of queued meeting chunks at each request boundary.
public actor PriorityTranscriber: Transcriber {
    private let base: any Transcriber
    private var queue = TranscriptionPriorityQueue()
    private var continuations: [String: CheckedContinuation<Transcript, any Error>] = [:]
    private var running: (id: String, priority: TranscriptionPriority, task: Task<Transcript, any Error>)?
    private var isDraining = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public var pendingRequestCount: Int { queue.count }

    public init(base: any Transcriber) {
        self.base = base
    }

    public func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript {
        let id = UUID().uuidString
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let request = ScheduledTranscription(id: id, clip: clip, options: options)
                continuations[id] = continuation
                for dropped in queue.enqueue(request) {
                    continuations.removeValue(forKey: dropped)?.resume(throwing: CancellationError())
                }
                if options.priority == .dictation, running?.priority == .preview {
                    running?.task.cancel()
                }
                startDrainIfNeeded()
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    private func startDrainIfNeeded() {
        guard !isDraining else { return }
        isDraining = true
        Task { await drain() }
    }

    private func drain() async {
        while let request = queue.dequeue() {
            guard let continuation = continuations.removeValue(forKey: request.id) else { continue }
            let task = Task { [base] in
                let transcript = try await base.transcribe(request.clip, options: request.options)
                try Task.checkCancellation()
                return transcript
            }
            running = (request.id, request.options.priority, task)
            do {
                continuation.resume(returning: try await task.value)
            } catch {
                continuation.resume(throwing: error)
            }
            running = nil
        }
        isDraining = false
        let waiters = idleWaiters
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    public func waitUntilIdle() async {
        guard isDraining || queue.count > 0 else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func cancel(id: String) {
        if running?.id == id {
            running?.task.cancel()
            return
        }
        guard queue.remove(id: id), let continuation = continuations.removeValue(forKey: id) else { return }
        continuation.resume(throwing: CancellationError())
    }
}


/// Stable transcription entry point shared by dictation and meeting work.
/// Reconfiguration drains the current priority queue before routing held work
/// to the replacement, preserving every request across settings changes.
public actor TranscriptionRouter: Transcriber {
    private struct HeldRequest {
        let id: UUID
        let clip: AudioClip
        let options: TranscriptionOptions
        let continuation: CheckedContinuation<Transcript, any Error>
    }

    private var current: any Transcriber
    private var held: [HeldRequest] = []
    private var routedTasks: [UUID: Task<Void, Never>] = [:]
    private var replacementWaiters: [CheckedContinuation<Void, Never>] = []
    public private(set) var isReplacing = false

    public init(initial: any Transcriber) { current = initial }

    public func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript {
        guard isReplacing else { return try await current.transcribe(clip, options: options) }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                held.append(HeldRequest(id: id, clip: clip, options: options, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    public func replace(with replacement: any Transcriber) async {
        while isReplacing {
            await withCheckedContinuation { replacementWaiters.append($0) }
        }
        isReplacing = true
        if let priority = current as? PriorityTranscriber { await priority.waitUntilIdle() }
        current = replacement
        isReplacing = false

        let requests = held
        held.removeAll()
        for request in requests { route(request, through: replacement) }
        let waiters = replacementWaiters
        replacementWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    public func waitUntilIdle() async {
        if let priority = current as? PriorityTranscriber { await priority.waitUntilIdle() }
        while !routedTasks.isEmpty {
            await withCheckedContinuation { replacementWaiters.append($0) }
        }
    }

    private func route(_ request: HeldRequest, through transcriber: any Transcriber) {
        let task = Task { [weak self] in
            do {
                request.continuation.resume(returning: try await transcriber.transcribe(request.clip, options: request.options))
            } catch {
                request.continuation.resume(throwing: error)
            }
            await self?.routedRequestFinished(request.id)
        }
        routedTasks[request.id] = task
    }

    private func cancel(id: UUID) {
        if let index = held.firstIndex(where: { $0.id == id }) {
            let request = held.remove(at: index)
            request.continuation.resume(throwing: CancellationError())
        } else {
            routedTasks[id]?.cancel()
        }
    }

    private func routedRequestFinished(_ id: UUID) {
        routedTasks.removeValue(forKey: id)
        let waiters = replacementWaiters
        replacementWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
