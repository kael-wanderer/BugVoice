import Foundation

public enum UploadMediaKind: String, Sendable {
    case audio = "Audio"
    case video = "Video"
}

public enum UploadJobState: String, Codable, Sendable {
    case queued
    case reading
    case transcribing
    case ready
    case failed
    case cancelled

    public var isTerminal: Bool {
        self == .ready || self == .failed || self == .cancelled
    }
}

public struct UploadJob: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var fileName: String
    public var kind: UploadMediaKind
    public var duration: TimeInterval
    public var byteSize: Int64
    public var meetingID: MeetingID?
    public var state: UploadJobState = .queued
    public var progress: Double?
    public var errorMessage: String?
    /// MCP client name when an agent added this file.
    public var addedBy: String?

    public init(
        id: UUID = UUID(), fileName: String, kind: UploadMediaKind, duration: TimeInterval, byteSize: Int64,
        addedBy: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.kind = kind
        self.duration = duration
        self.byteSize = byteSize
        self.addedBy = addedBy
    }
}

public enum UploadEvent: Sendable {
    case progress(Double?)
    case committed(MeetingID)
    case ready
    case failed(String)
    case cleanupFailed
    case cancelled
}

public struct UploadQueue: Sendable {
    public private(set) var jobs: [UploadJob] = []

    public init() {}

    public var active: UploadJob? {
        jobs.first { $0.state == .reading || $0.state == .transcribing }
    }

    public mutating func append(_ batch: [UploadJob]) {
        for job in batch where job.state == .queued && !jobs.contains(where: { $0.id == job.id }) {
            jobs.append(job)
        }
    }

    public mutating func attach(id: UUID, meetingID: MeetingID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].state.isTerminal else { return }
        jobs[index].meetingID = meetingID
    }

    public mutating func admit(meetingActive: Bool) -> UploadJob? {
        guard !meetingActive, active == nil,
              let index = jobs.firstIndex(where: { $0.state == .queued }) else { return nil }
        jobs[index].state = .reading
        jobs[index].progress = 0
        return jobs[index]
    }

    public mutating func apply(id: UUID, event: UploadEvent) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].state.isTerminal else { return }
        let state = jobs[index].state
        switch event {
        case .progress(let value) where state == .reading || state == .transcribing:
            jobs[index].progress = value.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
        case .committed(let meetingID) where state == .reading:
            jobs[index].meetingID = meetingID
            jobs[index].state = .transcribing
            jobs[index].progress = 0
        case .ready where state == .transcribing:
            jobs[index].state = .ready
            jobs[index].progress = 1
        case .failed(let message) where state == .reading || state == .transcribing:
            jobs[index].state = .failed
            jobs[index].errorMessage = message
        case .cleanupFailed:
            jobs[index].state = .failed
            jobs[index].errorMessage = "Could not remove the cancelled upload."
        case .cancelled:
            jobs[index].state = .cancelled
            jobs[index].progress = nil
        default:
            break
        }
    }

    public mutating func clearFinished() {
        jobs.removeAll { $0.state.isTerminal }
    }

    public mutating func reconcile(existing: Set<MeetingID>) {
        for index in jobs.indices where jobs[index].state.isTerminal {
            if let id = jobs[index].meetingID, !existing.contains(id) {
                jobs[index].meetingID = nil
            }
        }
    }
}
