import Foundation

/// Adds the spaces a dictation needs to sit between the words around it, so a
/// second dictation does not run into the first ("featureHello").
public enum NotesSpacing {
    /// `location` and `length` are UTF-16 offsets into `body`, as in NSRange.
    public static func fit(_ text: String, into body: String, at location: Int, replacing length: Int = 0) -> String {
        guard let first = text.first, let last = text.last else { return text }
        let units = body as NSString
        let before = location > 0 ? character(in: units, endingAt: location) : nil
        let end = location + length
        let after = end < units.length ? character(in: units, startingAt: end) : nil

        var result = text
        if let before, needsSpace(after: before), !first.isWhitespace, !isClosingPunctuation(first) {
            result = " " + result
        }
        if let after, after.isLetter || after.isNumber, !last.isWhitespace {
            result += " "
        }
        return result
    }

    private static func needsSpace(after character: Character) -> Bool {
        !character.isWhitespace && !"([{\"'“‘/-".contains(character)
    }

    private static func isClosingPunctuation(_ character: Character) -> Bool {
        ".,;:!?)]}…".contains(character)
    }

    private static func character(in units: NSString, endingAt offset: Int) -> Character? {
        let range = units.rangeOfComposedCharacterSequence(at: offset - 1)
        return units.substring(with: range).first
    }

    private static func character(in units: NSString, startingAt offset: Int) -> Character? {
        let range = units.rangeOfComposedCharacterSequence(at: offset)
        return units.substring(with: range).first
    }
}
