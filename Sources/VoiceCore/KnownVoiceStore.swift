import Foundation

/// `voices.json`: voice centroids stay on this Mac, readable by the owner only.
public actor KnownVoiceStore {
    private let url: URL

    public init(url: URL) { self.url = url }

    /// A missing file is an empty list.
    public func load() throws -> KnownVoiceFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return KnownVoiceFile() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(KnownVoiceFile.self, from: Data(contentsOf: url))
    }

    @discardableResult
    public func update(_ change: @Sendable (KnownVoiceFile) -> KnownVoiceFile) throws -> KnownVoiceFile {
        let current = try load()
        let updated = change(current)
        if updated != current || !FileManager.default.fileExists(atPath: url.path) { try save(updated) }
        return updated
    }

    private func save(_ file: KnownVoiceFile) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        // Written owner-only beside the file before it replaces it, like credentials.json.
        let temp = dir.appendingPathComponent(".voices-\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: temp) }
            else { try fm.moveItem(at: temp, to: url) }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
