import Foundation

/// Reads the JSON object a model was asked to reply with. Local models often add
/// a stray closing bracket or a sentence after the object, which strict parsing
/// rejects; this reads the first balanced `{...}` and ignores what follows.
public enum ModelJSON {
    /// The first top-level JSON object in `text`, or nil when there is none or it is not valid JSON.
    public static func object(_ text: String) -> [String: Any]? {
        guard let slice = firstObjectText(text) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(slice.utf8))) as? [String: Any]
    }

    /// The text from the first `{` to its matching `}`, skipping braces inside strings.
    static func firstObjectText(_ text: String) -> Substring? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let c = text[index]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 { return text[start...index] }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
