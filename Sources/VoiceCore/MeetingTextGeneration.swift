import Foundation

public struct MeetingTextBudget: Equatable, Sendable {
    public let contextTokens: Int
    public let outputTokens: Int
    public var inputTokens: Int { max(1, contextTokens - outputTokens - 1_024) }

    public init(contextTokens: Int = 8_192, outputTokens: Int = 2_048) {
        let context = max(2_048, contextTokens)
        self.contextTokens = context
        self.outputTokens = min(max(256, outputTokens), context - 1_024)
    }

    public init(settings: MeetingSettings) {
        self.init(contextTokens: settings.generationContextTokens, outputTokens: settings.generationOutputTokens)
    }
}

public struct MeetingTranscriptPart: Equatable, Sendable {
    public let segments: [MeetingSegment]
    public let estimatedTokens: Int

    public var promptText: String {
        segments.map { "[\(timestamp($0.start))–\(timestamp($0.end)) \($0.speaker)] \($0.text)" }
            .joined(separator: "\n")
    }

    public init(segments: [MeetingSegment]) {
        self.segments = segments
        let formattedCharacterCount = segments.reduce(0) { partial, segment in
            partial + segment.text.count + timestamp(segment.start).count + timestamp(segment.end).count + segment.speaker.count + 7
        } + max(0, segments.count - 1)
        self.estimatedTokens = max(1, (formattedCharacterCount + 2) / 3)
    }

    public static func split(transcript: [MeetingSegment], budget: MeetingTextBudget) -> [MeetingTranscriptPart] {
        let maxCharacters = max(1, budget.inputTokens * 3)
        var parts: [MeetingTranscriptPart] = []
        var current: [MeetingSegment] = []
        var currentCharacters = 0

        func flush() {
            guard !current.isEmpty else { return }
            parts.append(MeetingTranscriptPart(segments: current))
            current = []
            currentCharacters = 0
        }

        for segment in transcript {
            let markerLength = timestamp(segment.start).count + timestamp(segment.end).count + segment.speaker.count + 7
            let renderedLength = max(1, segment.text.count + markerLength)
            if renderedLength <= maxCharacters {
                if currentCharacters + renderedLength > maxCharacters { flush() }
                current.append(segment)
                currentCharacters += renderedLength
                continue
            }

            flush()
            for fragment in textFragments(segment.text, maximumCharacters: max(1, maxCharacters - markerLength)) {
                let piece = MeetingSegment(
                    start: segment.start, end: segment.end, text: fragment,
                    track: segment.track, sourceChunkID: segment.sourceChunkID
                )
                parts.append(MeetingTranscriptPart(segments: [piece]))
            }
        }
        flush()
        return parts
    }
}

public enum MeetingTextKind: String, Codable, Sendable {
    case summary
    case actionItems
}

public enum MeetingTextPhase: String, Sendable {
    case parts
    case merge
}

public struct MeetingTextProgress: Equatable, Sendable {
    public let phase: MeetingTextPhase
    public let completedParts: Int
    public let totalParts: Int
    public var fraction: Double { totalParts == 0 ? 1 : Double(completedParts) / Double(totalParts) }

    public init(phase: MeetingTextPhase, completedParts: Int, totalParts: Int) {
        self.phase = phase
        self.completedParts = completedParts
        self.totalParts = totalParts
    }
}

public enum MeetingTextGenerationError: Error, Equatable, Sendable {
    case mergeDidNotReduceToFitContext
}

public struct MeetingTextGenerator: Sendable {
    public init() {}

