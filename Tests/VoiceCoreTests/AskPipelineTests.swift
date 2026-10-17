import Foundation
import Testing
@testable import VoiceCore

private final class StubModel: TextModel, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [CleanupRequest] = []
    let understanding: @Sendable () async throws -> String
    let reading: @Sendable (Int) async throws -> String

    init(
        understanding: @escaping @Sendable () async throws -> String = { #"{"terms":["alpha"],"from":null,"to":null,"people":[]}"# },
        reading: @escaping @Sendable (Int) async throws -> String = { _ in #"{"answer":"Done.","citations":[{"line":"P1.1"}]}"# }
    ) {
        self.understanding = understanding
        self.reading = reading
    }

    var requests: [CleanupRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
    var readingRequests: [CleanupRequest] { requests.filter { $0.system == AskAnswerPrompt.rules } }

    private func record(_ request: CleanupRequest) -> Int {
        lock.lock()
        defer { lock.unlock() }
        _requests.append(request)
        return _requests.filter { $0.system == AskAnswerPrompt.rules }.count
    }

    func clean(_ request: CleanupRequest) async throws -> String {
        let readingIndex = record(request)
        if request.system == AskQueryPrompt.rules { return try await understanding() }
        return try await reading(readingIndex)
    }
}

private struct StubEmbedder: Embedder {
    var modelID = "embed"
    var vector: [Float] = [1, 0]
    var delay: Double = 0
    var fail = false
    func embed(_ inputs: [String]) async throws -> [[Float]] {
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        if fail { throw ProviderError.unavailable("down") }
        return inputs.map { _ in vector }
    }
}

private final class Steps: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [AskStep] = []
    func add(_ s: AskStep) { lock.lock(); list.append(s); lock.unlock() }
    var all: [AskStep] { lock.lock(); defer { lock.unlock() }; return list }
}

@Suite("AskPipeline")
struct AskPipelineTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func passage(_ i: Int, _ text: String, _ d: Date? = nil) -> AskPassage {
        AskPassage(
            source: .note(NoteID(rawValue: "n\(i)")), part: .note, index: 0, date: d ?? date(2026, 9, 1),
            lines: [AskLine(id: "b0.0", text: text)])
    }

    private func corpus(_ passages: [AskPassage], vectors: [String: [Float]] = [:]) -> AskCorpus {
        var info: [AskSource: AskItemInfo] = [:]
        for p in passages { info[p.source] = AskItemInfo(title: "T", kind: .note, date: p.date) }
        return AskCorpus(passages: passages, info: info, vectors: vectors, meetings: 2, notes: passages.count, dictations: 3)
    }

    private func pipeline(
        _ model: StubModel, embedder: (any Embedder)? = nil, context: Int = 16_384,
        understanding: Double = 5, embed: Double = 5, total: Double = 30
    ) -> AskPipeline {
        AskPipeline(
            model: model, modelID: "m", disableThinking: true, embedder: embedder, contextTokens: context,
            now: { Date(timeIntervalSince1970: 1_790_000_000) },
            understandingTimeout: understanding, embedTimeout: embed, totalTimeout: total, calendar: calendar)
    }

    private func run(_ p: AskPipeline, _ c: AskCorpus, steps: Steps = Steps()) async throws -> AskOutcome {
        try await p.run(question: "alpha?", history: [], corpus: c, progress: { steps.add($0) })
    }

    @Test func stepsReportedInOrder() async throws {
        let steps = Steps()
        let c = corpus([passage(1, "alpha one"), passage(2, "alpha two")])
        let outcome = try await run(pipeline(StubModel()), c, steps: steps)
        #expect(steps.all == [.understanding, .searching(meetings: 2, notes: 2, dictations: 3), .reading(passages: 2)])
        guard case .answered(let result, let word) = outcome else { Issue.record("not answered"); return }
        #expect(result.answer == "Done.")
        #expect(word == .noModel)
    }

    @Test func understandingFailureStillSearches() async throws {
        let model = StubModel(understanding: { throw ProviderError.unavailable("x") })
        let outcome = try await run(pipeline(model), corpus([passage(1, "alpha one")]))
        guard case .answered = outcome else { Issue.record("not answered: \(outcome)"); return }
    }

    @Test func dateRangeFilters() async throws {
        let model = StubModel(understanding: {
            #"{"terms":["alpha"],"from":"2026-09-10","to":"2026-09-20","people":[]}"#
        })
        let steps = Steps()
        let c = corpus([
            passage(1, "alpha old", date(2026, 8, 1)), passage(2, "alpha in", date(2026, 9, 15)),
            passage(3, "alpha late", date(2026, 10, 1)),
        ])
        _ = try await run(pipeline(model), c, steps: steps)
        #expect(steps.all.last == .reading(passages: 1))
        #expect(model.readingRequests[0].user.contains("alpha in"))
        #expect(!model.readingRequests[0].user.contains("alpha old"))
    }

    @Test func noEmbedderIsWordOnlyNoModel() async throws {
        let outcome = try await run(pipeline(StubModel()), corpus([passage(1, "alpha")]))
        guard case .answered(_, let word) = outcome else { Issue.record("not answered"); return }
        #expect(word == .noModel)
    }

    @Test func embedderTimeoutIsWordOnlyNotAnswering() async throws {
        let ps = [passage(1, "alpha")]
        let c = corpus(ps, vectors: [ps[0].id: [1, 0]])
        let outcome = try await run(pipeline(StubModel(), embedder: StubEmbedder(delay: 5), embed: 0.1), c)
        guard case .answered(_, let word) = outcome else { Issue.record("not answered"); return }
        #expect(word == .notAnswering)
    }

    @Test func embedderErrorIsWordOnlyNotAnswering() async throws {
        let ps = [passage(1, "alpha")]
        let c = corpus(ps, vectors: [ps[0].id: [1, 0]])
        let outcome = try await run(pipeline(StubModel(), embedder: StubEmbedder(fail: true)), c)
        guard case .answered(_, let word) = outcome else { Issue.record("not answered"); return }
        #expect(word == .notAnswering)
    }

    @Test func meaningSearchAddsPassagesAndClearsNotice() async throws {
        let ps = [passage(1, "alpha"), passage(2, "unrelated words"), passage(3, "other")]
        let vectors = [ps[0].id: [Float(1), 0], ps[1].id: [Float(0.9), 0.1], ps[2].id: [Float(0), 1]]
        let model = StubModel()
        let steps = Steps()
        let outcome = try await run(pipeline(model, embedder: StubEmbedder()), corpus(ps, vectors: vectors), steps: steps)
        guard case .answered(_, let word) = outcome else { Issue.record("not answered"); return }
        #expect(word == nil)
        // p3 has cosine 0, below the 0.3 floor, and no word hit.
        #expect(steps.all.last == .reading(passages: 2))
    }

    @Test func halfCoverageRule() async throws {
        let ps = (1...10).map { passage($0, "alpha \($0)") }
        var vectors: [String: [Float]] = [:]
        for p in ps.prefix(4) { vectors[p.id] = [1, 0] }
        let outcome = try await run(pipeline(StubModel(), embedder: StubEmbedder()), corpus(ps, vectors: vectors))
        guard case .answered(_, let word) = outcome else { Issue.record("not answered"); return }
        #expect(word == .notAnswering)
    }

    @Test func zeroPassagesSkipsReadingCall() async throws {
        let model = StubModel()
        let outcome = try await run(pipeline(model), corpus([passage(1, "nothing relevant")]))
        #expect(outcome == .nothingFound(wordSearchOnly: .noModel))
        #expect(model.readingRequests.isEmpty)
        #expect(model.requests.count == 1)
    }

    @Test func nothingFoundKeepsMeaningSearchState() async throws {
        let ps = [passage(1, "nothing relevant")]
        let outcome = try await run(pipeline(StubModel(), embedder: StubEmbedder()), corpus(ps, vectors: [ps[0].id: [0, 1]]))
        #expect(outcome == .nothingFound(wordSearchOnly: nil))
    }

    @Test func dateRangeWithoutWordHitsReadsNewestFirst() async throws {
        let model = StubModel(
            understanding: { #"{"terms":["zzz"],"from":"2026-09-01","to":"2026-09-30","people":[]}"# })
        let ps = [passage(1, "older", date(2026, 9, 5)), passage(2, "newer", date(2026, 9, 20)), passage(3, "outside", date(2026, 8, 1))]
        let steps = Steps()
        let outcome = try await run(pipeline(model), corpus(ps), steps: steps)
        guard case .answered = outcome else { Issue.record("not answered: \(outcome)"); return }
        #expect(steps.all.last == .reading(passages: 2))
        let user = try #require(model.readingRequests.first?.user)
        let newer = try #require(user.range(of: "newer"))
        let older = try #require(user.range(of: "older"))
        #expect(newer.lowerBound < older.lowerBound)
        #expect(!user.contains("outside"))
    }

    @Test func badJSONRetriedOnce() async throws {
        let model = StubModel(reading: { _ in "not json" })
        let outcome = try await run(pipeline(model), corpus([passage(1, "alpha")]))
        #expect(outcome == .failed(.unreadable))
        #expect(model.readingRequests.count == 2)
        #expect(model.readingRequests[1].user.hasSuffix("Reply with JSON only."))
        #expect(model.readingRequests[0].maxTokens == 2048)
    }

    @Test func badJSONThenGoodSucceeds() async throws {
        let model = StubModel(reading: { n in n == 1 ? "oops" : #"{"answer":"Ok.","citations":[{"line":"P1.1"}]}"# })
        let outcome = try await run(pipeline(model), corpus([passage(1, "alpha")]))
        guard case .answered = outcome else { Issue.record("not answered: \(outcome)"); return }
    }

    @Test func readingModelErrorFails() async throws {
        let model = StubModel(reading: { _ in throw ProviderError.unavailable("x") })
        let outcome = try await run(pipeline(model), corpus([passage(1, "alpha")]))
        #expect(outcome == .failed(.model))
    }

    @Test func uncitedAnswerIsNothingFound() async throws {
        let model = StubModel(reading: { _ in #"{"answer":"Maybe.","citations":[{"line":"P9.9"}]}"# })
        let outcome = try await run(pipeline(model), corpus([passage(1, "alpha")]))
        #expect(outcome == .nothingFound(wordSearchOnly: .noModel))
    }

    @Test func contextBudgetTrimsPassages() async throws {
        let text = "alpha " + String(repeating: "word ", count: 60)
        let ps = (1...60).map { passage($0, text) }
        let steps = Steps()
        _ = try await run(pipeline(StubModel(), context: 4096), corpus(ps), steps: steps)
        guard case .reading(let n) = steps.all.last else { Issue.record("no reading step"); return }
        #expect(n > 0 && n < 40)
    }

    @Test func totalTimeoutFails() async throws {
        let model = StubModel(reading: { _ in try await Task.sleep(for: .seconds(10)); return "" })
        let outcome = try await run(pipeline(model, total: 0.2), corpus([passage(1, "alpha")]))
        #expect(outcome == .failed(.tooSlow))
    }

    @Test func cancellationThrowsNoOutcome() async throws {
        let model = StubModel(reading: { _ in try await Task.sleep(for: .seconds(10)); return "" })
        let p = pipeline(model)
        let c = corpus([passage(1, "alpha")])
        let task = Task { try await p.run(question: "alpha?", history: [], corpus: c, progress: { _ in }) }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
