import Foundation

/// Hesitation sounds Whisper writes down on their own ("Um.", "Ah, e.", "ờ").
/// A meeting line made only of these says nothing.
public enum FillerFilter {
    static let fillers: Set<String> = [
        "uh", "uhh", "um", "umm", "uhm", "hm", "hmm", "mm", "mhm", "ah", "ahh", "eh", "er", "erm",
        "e", "ờ", "ơ", "à", "ừm", "ưm", "ậm", "ừ ừ"
    ]

    public static func isOnlyFiller(_ text: String) -> Bool {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines))
            .filter { !$0.isEmpty }
        return !words.isEmpty && words.allSatisfy(fillers.contains)
    }
}
