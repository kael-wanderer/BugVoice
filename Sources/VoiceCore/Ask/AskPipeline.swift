import Foundation

public enum AskStep: Equatable, Sendable {
    case understanding
    case searching(meetings: Int, notes: Int, dictations: Int)
    case reading(passages: Int)
}

public enum WordOnlyReason: Equatable, Sendable { case noModel, notAnswering }

public enum AskFailure: Error, Equatable, Sendable { case model, unreadable, tooSlow }

public enum AskOutcome: Equatable, Sendable {
    case answered(AskResult, wordSearchOnly: WordOnlyReason?)
    case nothingFound(wordSearchOnly: WordOnlyReason?)
    case failed(AskFailure)
}

/// The passages Ask may search, already limited to the scope.
public struct AskCorpus: Sendable {
    public var passages: [AskPassage]
    public var info: [AskSource: AskItemInfo]
    public var vectors: [String: [Float]]
    public var meetings: Int
    public var notes: Int
    public var dictations: Int

    public init(
        passages: [AskPassage], info: [AskSource: AskItemInfo], vectors: [String: [Float]],
        meetings: Int, notes: Int, dictations: Int
    ) {
        self.passages = passages
        self.info = info
        self.vectors = vectors
        self.meetings = meetings
        self.notes = notes
        self.dictations = dictations
    }
}

/// One Ask run: understand, search, read, check.
public struct AskPipeline: Sendable {
    public static let meaningFloor: Float = 0.3
    static let outputTokens = 2048
    static let slackTokens = 1024

    public let model: any TextModel
    public let modelID: String
    public let disableThinking: Bool
    public let embedder: (any Embedder)?
    public let contextTokens: Int
    public let now: @Sendable () -> Date
    public let understandingTimeout: Double
    public let embedTimeout: Double
    public let totalTimeout: Double
    public let calendar: Calendar

    public init(
        model: any TextModel, modelID: String, disableThinking: Bool, embedder: (any Embedder)?,
        contextTokens: Int, now: @escaping @Sendable () -> Date,
        understandingTimeout: Double = 20, embedTimeout: Double = 5, totalTimeout: Double = 120,
        calendar: Calendar = .current
    ) {
        self.model = model
        self.modelID = modelID
        self.disableThinking = disableThinking
        self.embedder = embedder
        self.contextTokens = contextTokens
        self.now = now
        self.understandingTimeout = understandingTimeout
        self.embedTimeout = embedTimeout
        self.totalTimeout = totalTimeout
        self.calendar = calendar
    }

    /// Throws only `CancellationError`; every other result is an `AskOutcome`.
    public func run(
        question: String, history: [NoteChatTurn], corpus: AskCorpus,
        progress: @escaping @Sendable (AskStep) -> Void
    ) async throws -> AskOutcome {
        do {
            return try await withTimeout(seconds: totalTimeout) {
                try await execute(question: question, history: history, corpus: corpus, progress: progress)
            }
        } catch is TimeoutError {
            return .failed(.tooSlow)
        }
    }

