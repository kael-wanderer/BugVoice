import Foundation

/// A dictation whose transcription failed, kept so it can be retried.
public struct FailedDictation: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var appName: String?
    public var bundleID: String?
    public var duration: TimeInterval
    /// Plain-English reason, never a provider's response body.
    public var reason: String

    public init(id: UUID, startedAt: Date, appName: String?, bundleID: String?, duration: TimeInterval, reason: String) {
        self.id = id; self.startedAt = startedAt; self.appName = appName
        self.bundleID = bundleID; self.duration = duration; self.reason = reason
    }
}

/// `Failed/<id>.wav` plus `Failed/<id>.json`, owner-only. The record is
/// written after the audio, so a record always has its audio. At most
/// `maxCount` recordings, each kept `maxAge`.
public struct FailedDictationStore: Sendable {
    public static let maxCount = 5
    public static let maxAge: TimeInterval = 24 * 60 * 60
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func audioURL(_ id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).wav") }
    public func recordURL(_ id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).json") }

    public func save(_ item: FailedDictation, audio: Data, now: Date) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        try write(audio, to: audioURL(item.id))
        do {
            try write(Self.encoder.encode(item), to: recordURL(item.id))
        } catch {
            try? fm.removeItem(at: audioURL(item.id))
            throw error
        }
        _ = load(now: now)
    }

    /// Replaces the record of a recording that is already kept.
    public func update(_ item: FailedDictation) throws {
        guard FileManager.default.fileExists(atPath: audioURL(item.id).path) else { return }
        try write(Self.encoder.encode(item), to: recordURL(item.id))
    }

    /// Kept recordings, newest first. Removes expired, surplus, damaged and
    /// orphaned files on the way.
    public func load(now: Date) -> [FailedDictation] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return [] }
        var items: [FailedDictation] = []
        var audioIDs = Set<UUID>()
        var recordIDs = Set<UUID>()
        for name in names {
            let url = folder.appendingPathComponent(name)
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            switch url.pathExtension {
            case "wav": audioIDs.insert(id)
            case "json": recordIDs.insert(id)
            default: continue
            }
        }
        for id in recordIDs {
            guard audioIDs.contains(id),
                  let data = try? Data(contentsOf: recordURL(id)),
                  let item = try? Self.decoder.decode(FailedDictation.self, from: data), item.id == id else {
                remove(id)
                continue
            }
            items.append(item)
        }
        for id in audioIDs.subtracting(recordIDs) { try? fm.removeItem(at: audioURL(id)) }
        items.sort { $0.startedAt > $1.startedAt }
        let kept = items.filter { now.timeIntervalSince($0.startedAt) <= Self.maxAge }.prefix(Self.maxCount)
        let keptIDs = Set(kept.map(\.id))
        for item in items where !keptIDs.contains(item.id) { remove(item.id) }
        return Array(kept)
    }

    public func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: recordURL(id))
        try? FileManager.default.removeItem(at: audioURL(id))
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Written beside the target with owner-only access, then swapped in.
    private func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let temp = folder.appendingPathComponent(".\(UUID().uuidString).tmp")
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

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
