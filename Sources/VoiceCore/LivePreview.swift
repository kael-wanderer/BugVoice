import Foundation

public enum LivePreviewPolicy {
    public static func isEnabled(settings: AppSettings, secureField: Bool, meetingRecording: Bool, speechReady: Bool) -> Bool {
        settings.speech.livePreview && settings.speech.engine == .whisperKit
            && !secureField && !meetingRecording && speechReady
    }
}

public enum LivePreviewCadence {
    public static let firstPassAfter: TimeInterval = 1.0
    public static let gapAfterPass: TimeInterval = 0.6
    public static let window: TimeInterval = 15

    public static func shouldStart(recorded: TimeInterval, running: Bool, lastReturnedAt: Date?, now: Date) -> Bool {
        guard recorded >= firstPassAfter, !running else { return false }
        return lastReturnedAt.map { now.timeIntervalSince($0) >= gapAfterPass } ?? true
    }
}

/// Display-only text. Never feeds the final transcription or persistence.
public enum LivePreviewText {
    public static let maxCharacters = 140

    public static func display(_ transcript: String) -> String? {
        let text = HallucinationFilter.strip(DictationPipeline.stripPlaceholders(transcript))
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty, !HallucinationFilter.isHallucination(text) else { return nil }
        guard text.count > maxCharacters else { return text }
        var suffix = text.suffix(maxCharacters)
        let boundary = text.index(text.endIndex, offsetBy: -maxCharacters)
        // Keep a complete first word when the suffix already starts at a boundary.
        if !suffix.first!.isWhitespace, !text[text.index(before: boundary)].isWhitespace,
           let space = suffix.firstIndex(where: \.isWhitespace) {
            let remainder = suffix[suffix.index(after: space)...]
            if !remainder.isEmpty { suffix = remainder }
        }
        return "…" + suffix.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