    private func execute(
        question: String, history: [NoteChatTurn], corpus: AskCorpus,
        progress: @Sendable (AskStep) -> Void
    ) async throws -> AskOutcome {
        try Task.checkCancellation()
        progress(.understanding)
        let query = try await understand(question: question, history: history)

        try Task.checkCancellation()
        progress(.searching(meetings: corpus.meetings, notes: corpus.notes, dictations: corpus.dictations))
        let dated = corpus.passages.filter { p in
            (query.from.map { p.date >= $0 } ?? true) && (query.to.map { p.date <= $0 } ?? true)
        }
        guard !dated.isEmpty else { return .nothingFound(wordSearchOnly: embedder == nil ? .noModel : nil) }

        let scores = AskRanking.wordScores(dated, terms: query.terms, people: query.people)
        let wordRanking = dated.filter { (scores[$0.id] ?? 0) > 0 }
            .sorted { scores[$0.id]! > scores[$1.id]! }
            .map(\.id)

        var rankings = [wordRanking]
        var wordOnly: WordOnlyReason?
        if let embedder {
            let covered = dated.filter { corpus.vectors[$0.id] != nil }.count
            if covered * 2 >= dated.count {
                if let meaning = try await meaningRanking(question: question, passages: dated, corpus: corpus, embedder: embedder) {
                    rankings.append(meaning)
                } else {
                    wordOnly = .notAnswering
                }
            } else {
                wordOnly = .notAnswering
            }
        } else {
            wordOnly = .noModel
        }

        try Task.checkCancellation()
        let byID = Dictionary(dated.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var fused = AskRanking.fuse(rankings).compactMap { byID[$0] }
        // A question that names only a time ("recent meetings") matches no words: read that time's newest passages.
        if fused.isEmpty, query.from != nil || query.to != nil {
            fused = dated.sorted { $0.date > $1.date }
        }
        let chosen = fit(Array(fused.prefix(AskRanking.maxPassages)), question: question, history: history, info: corpus.info)
        guard !chosen.isEmpty else { return .nothingFound(wordSearchOnly: wordOnly) }

        progress(.reading(passages: chosen.count))
        var request = AskAnswerPrompt.request(
            question: question, history: history, passages: chosen, info: corpus.info,
            modelID: modelID, disableThinking: disableThinking, maxOutputTokens: Self.outputTokens,
            calendar: calendar)
        var parsed: (answer: String, lineRefs: [String])?
        for attempt in 0..<2 {
            try Task.checkCancellation()
            if attempt == 1 { request.user += "\n\nReply with JSON only." }
            let reply: String
            do {
                let req = request
                reply = try await abandoningOnCancel { try await model.clean(req) }
            } catch is CancellationError {
                throw CancellationError()
            } catch is TimeoutError {
                throw TimeoutError()
            } catch {
                return .failed(.model)
            }
            parsed = AskAnswerPrompt.parse(reply)
            if parsed != nil { break }
        }
        guard let parsed else { return .failed(.unreadable) }
        guard let result = AskAnswerPrompt.check(
            lineRefs: parsed.lineRefs, passages: chosen, info: corpus.info, answer: parsed.answer)
        else { return .nothingFound(wordSearchOnly: wordOnly) }
        return .answered(result, wordSearchOnly: wordOnly)
    }

    private func understand(question: String, history: [NoteChatTurn]) async throws -> AskQuery {
        let request = AskQueryPrompt.request(question: question, history: history, today: now(), modelID: modelID)
        do {
            let reply = try await withTimeout(seconds: understandingTimeout) {
                try await abandoningOnCancel { try await model.clean(request) }
            }
            return AskQueryPrompt.parse(reply, question: question, calendar: calendar)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return AskQueryPrompt.fallback(question: question)
        }
    }

    /// Nil when the embedder is slow, fails, or answers nothing usable.
    private func meaningRanking(
        question: String, passages: [AskPassage], corpus: AskCorpus, embedder: any Embedder
    ) async throws -> [String]? {
        let vectors: [[Float]]
        do {
            vectors = try await withTimeout(seconds: embedTimeout) {
                try await abandoningOnCancel { try await embedder.embed([question]) }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return nil
        }
        guard let q = vectors.first, !q.isEmpty else { return nil }
        var scored: [(id: String, cosine: Float)] = []
        for p in passages {
            guard let v = corpus.vectors[p.id] else { continue }
            let c = AskRanking.cosine(q, v)
            if c >= Self.meaningFloor { scored.append((p.id, c)) }
        }
        return scored.enumerated().sorted {
            $0.element.cosine != $1.element.cosine ? $0.element.cosine > $1.element.cosine : $0.offset < $1.offset
        }.map(\.element.id)
    }

    private static func estimate(_ characters: Int) -> Int { characters / 3 }

    /// Keeps passages in order while they fit the context left after output and slack.
    private func fit(
        _ passages: [AskPassage], question: String, history: [NoteChatTurn], info: [AskSource: AskItemInfo]
    ) -> [AskPassage] {
        let promptChars = question.count + history.reduce(0) { $0 + $1.message.count + $1.reply.count }
        var available = contextTokens - Self.outputTokens - Self.slackTokens - Self.estimate(promptChars)
        var kept: [AskPassage] = []
        for p in passages {
            let item = info[p.source]
            let header = 24 + (item?.title.count ?? 0) + (item?.people.joined(separator: ", ").count ?? 0)
            let cost = Self.estimate(p.searchText.count + header)
            guard cost <= available else { break }
            available -= cost
            kept.append(p)
        }
        return kept
    }
}
