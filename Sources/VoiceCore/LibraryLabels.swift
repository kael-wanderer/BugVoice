import Foundation

/// Stable id of a folder in `library.json`. Survives folder renames.
public struct FolderID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func new() -> FolderID {
        FolderID(rawValue: UUID().uuidString.lowercased())
    }

    public var description: String { rawValue }
}

/// Tag names are stored lowercase, without `#`. Letters of any script,
/// digits, `-`, `_` and `/` are kept; spaces become `-`.
public enum TagName {
    public static let maxLength = 32

    public static func normalize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("#") { text.removeFirst() }
        text = text
            .precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: "-")

        var kept = String.UnicodeScalarView()
        var previousWasLetter = false
        for scalar in text.unicodeScalars {
            let isLetter = scalar.properties.isAlphabetic
            let isDigit = scalar.properties.numericType == .decimal
            let isPunctuation = scalar == "-" || scalar == "_" || scalar == "/"
            let isMark = scalar.properties.generalCategory == .nonspacingMark
            if isLetter || isDigit || isPunctuation || (isMark && previousWasLetter) {
                kept.append(scalar)
                previousWasLetter = isLetter || (isMark && previousWasLetter)
            } else {
                previousWasLetter = false
            }
        }
        let result = String(kept)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_/"))
            .precomposedStringWithCanonicalMapping
        guard !result.isEmpty, result.count <= maxLength else { return nil }
        return result
    }
}

/// The folder and tags one note or meeting carries.
public struct ItemLabels: Codable, Equatable, Sendable {
    public static let maxTags = 10

    public enum AddResult: Equatable, Sendable {
        case added, duplicate, invalid, full
    }

    public var folderID: FolderID?
    public var tags: [String]

    public init(folderID: FolderID? = nil, tags: [String] = []) {
        self.folderID = folderID
        self.tags = tags
    }

    @discardableResult
    public mutating func addTag(_ raw: String) -> AddResult {
        guard let tag = TagName.normalize(raw) else { return .invalid }
        guard !tags.contains(tag) else { return .duplicate }
        guard tags.count < Self.maxTags else { return .full }
        tags.append(tag)
        return .added
    }

    public mutating func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}
