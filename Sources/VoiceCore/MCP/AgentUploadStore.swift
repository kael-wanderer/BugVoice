import Foundation

/// One file an agent asked BugVoice to transcribe. Kept on disk so the job id
/// still answers `get_job` after BugVoice quits before the file was read.
public struct AgentUploadEntry: Codable, Equatable, Sendable {
    public let id: UUID
    public var path: String
    public var title: String?
    public var folderID: FolderID?
    public var tags: [String]
    public var client: String
    public var state: UploadJobState
    public var meetingID: MeetingID?
    public var error: String?
    public var updatedAt: Date

    public init(
        id: UUID, path: String, title: String?, folderID: FolderID?, tags: [String], client: String,
        state: UploadJobState = .queued, meetingID: MeetingID? = nil, error: String? = nil, updatedAt: Date
    ) {
        self.id = id
        self.path = path
        self.title = title
        self.folderID = folderID
        self.tags = tags
        self.client = client
        self.state = state
        self.meetingID = meetingID
        self.error = error
        self.updatedAt = updatedAt
    }

    /// The job as `get_job` reports it when the queue no longer lists it.
    public var job: UploadJob {
        var job = UploadJob(
            id: id, fileName: (path as NSString).lastPathComponent, kind: .audio, duration: 0, byteSize: 0,
            addedBy: client)
        job.state = state
        job.meetingID = meetingID
        job.errorMessage = error
        return job
    }
}

/// `MCP/agent-uploads.json`: owner-only file in an owner-only folder.
public struct AgentUploadStore: Sendable {
    /// Finished entries are kept this long so an agent can still read the outcome.
    public static let keepFinished: TimeInterval = 7 * 86_400

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Entries on disk; none when the file is missing or unreadable.
    public func load() -> [AgentUploadEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AgentUploadEntry].self, from: data)) ?? []
    }

    public func save(_ entries: [AgentUploadEntry]) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
        // Written beside the file with owner-only access, then swapped in.
        let temp = dir.appendingPathComponent(".agent-uploads-\(UUID().uuidString).tmp")
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

    /// Drops finished entries last changed more than `keepFinished` ago.
    public static func pruned(_ entries: [AgentUploadEntry], now: Date) -> [AgentUploadEntry] {
        entries.filter { !$0.state.isTerminal || now.timeIntervalSince($0.updatedAt) <= keepFinished }
    }

    /// At launch: entries still waiting to be read go back in the queue when
    /// their file is there, and fail when it is gone. Reading that was cut
    /// short starts over, since its partial meeting is discarded at launch.
    public static func recovered(
        _ entries: [AgentUploadEntry], now: Date, fileExists: (String) -> Bool
    ) -> (entries: [AgentUploadEntry], requeue: [AgentUploadEntry]) {
        var requeue: [AgentUploadEntry] = []
        let updated = pruned(entries, now: now).map { entry -> AgentUploadEntry in
            guard entry.state == .queued || entry.state == .reading else { return entry }
            var entry = entry
            if fileExists(entry.path) {
                if entry.state != .queued {
                    entry.state = .queued
                    entry.updatedAt = now
                }
                requeue.append(entry)
            } else {
                entry.state = .failed
                entry.error = "File not found: \(entry.path)."
                entry.updatedAt = now
            }
            return entry
        }
        return (updated, requeue)
    }

    /// Copies each queue job's state, meeting and error into its entry.
    /// Progress alone is not saved.
    public static func merged(_ entries: [AgentUploadEntry], jobs: [UploadJob], now: Date) -> [AgentUploadEntry] {
        let byID = Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return entries.map { entry in
            guard let job = byID[entry.id] else { return entry }
            var next = entry
            next.state = job.state
            next.meetingID = job.meetingID ?? entry.meetingID
            next.error = job.errorMessage
            guard next != entry else { return entry }
            next.updatedAt = now
            return next
        }
    }
}
