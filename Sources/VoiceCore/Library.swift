import Foundation

public struct LibraryFolder: Codable, Equatable, Sendable, Identifiable {
    public let id: FolderID
    public var name: String
    public let createdAt: Date

    public init(id: FolderID, name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// `library.json`: the folder list. Notes and meetings store their own labels.
public struct LibraryFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var folders: [LibraryFolder]
    public var tags: [LibraryTag]
    public var lastUploadFolderID: FolderID?

    public init(version: Int = LibraryFile.currentVersion, folders: [LibraryFolder] = [], lastUploadFolderID: FolderID? = nil, tags: [LibraryTag] = []) {
        self.tags = tags
        self.version = version
        self.folders = folders
        self.lastUploadFolderID = lastUploadFolderID
    }

    private enum CodingKeys: String, CodingKey { case version, folders, lastUploadFolderID, tags }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        folders = try c.decode([LibraryFolder].self, forKey: .folders)
        lastUploadFolderID = try c.decodeIfPresent(FolderID.self, forKey: .lastUploadFolderID)
        tags = try c.decodeIfPresent([LibraryTag].self, forKey: .tags) ?? []
    }

    public func folder(_ id: FolderID?) -> LibraryFolder? {
        guard let id else { return nil }
        return folders.first { $0.id == id }
    }

    public var knownIDs: Set<FolderID> { Set(folders.map(\.id)) }
}

public enum LibraryFolderError: Error, Equatable, Sendable, LocalizedError {
    case empty, tooLong, duplicate, reserved, missing, readOnly

    public var errorDescription: String? {
        switch self {
        case .empty: "Enter a folder name."
        case .tooLong: "Folder names can be up to 40 characters."
        case .duplicate: "A folder with this name already exists."
        case .reserved: "This name is reserved."
        case .missing: "This folder no longer exists."
        case .readOnly: "Folders were saved by a newer BugVoice. Folder changes are turned off."
        }
    }
}

public enum LibraryFolders {
    public static let maxNameLength = 40
    static let reservedKeys: Set<String> = ["unfiled", "all"]

    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "đ", with: "d")
    }

    static func validate(_ name: String, in file: LibraryFile, excluding: FolderID?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryFolderError.empty }
        guard trimmed.count <= maxNameLength else { throw LibraryFolderError.tooLong }
        let candidate = key(trimmed)
        guard !reservedKeys.contains(candidate) else { throw LibraryFolderError.reserved }
        guard !file.folders.contains(where: { $0.id != excluding && key($0.name) == candidate }) else {
            throw LibraryFolderError.duplicate
        }
        return trimmed
    }

    @discardableResult
    public static func create(_ name: String, in file: inout LibraryFile, now: Date = Date()) throws -> LibraryFolder {
        let trimmed = try validate(name, in: file, excluding: nil)
        let folder = LibraryFolder(id: .new(), name: trimmed, createdAt: now)
        file.folders.append(folder)
        return folder
    }

    public static func rename(_ id: FolderID, to name: String, in file: inout LibraryFile) throws {
        guard let index = file.folders.firstIndex(where: { $0.id == id }) else { throw LibraryFolderError.missing }
        file.folders[index].name = try validate(name, in: file, excluding: id)
    }

    /// Removes the folder only. Items keeping its id show as Unfiled.
    public static func delete(_ id: FolderID, in file: inout LibraryFile) {
        file.folders.removeAll { $0.id == id }
        if file.lastUploadFolderID == id { file.lastUploadFolderID = nil }
    }

    public static func sorted(_ folders: [LibraryFolder]) -> [LibraryFolder] {
        folders.sorted {
            let left = key($0.name), right = key($1.name)
            return left == right ? $0.id.rawValue < $1.id.rawValue : left < right
        }
    }
}

public enum LibraryLoadResult: Equatable, Sendable {
    case loaded(LibraryFile)
    case missing
    /// The file could not be read; it was renamed to `backupName` in the same folder.
    case reset(backupName: String)
    /// Written by a newer BugVoice: show what can be read, never write.
    case newer(LibraryFile)
}

public actor LibraryStore {
    private let url: URL
    private let now: @Sendable () -> Date

    public init(url: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.url = url
        self.now = now
    }

    public func load() -> LibraryLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url) else { return backup() }
        if let header = try? decoder.decode(VersionHeader.self, from: data), header.version > LibraryFile.currentVersion {
            let folders = (try? decoder.decode(FoldersOnly.self, from: data))?.folders ?? []
            return .newer(LibraryFile(version: header.version, folders: folders))
        }
        guard let file = try? decoder.decode(LibraryFile.self, from: data) else { return backup() }
        return .loaded(file)
    }

    public func save(_ file: LibraryFile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    private func backup() -> LibraryLoadResult {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        var name = "library.corrupt-\(formatter.string(from: now())).json"
        var destination = url.deletingLastPathComponent().appendingPathComponent(name)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            name = "library.corrupt-\(formatter.string(from: now()))-\(suffix).json"
            destination = url.deletingLastPathComponent().appendingPathComponent(name)
            suffix += 1
        }
        try? FileManager.default.moveItem(at: url, to: destination)
        return .reset(backupName: name)
    }

    private struct VersionHeader: Decodable { let version: Int }
    private struct FoldersOnly: Decodable { let folders: [LibraryFolder] }
}
