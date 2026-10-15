import Foundation
import Testing
@testable import VoiceCore

@Suite struct AbandonOnCancelTests {
    @Test func returnsTheOperationResult() async throws {
        let value = try await abandoningOnCancel { 42 }
        #expect(value == 42)
    }

    @Test func rethrowsTheOperationError() async {
        await #expect(throws: ProviderError.unavailable("x")) {
            try await abandoningOnCancel { () async throws -> Int in throw ProviderError.unavailable("x") }
        }
    }

    /// An operation that ignores cancellation must not hold up the caller,
    /// or `withTimeout` cannot return until the operation finishes.
    @Test func returnsPromptlyWhenTheOperationIgnoresCancellation() async {
        let start = Date()
        let outcome: Result<Int, Error>
        do {
            outcome = .success(try await withTimeout(seconds: 0.1) {
                try await abandoningOnCancel { () async throws -> Int in
                    // Busy wait: never checks for cancellation.
                    let end = Date().addingTimeInterval(2)
                    while Date() < end { usleep(1_000) }
                    return 1
                }
            })
        } catch {
            outcome = .failure(error)
        }
        #expect(Date().timeIntervalSince(start) < 1)
        guard case .failure(let error) = outcome else {
            Issue.record("expected a timeout")
            return
        }
        #expect(error is TimeoutError)
    }

    @Test func alreadyCancelledCallerReturnsImmediately() async {
        let task = Task {
            try await abandoningOnCancel { () async throws -> Int in
                try? await Task.sleep(for: .seconds(5))
                return 1
            }
        }
        task.cancel()
        let start = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(throws: CancellationError.self) { try result.get() }
    }
}

@Suite struct RecallableResultTests {
    func result(_ outcome: DictationOutcome) -> DictationResult {
        DictationResult(
            startedAt: Date(), appName: "App", bundleID: "b", style: .personal, language: "en",
            raw: "secret raw", cleaned: "secret clean", finalText: "secret", outcome: outcome,
            rawReason: nil, errorMessage: nil, timings: StageTimings()
        )
    }

    @Test func secureFieldResultKeepsNoText() {
        let r = result(.copiedSecureField).recallable
        #expect(r.outcome == .copiedSecureField)
        #expect(r.raw.isEmpty)
        #expect(r.cleaned == nil)
        #expect(r.finalText.isEmpty)
        #expect(r.appName == "App")
    }

    @Test func otherResultsAreUnchanged() {
        let r = result(.inserted)
        #expect(r.recallable == r)
    }
}
