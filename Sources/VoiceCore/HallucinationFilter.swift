import Foundation

/// Whisper emits these on silence or noise. Only an exact match of the whole
/// transcript counts, so real speech containing the words is kept.
public enum HallucinationFilter {
    static let phrases: Set<String> = [
        "thank you",
        "thank you very much",
        "thanks for watching",
        "thank you for watching",
        "please subscribe",
        "you",
        "music",
        "hãy subscribe cho kênh ghiền mì gõ để không bỏ lỡ những video hấp dẫn",
        "cảm ơn các bạn đã theo dõi",
        "cảm ơn các bạn đã xem video",
        "hẹn gặp lại các bạn trong những video tiếp theo",
    ]

    /// Credits Whisper sometimes writes in the middle of real speech. Only lines nobody
    /// says in a dictation or a call are listed; "thank you" can be real and stays.
    static let embedded = [
        "hãy subscribe cho kênh ghiền mì gõ để không bỏ lỡ những video hấp dẫn",
        "hẹn gặp lại các bạn trong những video tiếp theo",
        "subtitles by the amara org community",
    ]

    private static let embeddedPatterns: [NSRegularExpression] = embedded.compactMap { phrase in
        let words = phrase.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
        let pattern = #"\s*"# + words.joined(separator: #"[\s\p{P}\p{S}]+"#) + #"\p{P}*"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// Removes `embedded` credits from inside longer text, ignoring case and punctuation.
    public static func strip(_ text: String) -> String {
        var result = text.precomposedStringWithCanonicalMapping
        for pattern in embeddedPatterns {
            result = pattern.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: " ")
        }
        guard result != text.precomposedStringWithCanonicalMapping else { return text }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func isHallucination(_ text: String) -> Bool {
        // Whisper annotations such as `[BLANK_AUDIO]`, `[ Silence ]` or `(breathing)`
        // describe the audio, not speech.
        let withoutAnnotations = text.replacing(/\[[^\]]*\]|\([^)]*\)/, with: " ")
        let normalized = withoutAnnotations.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters.union(.symbols))
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return normalized.isEmpty || phrases.contains(normalized) || isMostlyNonLatin(normalized)
    }

    /// BugVoice transcribes English and Vietnamese, both written in Latin
    /// script. Over music Whisper writes subtitle credits in other scripts
    /// ("Субтитры сделал …", "ご視聴ありがとうございました"), so text whose
    /// letters are mostly non-Latin is not speech from this user.
    static func isMostlyNonLatin(_ text: String) -> Bool {
        var latin = 0
        var other = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            if isLatin(scalar) { latin += 1 } else { other += 1 }
        }
        return other > latin
    }

    private static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A: true // ASCII letters
        case 0xC0...0x24F: true // Latin-1 Supplement, Latin Extended-A/B
        case 0x300...0x36F: true // combining diacritics
        case 0x1E00...0x1EFF: true // Latin Extended Additional (Vietnamese)
        default: false
        }
    }
}
