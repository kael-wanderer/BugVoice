import Foundation

public struct MeetingID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func new() -> MeetingID {
        MeetingID(rawValue: UUID().uuidString.lowercased())
    }

    public var description: String { rawValue }
}

public enum MeetingState: String, Codable, Sendable, CaseIterable {
    case recording
    case paused
    case interrupted
    case transcribing
    case ready
    case failed

    public var isRecoverable: Bool {
        switch self {
        case .recording, .paused, .interrupted, .transcribing: true
        case .ready, .failed: false
        }
    }
}

public enum MeetingTrack: String, Codable, Sendable, CaseIterable {
    case mic
    case system
}

public enum MeetingChunkState: String, Codable, Sendable {
    case pending
    case complete
    case empty
    case failed
}

public struct MeetingChunkRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var track: MeetingTrack
    public var offset: TimeInterval
    public var duration: TimeInterval
    public var requestedLanguage: SpeechLanguage
    public var detectedLanguage: String?
    public var state: MeetingChunkState
    public var errorMessage: String?

    public init(
        id: String,
        track: MeetingTrack,
        offset: TimeInterval,
        duration: TimeInterval,
        requestedLanguage: SpeechLanguage,
        detectedLanguage: String? = nil,
        state: MeetingChunkState,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.track = track
        self.offset = offset
        self.duration = duration
        self.requestedLanguage = requestedLanguage
        self.detectedLanguage = detectedLanguage
        self.state = state
        self.errorMessage = errorMessage
    }
}

public struct MeetingSegment: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var track: MeetingTrack

    public var speaker: String { track == .mic ? "You" : "Others" }

    public init(id: String = UUID().uuidString, start: TimeInterval, end: TimeInterval, text: String, track: MeetingTrack) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.track = track
    }
}

public struct MeetingMark: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var offset: TimeInterval
    public var label: String?

    public init(id: String = UUID().uuidString, offset: TimeInterval, label: String? = nil) {
        self.id = id
        self.offset = offset
        self.label = label
    }
}

public struct MeetingAudioFormat: Codable, Equatable, Sendable {
    public var sampleRate: Int
    public var channels: Int
    public var bitDepth: Int
    public var journalEncoding: String
    public var finalEncoding: String

    public init(
        sampleRate: Int = 16_000,
        channels: Int = 1,
        bitDepth: Int = 16,
        journalEncoding: String = "signed-int16-le-pcm",
        finalEncoding: String = "aac"
    ) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
        self.journalEncoding = journalEncoding
        self.finalEncoding = finalEncoding
    }
}

public struct MeetingManifest: Codable, Equatable, Sendable, Identifiable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: MeetingID
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var duration: TimeInterval
    public var state: MeetingState
    public var audioFormat: MeetingAudioFormat
    public var chunks: [MeetingChunkRecord]
    public var marks: [MeetingMark]
    public var segments: [MeetingSegment]
    public var transcriptProgress: Double?
    public var transcriptionError: String?
    public var summary: String?
    public var actionItems: String?

    public init(
        schemaVersion: Int = MeetingManifest.currentSchemaVersion,
        id: MeetingID = .new(),
        title: String = "Meeting",
        startedAt: Date,
        endedAt: Date? = nil,
        duration: TimeInterval = 0,
        state: MeetingState = .recording,
        audioFormat: MeetingAudioFormat = MeetingAudioFormat(),
        chunks: [MeetingChunkRecord] = [],
        marks: [MeetingMark] = [],
        segments: [MeetingSegment] = [],
        transcriptProgress: Double? = nil,
        transcriptionError: String? = nil,
        summary: String? = nil,
        actionItems: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.state = state
        self.audioFormat = audioFormat
        self.chunks = chunks
        self.marks = marks
        self.segments = segments
        self.transcriptProgress = transcriptProgress
        self.transcriptionError = transcriptionError
        self.summary = summary
        self.actionItems = actionItems
    }

    public static func new(startedAt: Date) -> MeetingManifest {
        MeetingManifest(startedAt: startedAt)
    }
}

public enum MeetingStoreError: Error, Equatable, Sendable {
    case missingManifest(MeetingID)
    case unsupportedSchemaVersion(Int)
    case manifestIDMismatch(expected: MeetingID, actual: MeetingID)
}

/// Persists each meeting manifest by atomic replacement inside its meeting folder.
public actor MeetingStore {
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func save(_ meeting: MeetingManifest) throws {
        let directory = root.appendingPathComponent(meeting.id.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(meeting)
        try data.write(to: directory.appendingPathComponent("meeting.json"), options: .atomic)
    }

    public func load(id: MeetingID) throws -> MeetingManifest {
        let url = root
            .appendingPathComponent(id.rawValue, isDirectory: true)
            .appendingPathComponent("meeting.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MeetingStoreError.missingManifest(id)
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let version = try decoder.decode(MeetingSchemaVersion.self, from: data).schemaVersion
        guard version == MeetingManifest.currentSchemaVersion else {
            throw MeetingStoreError.unsupportedSchemaVersion(version)
        }
        let meeting = try decoder.decode(MeetingManifest.self, from: data)
        guard meeting.id == id else {
            throw MeetingStoreError.manifestIDMismatch(expected: id, actual: meeting.id)
        }
        return meeting
    }
}

private struct MeetingSchemaVersion: Decodable {
    var schemaVersion: Int
}
