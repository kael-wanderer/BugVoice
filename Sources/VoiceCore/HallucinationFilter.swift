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
        "hãy subscribe cho kênh ghiền mì gõ để không bỏ lỡ những video hấp dẫn",
        "cảm ơn các bạn đã theo dõi",
        "cảm ơn các bạn đã xem video",
        "hẹn gặp lại các bạn trong những video tiếp theo",
    ]

    public static func isHallucination(_ text: String) -> Bool {
        let normalized = text.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters.union(.symbols))
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return normalized.isEmpty || phrases.contains(normalized)
    }
}
