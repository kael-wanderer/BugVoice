import Foundation

public enum MeetingPCMJournal {
    public static let sampleRate = 16_000
    public static let channels = 1
    public static let bitDepth = 16

    /// Encodes headerless signed little-endian Int16 PCM at 16 kHz mono.
    public static func encode(_ clip: AudioClip) -> Data {
        var data = Data(capacity: clip.samples.count * 2)
        for sample in clip.samples {
            let clamped = max(-1, min(1, sample))
            let value = Int16(clamped < 0 ? clamped * 32_768 : clamped * 32_767)
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    public static func recover(_ data: Data, committedByteCount: Int) -> MeetingPCMRecovery {
        let boundedCount = min(data.count, max(0, committedByteCount))
        let usableCount = boundedCount - boundedCount % 2
        let committed = data.prefix(usableCount)
        return MeetingPCMRecovery(committedData: Data(committed), sampleCount: usableCount / 2)
    }
}

public struct MeetingPCMRecovery: Equatable, Sendable {
    public var committedData: Data
    public var sampleCount: Int

    public init(committedData: Data, sampleCount: Int) {
        self.committedData = committedData
        self.sampleCount = sampleCount
    }
}

public struct MeetingTrackCheckpoint: Codable, Equatable, Sendable {
    public var track: MeetingTrack
    public var committedByteCount: Int
    public var sampleCount: Int
    public var startOffset: TimeInterval
    public var endOffset: TimeInterval

    public init(
        track: MeetingTrack,
        committedByteCount: Int,
        sampleCount: Int,
        startOffset: TimeInterval,
        endOffset: TimeInterval
    ) {
        self.track = track
        self.committedByteCount = committedByteCount
        self.sampleCount = sampleCount
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

public struct MeetingCheckpoint: Codable, Equatable, Sendable {
    public var tracks: [MeetingTrackCheckpoint]

    public init(tracks: [MeetingTrackCheckpoint] = []) {
        self.tracks = tracks
    }

    public func track(_ track: MeetingTrack) -> MeetingTrackCheckpoint? {
        tracks.first { $0.track == track }
    }
}

public enum MeetingRetention {
    public static func expired(
        _ meeting: MeetingManifest,
        policy: MeetingRetentionPolicy,
        now: Date
    ) -> Bool {
        let retainedFrom = meeting.source == .upload ? (meeting.importedAt ?? meeting.endedAt) : meeting.endedAt
        guard meeting.state == .ready,
              let maxAge = policy.maxAge,
              let retainedFrom
        else { return false }
        return retainedFrom <= now.addingTimeInterval(-maxAge)
    }

    public static func pruneCandidates(
        _ meetings: [MeetingManifest],
        policy: MeetingRetentionPolicy,
        now: Date
    ) -> [MeetingID] {
        meetings.filter { expired($0, policy: policy, now: now) }.map(\.id)
    }
}
