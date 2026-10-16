import Foundation

/// English under non-English meeting lines: which lines need it, what to send, how to read the reply.
public enum MeetingTranslation {
    /// Lines per request.
    public static let batchSize = 12
    /// Wait after a failed request before the next one.
    public static let retryDelay: TimeInterval = 30

    public static let systemPrompt = """
    You translate meeting transcript lines into English. Each input line starts with its number. \
    Return the same numbers, one line each, as `N. English text`. Keep names, product names and \
    technical terms as they are. When a line is already English, return it unchanged. Return only \
    the numbered lines.
    """

    /// Whether a meeting in these languages gets English lines.
    public static func isOffered(_ languages: [SpeechLanguage]) -> Bool {
        languages.contains { $0 != .en && $0 != .auto }
    }

    /// The lines that need English next, oldest first, at most `batchSize`.
    /// English lines are sent too: Whisper's chunk language is often "en" for
    /// Spanish speech, so the model decides and returns English lines unchanged.
    public static func pending(in meeting: MeetingManifest) -> [MeetingSegment] {
        guard meeting.showEnglish, isOffered(meeting.languages) else { return [] }
        let lines = meeting.segments.filter {
            $0.translation == nil && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return Array(lines.sorted { $0.start < $1.start }.prefix(batchSize))
    }

    public static func request(lines: [MeetingSegment], budget: MeetingTextBudget) -> CleanupRequest {
        let user = lines.enumerated().map { index, segment in
            "\(index + 1). " + segment.text.split(whereSeparator: \.isNewline).joined(separator: " ")
        }.joined(separator: "\n")
        // Thinking off: a reasoning model takes about five times as long and adds nothing here.
        return CleanupRequest(system: systemPrompt, user: user, maxTokens: min(2_048, budget.outputTokens), disableThinking: true)
    }

    /// English by segment id. Lines the reply left out are missing; a line
    /// returned unchanged maps to "" so it is not sent again. When a number
    /// repeats, the last one wins: a model that writes its reasoning into the
    /// reply puts the answer after it.
    public static func parse(_ reply: String, lines: [MeetingSegment]) -> [String: String] {
        var result: [String: String] = [:]
        for raw in reply.split(whereSeparator: \.isNewline) {
            let text = raw.trimmingCharacters(in: .whitespaces)
            let digits = text.prefix { $0.isASCII && $0.isNumber }
            guard let number = Int(digits), lines.indices.contains(number - 1) else { continue }
            let rest = text.dropFirst(digits.count)
            guard rest.first == "." || rest.first == ")" else { continue }
            let english = rest.dropFirst().trimmingCharacters(in: .whitespaces)
            let segment = lines[number - 1]
            guard !english.isEmpty else { continue }
            result[segment.id] = comparable(english) == comparable(segment.text) ? "" : english
        }
        return result
    }

    /// Keeps the English of live lines on final lines with the same text and
    /// track that start within 1 second of them.
    public static func carryOver(from live: [MeetingSegment], to final: [MeetingSegment]) -> [MeetingSegment] {
        final.map { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard segment.translation == nil,
                  let match = live.first(where: {
                      $0.translation != nil && $0.track == segment.track && abs($0.start - segment.start) <= 1
                          && $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == text
                  }) else { return segment }
            var carried = segment
            carried.translation = match.translation
            return carried
        }
    }

    private static func comparable(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) })
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
