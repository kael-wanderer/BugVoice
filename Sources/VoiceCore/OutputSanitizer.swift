import Foundation

public enum RawReason: String, Codable, Sendable {
    case detailChanged, cleanupOff, modelError, modelTimeout, emptyOutput, tooLong, placeholderLost
}

public enum SanitizeResult: Equatable, Sendable {
    case accepted(String)
    case rejected(RawReason)
}

public enum OutputSanitizer {
    static func stripReasoning(_ output: String) -> String {
        var text = output.replacingOccurrences(of: "(?s)<think>.*?</think>", with: "", options: .regularExpression)
        // A closing tag with no opener: the chat template opened the block.
        if let close = text.range(of: "</think>") {
            text = String(text[close.upperBound...])
        }
        // An opener with no closer: everything after it is reasoning.
        if let open = text.range(of: "<think>") {
            text = String(text[..<open.lowerBound])
        }
        return text
    }

    public static func sanitize(_ output: String, raw: String) -> SanitizeResult {
        var text = stripReasoning(output)
        text = text.replacingOccurrences(of: "</?dictation>", with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .rejected(.emptyOutput) }
        if text.count > raw.count * 2 + 50 { return .rejected(.tooLong) }
        return .accepted(text)
    }
}
