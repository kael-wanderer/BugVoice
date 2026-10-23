import Foundation

public enum CommandPrompt {
    public static let maxSelection = 8_000
    public static let rewriteRules = "You edit text for the user. Apply the instruction to the text inside <text> tags. Output only the resulting text: no preamble, no quotes, no tags, no explanation. Keep the text's language unless the instruction asks to translate. Keep names, code, paths, numbers and Markdown formatting unless the instruction says otherwise."
    public static let writeRules = "You write text for the user. Write the text the instruction asks for. Output only the text: no preamble, no quotes, no tags, no explanation. Write in the language of the instruction unless it asks for another."

    public static func request(
        instruction: String, selection: String?, style: Style, focus: FocusSnapshot,
        vocabulary: Vocabulary, language: SpeechLanguage, keepEnglishWords: Bool,
        modelID: String, disableThinking: Bool
    ) -> CleanupRequest {
        let rewriting = !(selection ?? "").isEmpty
        var parts = [rewriting ? rewriteRules : writeRules, "App style, for tone: " + PromptBuilder.defaultRules(for: style)]
        if keepEnglishWords && (language == .vi || language == .auto) { parts.append(PromptBuilder.keepEnglishRule) }
        if keepEnglishWords && language == .es { parts.append(PromptBuilder.keepEnglishSpanishRule) }
        if !vocabulary.terms.isEmpty { parts.append("Spell these terms exactly: " + vocabulary.terms.joined(separator: ", ")) }
        if !vocabulary.projectWords.isEmpty { parts.append(PromptBuilder.projectWordsLine(vocabulary.projectWords)) }
        if !rewriting, let before = focus.beforeText, !before.isEmpty {
            parts.append("Text already before the cursor, for context only. Do not repeat it:\n<before>\(String(before.suffix(500)))</before>")
        }
        var user = "<instruction>\n\(instruction)\n</instruction>"
        if rewriting, let selection { user += "\n<text>\n\(selection)\n</text>" }
        let suppressThinking = disableThinking && modelID.lowercased().contains("qwen")
        if suppressThinking { user += "\n\n/no_think" }
        return CleanupRequest(system: parts.joined(separator: "\n\n"), user: user,
            maxTokens: min(8_192, max(512, (selection?.count ?? 0) + 1_024)), temperature: 0.3,
            disableThinking: suppressThinking)
    }
}

public enum CommandOutput {
    public enum Rejection: Error, Equatable, Sendable { case empty, tooLong }
    public static func sanitize(_ output: String, selection: String?) -> Result<String, Rejection> {
        var text = OutputSanitizer.stripReasoning(output)
            .replacingOccurrences(of: "</?(?:text|instruction)>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let newline = text.firstIndex(of: "\n") {
            let first = text[..<newline].trimmingCharacters(in: .whitespaces)
            if first.hasSuffix(":"), first.split(whereSeparator: \.isWhitespace).count <= 12,
               !(selection ?? "").contains(first) {
                text = String(text[text.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        for (open, close) in [("\"", "\""), ("“", "”"), ("'", "'")] {
            if text.count >= 2, text.hasPrefix(open), text.hasSuffix(close), !(selection ?? "").hasPrefix(open) {
                text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        if text.isEmpty { return .failure(.empty) }
        if text.count > 4 * (selection?.count ?? 0) + 2_000 { return .failure(.tooLong) }
        return .success(text)
    }
}
