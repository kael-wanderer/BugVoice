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

/// FIFO within each priority, with dictation always selected before queued meeting work.
public struct TranscriptionPriorityQueue: Sendable {
    private var requests: [ScheduledTranscription] = []

    public init() {}

    public var count: Int { requests.count }

    public mutating func enqueue(_ request: ScheduledTranscription) {
        requests.append(request)
    }

    public mutating func dequeue() -> ScheduledTranscription? {
        guard !requests.isEmpty else { return nil }
        let index = requests.firstIndex { $0.options.priority == .dictation } ?? requests.startIndex
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
    private var isDraining = false

    var pendingRequestCount: Int { queue.count }

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
                queue.enqueue(request)
                startDrainIfNeeded()
            }
        } onCancel: {
            Task { await self.cancelQueued(id: id) }
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
            do {
                continuation.resume(returning: try await base.transcribe(request.clip, options: request.options))
            } catch {
                continuation.resume(throwing: error)
            }
        }
        isDraining = false
    }

    private func cancelQueued(id: String) {
        guard queue.remove(id: id), let continuation = continuations.removeValue(forKey: id) else { return }
        continuation.resume(throwing: CancellationError())
    }
}
