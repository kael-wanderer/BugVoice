import Foundation

public enum CredentialStoreError: Error, Equatable, LocalizedError {
    /// The file exists but is not one this build can rewrite without losing keys.
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .unreadable: "credentials.json could not be read, so it was left unchanged."
        }
    }
}

/// API keys in one JSON file only this user can open (folder 0700, file
/// 0600), never in `settings.json`. Replaces the Keychain: macOS ties a
/// Keychain item to the exact build of an app without an Apple Team ID, so
/// every rebuild asked for the login password again.
public struct CredentialStore: Sendable {
    public let url: URL

    /// One process, one file: keeps a read-modify-write from losing a key.
    private static let lock = NSLock()

    public init(url: URL) {
        self.url = url
    }

    struct File: Codable {
        var version = 1
        /// Set once the old Keychain items were copied in.
        var keychainImported = false
        var entries: [String: String] = [:]
    }

    /// Nil: no file yet. Throws when the file exists but cannot be used.
    private func load() throws -> File? {
        guard let data = try? Data(contentsOf: url) else {
            return FileManager.default.fileExists(atPath: url.path) ? nil : File()
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.version == 1 else { return nil }
        return file
    }

    public func read(_ account: String) -> String? {
        Self.lock.withLock { (try? load())??.entries[account] }
    }

    public var keychainImported: Bool {
        Self.lock.withLock { (try? load())??.keychainImported ?? false }
    }

    /// `nil` or empty deletes.
    public func write(_ value: String?, account: String) throws {
        try update { file in
            if let value, !value.isEmpty { file.entries[account] = value } else { file.entries[account] = nil }
        }
    }

    public func markKeychainImported() throws {
        try update { $0.keychainImported = true }
    }

    /// Copies each legacy key that is not here yet, marks the import done,
    /// and returns the accounts copied, which the caller then deletes from
    /// the old store.
    public func importLegacy(accounts: [String], read legacy: (String) -> String?) throws -> [String] {
        var moved: [String] = []
        try update { file in
            for account in accounts where file.entries[account] == nil {
                guard let value = legacy(account), !value.isEmpty else { continue }
                file.entries[account] = value
                moved.append(account)
            }
            file.keychainImported = true
        }
        return moved
    }

    private func update(_ change: (inout File) -> Void) throws {
        try Self.lock.withLock {
            guard var file = try load() else { throw CredentialStoreError.unreadable }
            change(&file)
            try save(file)
        }
    }

    private func save(_ file: File) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        // Written beside the file with owner-only access before it replaces
        // it, so the key is never readable by others, even for a moment.
        let temp = dir.appendingPathComponent(".credentials-\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            _ = try fm.replaceItemAt(url, withItemAt: temp)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
