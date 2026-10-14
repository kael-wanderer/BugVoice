import Foundation

public struct TimeoutError: Error, Equatable {
    public init() {}
}

/// Runs `operation`, cancelling it and throwing `TimeoutError` after `seconds`.
public func withTimeout<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw TimeoutError() }
        return first
    }
}

/// Runs `operation` in its own task and returns as soon as the caller is
/// cancelled, throwing `CancellationError`, even if `operation` never checks
/// for cancellation. The operation is cancelled too, but may keep running in
/// the background until it finishes; its result is then discarded.
///
/// For calls into APIs that do not honour cancellation, so that `withTimeout`
/// can return on time.
public func abandoningOnCancel<T: Sendable>(
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let gate = ResumeOnce<T>()
    let work = Task {
        do { gate.resume(.success(try await operation())) } catch { gate.resume(.failure(error)) }
    }
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { gate.attach($0) }
    } onCancel: {
        work.cancel()
        gate.resume(.failure(CancellationError()))
    }
}

/// Resumes one continuation exactly once with whichever result arrives first,
/// whether it arrives before or after the continuation is attached.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pending: Result<T, Error>?
    private var finished = false

    func attach(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if let pending {
            finished = true
            self.pending = nil
            lock.unlock()
            continuation.resume(with: pending)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        guard !finished, pending == nil else { lock.unlock(); return }
        guard let continuation else {
            pending = result
            lock.unlock()
            return
        }
        finished = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}
