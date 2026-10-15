import Foundation

/// The folder menu choice on a page. Stored in settings as its raw value.
public enum FolderFilter: Hashable, Sendable {
    case all
    case unfiled
    case folder(FolderID)

    public init(rawValue: String) {
        switch rawValue {
        case "all", "": self = .all
        case "unfiled": self = .unfiled
        default: self = .folder(FolderID(rawValue: rawValue))
        }
    }

    public var rawValue: String {
        switch self {
        case .all: "all"
        case .unfiled: "unfiled"
        case .folder(let id): id.rawValue
        }
    }

    /// A filter naming a deleted folder shows everything.
    public func resolved(known: Set<FolderID>) -> FolderFilter {
        if case .folder(let id) = self, !known.contains(id) { return .all }
        return self
    }

    /// New notes and meetings go into the folder being viewed.
    public var newItemFolderID: FolderID? {
        if case .folder(let id) = self { return id }
        return nil
    }
}

public protocol LibraryLabeled {
    var labelFolderID: FolderID? { get }
    var labelTags: [String] { get }
}

extension MeetingManifest: LibraryLabeled {
    public var labelFolderID: FolderID? { folderID }
    public var labelTags: [String] { tags }
}

extension NoteDocument: LibraryLabeled {
    public var labelFolderID: FolderID? { frontMatter.folderID }
    public var labelTags: [String] { frontMatter.tags }
}

public struct FolderCounts: Equatable, Sendable {
    public var all = 0
    public var unfiled = 0
    public var byFolder: [FolderID: Int] = [:]

    public init() {}

    public func count(_ id: FolderID) -> Int { byFolder[id] ?? 0 }
}

public struct TagCount: Equatable, Sendable, Identifiable {
    public let name: String
    public let count: Int
    public var id: String { name }

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public enum LibraryProjection {
    /// An unknown folder id counts as Unfiled.
    static func effectiveFolder(_ id: FolderID?, known: Set<FolderID>) -> FolderID? {
        guard let id, known.contains(id) else { return nil }
        return id
    }

    public static func matches<T: LibraryLabeled>(_ item: T, folder: FolderFilter, tags: [String], known: Set<FolderID>) -> Bool {
        let effective = effectiveFolder(item.labelFolderID, known: known)
        switch folder {
        case .all: break
        case .unfiled: if effective != nil { return false }
        case .folder(let id): if effective != id { return false }
        }
        return tags.allSatisfy(item.labelTags.contains)
    }

    public static func filter<T: LibraryLabeled>(_ items: [T], folder: FolderFilter, tags: [String], known: Set<FolderID>) -> [T] {
        items.filter { matches($0, folder: folder, tags: tags, known: known) }
    }

    public static func counts<T: LibraryLabeled>(_ items: [T], known: Set<FolderID>) -> FolderCounts {
        var counts = FolderCounts()
        for item in items {
            counts.all += 1
            if let id = effectiveFolder(item.labelFolderID, known: known) {
                counts.byFolder[id, default: 0] += 1
            } else {
                counts.unfiled += 1
            }
        }
        return counts
    }

    public static func catalog<T: LibraryLabeled>(_ items: [T]) -> [TagCount] {
        var totals: [String: Int] = [:]
        for item in items {
            for tag in Set(item.labelTags) { totals[tag, default: 0] += 1 }
        }
        return totals.map { TagCount(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }
}
