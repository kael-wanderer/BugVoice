import Foundation

public struct NotesMarkdownParseResult: Sendable, Equatable {
    public let title: String
    public let body: String
    public let needsNormalization: Bool

    public init(title: String, body: String, needsNormalization: Bool) {
        self.title = title
        self.body = body
        self.needsNormalization = needsNormalization
    }
}

public enum NotesDocumentError: Error, Equatable {
    case invalidUTF8
}

public enum NotesMarkdownDocument {
    public static func parse(data: Data, filename: String) throws -> NotesMarkdownParseResult {
        guard let source = String(data: data, encoding: .utf8) else {
            throw NotesDocumentError.invalidUTF8
        }

        if let parsed = parseHeading(source) {
            let canonical = serialize(title: parsed.title, body: parsed.body)
            return NotesMarkdownParseResult(
                title: parsed.title,
                body: parsed.body,
                needsNormalization: canonical != data
            )
        }

        return NotesMarkdownParseResult(
            title: title(from: filename),
            body: source,
            needsNormalization: true
        )
    }

    public static func serialize(title: String, body: String) -> Data {
        Data("# \(title)\n\n\(body)".utf8)
    }

    private static func parseHeading(_ source: String) -> (title: String, body: String)? {
        let firstLineEnd = source.firstIndex(of: "\n") ?? source.endIndex
        var heading = String(source[..<firstLineEnd])
        if heading.last == "\r" { heading.removeLast() }
        guard heading.hasPrefix("# ") else { return nil }

        let title = String(heading.dropFirst(2))
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        guard firstLineEnd < source.endIndex else { return (title, "") }
        var bodyStart = source.index(after: firstLineEnd)
        if source[bodyStart...].hasPrefix("\r\n") {
            bodyStart = source.index(bodyStart, offsetBy: 2)
        } else if source[bodyStart...].hasPrefix("\n") {
            bodyStart = source.index(after: bodyStart)
        }
        return (title, String(source[bodyStart...]))
    }

    private static func title(from filename: String) -> String {
        let name = URL(fileURLWithPath: filename).lastPathComponent
        let stem = name.lowercased().hasSuffix(".md") ? String(name.dropLast(3)) : name
        let title = stem.replacingOccurrences(of: "-", with: " ")
        return title.isEmpty ? "Note" : title
    }
}

public enum NotesSlug {
    public static func make(_ title: String) -> String {
        let mapped = title
            .replacingOccurrences(of: "Đ", with: "D")
            .replacingOccurrences(of: "đ", with: "d")
            .decomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        var slug = ""
        var needsHyphen = false
        for scalar in mapped.unicodeScalars {
            let value = scalar.value
            let isASCIIAlphaNumeric = (value >= 97 && value <= 122) || (value >= 48 && value <= 57)
            if isASCIIAlphaNumeric {
                if needsHyphen, !slug.isEmpty { slug.append("-") }
                slug.unicodeScalars.append(scalar)
                needsHyphen = false
            } else {
                needsHyphen = true
            }
        }
        return slug.isEmpty ? "note" : slug
    }

    public static func available(
        _ title: String,
        existingFilenames: [String],
        excludingFilename: String? = nil
    ) -> String {
        let base = make(title)
        let excluded = excludingFilename.map(normalizedFilename)
        let existing = Set(existingFilenames.map(normalizedFilename).filter { $0 != excluded })
        var suffix = 1
        while true {
            let candidate = suffix == 1 ? base : "\(base)-\(suffix)"
            if !existing.contains("\(candidate).md") { return candidate }
            suffix += 1
        }
    }

    private static func normalizedFilename(_ filename: String) -> String {
        filename.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
