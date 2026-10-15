import Foundation

public enum DictionaryLoadIssue: Equatable, Sendable {
    case none
    case resetFromCorrupt
    case newerVersion
}

public enum DictionaryStoreError: Error, Equatable {
    case newerVersion
}

/// Owns `dictionary.json`. Every write replaces the file atomically.
public actor DictionaryStore {
    public let url: URL
    private var loaded = false
    private var readOnly = false
    private var lastRevision = Int.min

    public init(url: URL) {
        self.url = url
    }

    @discardableResult
    public func load(now: Date = Date()) -> (DictionaryFile, DictionaryLoadIssue) {
        loaded = true
        readOnly = false
        guard FileManager.default.fileExists(atPath: url.path) else { return (DictionaryFile(), .none) }
        struct Header: Decodable { var schemaVersion: Int? }
        if let data = try? Data(contentsOf: url) {
            if let version = (try? JSONDecoder().decode(Header.self, from: data))?.schemaVersion,
               version > DictionaryFile.supportedSchemaVersion {
                readOnly = true
                return (DictionaryFile(), .newerVersion)
            }
            if let decoded = try? JSONDecoder().decode(DictionaryFile.self, from: data) {
                return (decoded, .none)
            }
        }
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("dictionary.corrupt-\(Int(now.timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: backup)
        return (DictionaryFile(), .resetFromCorrupt)
    }

    /// Saves older than the last revision written are ignored.
    public func save(_ file: DictionaryFile, revision: Int? = nil) throws {
        if !loaded { load() }
        if readOnly { throw DictionaryStoreError.newerVersion }
        if let revision {
            guard revision > lastRevision else { return }
            lastRevision = revision
        }
        try write(file)
    }

    /// Writes the migrated Dictionary before renaming `vocabulary.txt`.
    @discardableResult
    public func migrateIfNeeded(vocabularyURL: URL, now: Date = Date()) throws -> Bool {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path), fm.fileExists(atPath: vocabularyURL.path) else { return false }
        let text = try String(contentsOf: vocabularyURL, encoding: .utf8)
        try write(DictionaryFile(migrating: Vocabulary.parse(text)))
        let dir = vocabularyURL.deletingLastPathComponent()
        var target = dir.appendingPathComponent("vocabulary.migrated.txt")
        if fm.fileExists(atPath: target.path) {
            target = dir.appendingPathComponent("vocabulary.migrated-\(Int(now.timeIntervalSince1970)).txt")
        }
        try fm.moveItem(at: vocabularyURL, to: target)
        return true
    }

    private func write(_ file: DictionaryFile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
    }
}
