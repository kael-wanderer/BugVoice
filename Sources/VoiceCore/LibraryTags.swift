import Foundation

public enum TagColor: String, Codable, CaseIterable, Sendable {
    case red, orange, yellow, green, teal, blue, purple
}

public struct LibraryTag: Codable, Equatable, Sendable {
    public var name: String
    public var color: TagColor?

    public init(name: String, color: TagColor?) {
        self.name = name
        self.color = color
    }

    private enum CodingKeys: String, CodingKey { case name, color }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        color = try c.decodeIfPresent(String.self, forKey: .color).flatMap(TagColor.init(rawValue:))
    }
}

public enum TagEdit {
    public static func rename(_ old: String, to new: String, in tags: [String]) -> [String] {
        guard old != new else { return tags }
        if tags.contains(new) { return remove(old, from: tags) }
        return tags.map { $0 == old ? new : $0 }
    }

    public static func remove(_ name: String, from tags: [String]) -> [String] {
        tags.filter { $0 != name }
    }
}

public enum TagCreateResult: Equatable, Sendable {
    case created(String), exists(String), invalid
}

public enum LibraryTags {
    public static func color(of name: String, in file: LibraryFile) -> TagColor? {
        file.tags.first { $0.name == name }?.color
    }

    public static func create(_ raw: String, inUse: Set<String>, in file: inout LibraryFile) -> TagCreateResult {
        guard let name = TagName.normalize(raw) else { return .invalid }
        guard !inUse.contains(name), !file.tags.contains(where: { $0.name == name }) else { return .exists(name) }
        file.tags.append(LibraryTag(name: name, color: nil))
        return .created(name)
    }

    public static func setColor(_ color: TagColor?, for name: String, in file: inout LibraryFile) {
        if let index = file.tags.firstIndex(where: { $0.name == name }) {
            file.tags[index].color = color
        } else {
            file.tags.append(LibraryTag(name: name, color: color))
        }
    }

    public static func rename(_ old: String, to new: String, in file: inout LibraryFile) {
        guard old != new else { return }
        let source = file.tags.first { $0.name == old }
        let target = file.tags.first { $0.name == new }
        delete(old, in: &file)
        if source != nil || target != nil {
            setColor(target?.color ?? source?.color, for: new, in: &file)
        }
    }

    public static func delete(_ name: String, in file: inout LibraryFile) {
        file.tags.removeAll { $0.name == name }
    }
}

public struct TagRow: Equatable, Sendable, Identifiable {
    public let name: String
    public let color: TagColor?
    public let notes: Int
    public let meetings: Int
    public var id: String { name }

    public init(name: String, color: TagColor?, notes: Int, meetings: Int) {
        self.name = name
        self.color = color
        self.notes = notes
        self.meetings = meetings
    }

    public var countText: String {
        var parts: [String] = []
        if notes > 0 { parts.append("\(notes) \(notes == 1 ? "note" : "notes")") }
        if meetings > 0 { parts.append("\(meetings) \(meetings == 1 ? "meeting" : "meetings")") }
        return parts.isEmpty ? "not used" : parts.joined(separator: " · ")
    }
}

extension LibraryProjection {
    public static func tagRows(notes: [TagCount], meetings: [TagCount], file: LibraryFile) -> [TagRow] {
        let names = Set(notes.map(\.name) + meetings.map(\.name) + file.tags.map(\.name))
        return names.sorted().map { name in
            TagRow(name: name, color: LibraryTags.color(of: name, in: file),
                   notes: notes.first { $0.name == name }?.count ?? 0,
                   meetings: meetings.first { $0.name == name }?.count ?? 0)
        }
    }
}
