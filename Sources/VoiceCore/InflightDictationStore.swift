import Foundation

public struct InflightDictation: Codable, Equatable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var appName: String?
    public var bundleID: String?
    public var duration: TimeInterval

    public init(id: UUID, startedAt: Date, appName: String?, bundleID: String?, duration: TimeInterval) {
        self.id = id; self.startedAt = startedAt; self.appName = appName
        self.bundleID = bundleID; self.duration = duration
    }
}

public struct InflightDictationStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func begin(_ item: InflightDictation) throws {
        let fm = FileManager.default
        let folder = url.deletingLastPathComponent()
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let temp = folder.appendingPathComponent(".\(UUID().uuidString).tmp")
        let data = try JSONEncoder().encode(item)
        guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        do { _ = try fm.replaceItemAt(url, withItemAt: temp) }
        catch { try? fm.removeItem(at: temp); throw error }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func replaceLastRecording(at target: URL, with data: Data?) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        if let data {
            let fm = FileManager.default
            let temporary = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
            guard fm.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            do { _ = try fm.replaceItemAt(target, withItemAt: temporary) }
            catch { try? fm.removeItem(at: temporary); throw error }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        } else if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
    }

    public func end() { try? FileManager.default.removeItem(at: url) }

    public func recover(into store: FailedDictationStore, lastRecording: URL, now: Date) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url), let item = try? JSONDecoder().decode(InflightDictation.self, from: data),
              now.timeIntervalSince(item.startedAt) <= FailedDictationStore.maxAge,
              let audio = try? Data(contentsOf: lastRecording), let clip = try? WAVDecoder.decode(audio),
              abs(clip.duration - item.duration) <= 0.1 else { end(); return }
        let failed = FailedDictation(id: item.id, startedAt: item.startedAt, appName: item.appName,
                                     bundleID: item.bundleID, duration: item.duration,
                                     reason: "BugVoice quit before this dictation finished.")
        try store.save(failed, audio: audio, now: now)
        end()
    }
}