    public func generate(
        transcript: [MeetingSegment],
        kind: MeetingTextKind,
        budget rawBudget: MeetingTextBudget,
        model: any TextModel,
        progress: @Sendable (MeetingTextProgress) -> Void = { _ in }
    ) async throws -> String {
        try Task.checkCancellation()
        let budget = MeetingTextBudget(contextTokens: rawBudget.contextTokens, outputTokens: rawBudget.outputTokens)
        let parts = MeetingTranscriptPart.split(transcript: transcript, budget: budget)
        guard !parts.isEmpty else { return "" }

        var results: [String] = []
        for (index, part) in parts.enumerated() {
            try Task.checkCancellation()
            let answer = try await model.clean(CleanupRequest(
                system: systemPrompt(kind: kind, stage: .part),
                user: "Part \(index + 1) of \(parts.count):\n\(part.promptText)",
                maxTokens: budget.outputTokens
            ))
            try Task.checkCancellation()
            results.append(answer.trimmingCharacters(in: .whitespacesAndNewlines))
            progress(MeetingTextProgress(phase: .parts, completedParts: index + 1, totalParts: parts.count))
        }

        var level = results
        while level.count > 1 {
            try Task.checkCancellation()
            var next: [String] = []
            let groups = grouped(level, maximumCharacters: budget.inputTokens * 3)
            for (index, group) in groups.enumerated() {
                try Task.checkCancellation()
                guard group.reduce(0, { $0 + $1.count }) <= budget.inputTokens * 3 else {
                    throw MeetingTextGenerationError.mergeDidNotReduceToFitContext
                }
                let answer = try await model.clean(CleanupRequest(
                    system: systemPrompt(kind: kind, stage: .merge),
                    user: "Merge these results (group \(index + 1) of \(groups.count)):\n\(group.joined(separator: "\n"))",
                    maxTokens: budget.outputTokens
                ))
                try Task.checkCancellation()
                next.append(answer.trimmingCharacters(in: .whitespacesAndNewlines))
                progress(MeetingTextProgress(phase: .merge, completedParts: index + 1, totalParts: groups.count))
            }
            guard next.count < level.count else {
                throw MeetingTextGenerationError.mergeDidNotReduceToFitContext
            }
            level = next
        }

        let finalText = level[0]
        return kind == .actionItems ? deduplicatedBullets(finalText) : finalText
    }

    private enum Stage { case part, merge }

    private func systemPrompt(kind: MeetingTextKind, stage: Stage) -> String {
        let kindInstruction = kind == .summary
            ? "Write a factual meeting summary. Keep names, decisions, and uncertainty faithful to the transcript."
            : "Extract action items as concise Markdown bullets. Include an owner only when stated."
        let stageInstruction = stage == .part ? "Process only the supplied transcript part." : "Combine the supplied partial results without adding facts."
        return "\(kindInstruction) \(stageInstruction)"
    }

    private func grouped(_ values: [String], maximumCharacters: Int) -> [[String]] {
        var groups: [[String]] = []
        var current: [String] = []
        var size = 0
        for value in values {
            if !current.isEmpty && size + value.count > maximumCharacters {
                groups.append(current)
                current = []
                size = 0
            }
            current.append(value)
            size += value.count
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    private func deduplicatedBullets(_ text: String) -> String {
        var seen: Set<String> = []
        return text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = line.drop(while: { $0 == "-" || $0 == "*" || $0 == "•" || $0.isWhitespace })
                .lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !line.isEmpty, seen.insert(normalized).inserted else { return nil }
            return line
        }.joined(separator: "\n")
    }
}

private func timestamp(_ seconds: Double) -> String {
    let value = max(0, Int(seconds))
    return String(format: "%d:%02d", value / 60, value % 60)
}

private func textFragments(_ text: String, maximumCharacters: Int) -> [String] {
    let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
    var fragments: [String] = []
    var current = ""
    for word in words {
        if word.count > maximumCharacters {
            if !current.isEmpty { fragments.append(current); current = "" }
            var remainder = word[...]
            while !remainder.isEmpty {
                let end = remainder.index(remainder.startIndex, offsetBy: min(maximumCharacters, remainder.count))
                fragments.append(String(remainder[..<end]))
                remainder = remainder[end...]
            }
        } else if current.isEmpty {
            current = word
        } else if current.count + 1 + word.count <= maximumCharacters {
            current += " " + word
        } else {
            fragments.append(current)
            current = word
        }
    }
    if !current.isEmpty { fragments.append(current) }
    return fragments
}
