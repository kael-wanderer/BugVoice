import Foundation

/// BugVoice's keys at the top of a note file. Lines from other apps are kept
/// verbatim in `extra` and written back after BugVoice's keys.
public struct NoteFrontMatter: Equatable, Sendable {
    public var folderID: FolderID?
    public var tags: [String]
    public var pinned: Bool
    public var extra: [String]

    public init(folderID: FolderID? = nil, tags: [String] = [], pinned: Bool = false, extra: [String] = []) {
        self.folderID = folderID
        self.tags = tags
        self.pinned = pinned
        self.extra = extra
    }

    public var isEmpty: Bool { folderID == nil && tags.isEmpty && !pinned && extra.isEmpty }
    public var labels: ItemLabels { ItemLabels(folderID: folderID, tags: tags) }
}

public struct NotesMarkdownParseResult: Sendable, Equatable {
    public let title: String
    public let body: String
    public let frontMatter: NoteFrontMatter
    public let needsNormalization: Bool

    public init(title: String, body: String, frontMatter: NoteFrontMatter = NoteFrontMatter(), needsNormalization: Bool) {
        self.title = title
        self.body = body
        self.frontMatter = frontMatter
        self.needsNormalization = needsNormalization
    }
}

public enum NotesDocumentError: Error, Equatable {
    case invalidUTF8
}

public enum NotesMarkdownDocument {
    public static func parse(data: Data, filename: String) throws -> NotesMarkdownParseResult {
        guard let original = String(data: data, encoding: .utf8) else {
            throw NotesDocumentError.invalidUTF8
        }
        let (frontMatter, source) = splitFrontMatter(original) ?? (NoteFrontMatter(), original)

        if let parsed = parseHeading(source) {
            let canonical = serialize(title: parsed.title, body: parsed.body, frontMatter: frontMatter)
            return NotesMarkdownParseResult(
                title: parsed.title,
                body: parsed.body,
                frontMatter: frontMatter,
                needsNormalization: canonical != data
            )
        }

        return NotesMarkdownParseResult(
            title: title(from: filename),
            body: source,
            frontMatter: frontMatter,
            needsNormalization: true
        )
    }

    public static func serialize(title: String, body: String) -> Data {
        serialize(title: title, body: body, frontMatter: NoteFrontMatter())
    }

    public static func serialize(title: String, body: String, frontMatter: NoteFrontMatter) -> Data {
        var text = ""
        if !frontMatter.isEmpty {
            text += "---\n"
            if let folderID = frontMatter.folderID { text += "folder: \(folderID.rawValue)\n" }
            if !frontMatter.tags.isEmpty { text += "tags: [\(frontMatter.tags.joined(separator: ", "))]\n" }
            if frontMatter.pinned { text += "pinned: true\n" }
            for line in frontMatter.extra { text += line + "\n" }
            text += "---\n"
        }
        text += "# \(title)\n\n\(body)"
        return Data(text.utf8)
    }

    /// Returns nil when the file does not start with a closed `---` block.
    private static func splitFrontMatter(_ source: String) -> (NoteFrontMatter, String)? {
        let lines = source.components(separatedBy: "\n")
        guard let first = lines.first, stripCR(first) == "---", lines.count > 1 else { return nil }
        guard let close = lines.indices.dropFirst().first(where: { stripCR(lines[$0]) == "---" }) else { return nil }

        var front = NoteFrontMatter()
        for raw in lines[1..<close] {
            let line = stripCR(raw)
            if line.hasPrefix("folder:") {
                let value = unquote(String(line.dropFirst("folder:".count)))
                front.folderID = value.isEmpty ? nil : FolderID(rawValue: value)
            } else if line.hasPrefix("tags:"), let tags = parseTagList(String(line.dropFirst("tags:".count))) {
                front.tags = tags
            } else if line.hasPrefix("pinned:") {
                front.pinned = unquote(String(line.dropFirst("pinned:".count))).lowercased() == "true"
            } else {
                front.extra.append(line)
            }
        }
        let remainder = lines[(close + 1)...].joined(separator: "\n")
        return (front, remainder)
    }

    private static func parseTagList(_ raw: String) -> [String]? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("["), value.hasSuffix("]") else { return nil }
        var tags: [String] = []
        for part in value.dropFirst().dropLast().split(separator: ",") {
            guard let tag = TagName.normalize(unquote(String(part))), !tags.contains(tag) else { continue }
            if tags.count < ItemLabels.maxTags { tags.append(tag) }
        }
        return tags
    }

    private static func unquote(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, let last = value.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func stripCR(_ line: String) -> String {
        line.hasSuffix("\r") ? String(line.dropLast()) : line
    }

    private static func parseHeading(_ source: String) -> (title: String, body: String)? {
        let firstLineEnd = source.firstIndex(where: { $0 == "\n" || $0 == "\r\n" }) ?? source.endIndex
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
