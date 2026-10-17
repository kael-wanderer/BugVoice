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

public enum MeetingRecoveryAction: Sendable, Equatable {
    case recoverCapture
    case retryTranscription
}

public enum MeetingRecoveryPolicy {
    public static func action(for state: MeetingState) -> MeetingRecoveryAction? {
        switch state {
        case .recording, .paused, .interrupted: .recoverCapture
        case .transcribing: .retryTranscription
        case .ready, .failed: nil
        }
    }

    public static func action(for manifest: MeetingManifest) -> MeetingRecoveryAction? {
        if manifest.source == .upload {
            return manifest.state == .transcribing ? .retryTranscription : nil
        }
        return action(for: manifest.state)
    }
}

public enum MeetingSource: String, Codable, Sendable {
    case recording
    case upload
}

public enum MeetingTrack: String, Codable, Sendable, CaseIterable {
    case mic
    case system
    case file

    public static let recordingTracks: [MeetingTrack] = [.mic, .system]

    public var order: Int {
        switch self {
        case .mic: 0
        case .system: 1
        case .file: 2
        }
    }
}

public enum MeetingChunkState: String, Codable, Sendable {
    case pending
    case complete
    case empty
    case failed
}

public enum MeetingTranscriptionMode: String, Codable, Sendable {
    case timestamped
    case forcedVAD
}

public struct MeetingChunkAttempt: Codable, Equatable, Sendable {
    public var mode: MeetingTranscriptionMode
    public var requestedLanguage: SpeechLanguage
    public var detectedLanguage: String?
    public var state: MeetingChunkState
    public var text: String
    public var segments: [TranscriptSegment]
    public var errorMessage: String?

    public init(
        mode: MeetingTranscriptionMode,
        requestedLanguage: SpeechLanguage,
        detectedLanguage: String? = nil,
        state: MeetingChunkState,
        text: String = "",
        segments: [TranscriptSegment] = [],
        errorMessage: String? = nil
    ) {
        self.mode = mode
        self.requestedLanguage = requestedLanguage
        self.detectedLanguage = detectedLanguage
        self.state = state
        self.text = text
        self.segments = segments
        self.errorMessage = errorMessage
    }
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
    public var attempts: [MeetingChunkAttempt]
    public var chosenAttempt: Int?

    public init(
        id: String,
        track: MeetingTrack,
        offset: TimeInterval,
        duration: TimeInterval,
        requestedLanguage: SpeechLanguage,
        detectedLanguage: String? = nil,
        state: MeetingChunkState,
        errorMessage: String? = nil,
        attempts: [MeetingChunkAttempt] = [],
        chosenAttempt: Int? = nil
    ) {
        self.id = id
        self.track = track
        self.offset = offset
        self.duration = duration
        self.requestedLanguage = requestedLanguage
        self.detectedLanguage = detectedLanguage
        self.state = state
        self.errorMessage = errorMessage
        self.attempts = attempts
        self.chosenAttempt = chosenAttempt
    }
}

extension MeetingChunkRecord {
    private enum CodingKeys: String, CodingKey {
        case id, track, offset, duration, requestedLanguage, detectedLanguage, state, errorMessage
        case attempts, chosenAttempt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        track = try c.decode(MeetingTrack.self, forKey: .track)
        offset = try c.decode(TimeInterval.self, forKey: .offset)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        requestedLanguage = try c.decode(SpeechLanguage.self, forKey: .requestedLanguage)
        detectedLanguage = try c.decodeIfPresent(String.self, forKey: .detectedLanguage)
        state = try c.decode(MeetingChunkState.self, forKey: .state)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        attempts = (try? c.decode([MeetingChunkAttempt].self, forKey: .attempts)) ?? []
        chosenAttempt = try c.decodeIfPresent(Int.self, forKey: .chosenAttempt)
    }
}

public struct MeetingSegment: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var track: MeetingTrack
    public var sourceChunkID: String?
    /// English for a non-English line: nil until translated, empty when the line needs none.
    public var translation: String?

    public var speakerID: String?
    public var speakerName: String?

    public var speaker: String {
        if let speakerName { return speakerName }
        return switch track {
        case .mic: "You"
        case .system: "Others"
        case .file: "Speaker"
        }
    }

    public init(
        id: String = UUID().uuidString,
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        track: MeetingTrack,
        sourceChunkID: String? = nil,
        translation: String? = nil,
        speakerID: String? = nil,
        speakerName: String? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.track = track
        self.sourceChunkID = sourceChunkID
        self.speakerID = speakerID
        self.speakerName = speakerName
        self.translation = translation
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

public struct MeetingSpeaker: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String?
    public var colorIndex: Int
    public var centroid: [Float]?

    public init(id: String, name: String? = nil, colorIndex: Int, centroid: [Float]? = nil) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.centroid = centroid
    }
}

public enum SpeakerSplitState: Codable, Equatable, Sendable {
    case none, running, done, failed(String)

    private enum CodingKeys: String, CodingKey { case failed }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let status = try? value.decode(String.self) {
            switch status {
            case "none": self = .none
            case "running": self = .running
            case "done": self = .done
            default: throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unknown speaker split status")
            }
        } else {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            self = .failed(try fields.decode(String.self, forKey: .failed))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .none, .running, .done:
            var value = encoder.singleValueContainer()
            let status: String
            switch self { case .none: status = "none"; case .running: status = "running"; default: status = "done" }
            try value.encode(status)
        case .failed(let message):
            var fields = encoder.container(keyedBy: CodingKeys.self)
            try fields.encode(message, forKey: .failed)
        }
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
    public var source: MeetingSource
    public var sourceFileName: String?
    public var importedAt: Date?
    /// Folder from `library.json`; nil or an unknown id means Unfiled.
    public var folderID: FolderID?
    public var tags: [String]
    /// Existing tags the Meetings model proposed after the last summary. Shown until clicked or dismissed.
    public var suggestedTags: [String]
    /// Languages chosen for this meeting; empty for meetings saved before the choice existed.
    public var languages: [SpeechLanguage]
    /// The owner's own notes, Markdown.
    public var notes: String
    /// Running summary written during the meeting.
    public var liveSummary: String?
    public var liveSummaryUpdatedAt: Date?
    /// Meeting time (seconds) up to which transcript lines went into `liveSummary`.
    public var liveSummaryCutoff: TimeInterval
    /// Bundle ID of the app whose microphone use offered this recording.
    public var detectedApp: String?
    /// Show English under non-English transcript lines, and translate new ones.
    public var speakers: [MeetingSpeaker]
    public var speakerSplit: SpeakerSplitState
    public var speakerNamesAtSummary: [String: String]?
    public var showEnglish: Bool

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
        actionItems: String? = nil,
        source: MeetingSource = .recording,
        sourceFileName: String? = nil,
        importedAt: Date? = nil,
        folderID: FolderID? = nil,
        tags: [String] = [],
        suggestedTags: [String] = [],
        languages: [SpeechLanguage] = [],
        notes: String = "",
        liveSummary: String? = nil,
        liveSummaryUpdatedAt: Date? = nil,
        liveSummaryCutoff: TimeInterval = 0,
        detectedApp: String? = nil,
        showEnglish: Bool = true,
        speakers: [MeetingSpeaker] = [],
        speakerSplit: SpeakerSplitState = .none,
        speakerNamesAtSummary: [String: String]? = nil
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
        self.source = source
        self.sourceFileName = sourceFileName
        self.importedAt = importedAt
        self.folderID = folderID
        self.tags = tags
        self.suggestedTags = suggestedTags
        self.languages = languages
        self.notes = notes
        self.liveSummary = liveSummary
        self.liveSummaryUpdatedAt = liveSummaryUpdatedAt
        self.liveSummaryCutoff = liveSummaryCutoff
        self.detectedApp = detectedApp
        self.showEnglish = showEnglish
        self.speakers = speakers
        self.speakerSplit = speakerSplit
        self.speakerNamesAtSummary = speakerNamesAtSummary
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, title, startedAt, endedAt, duration, state
        case audioFormat, chunks, marks, segments, transcriptProgress
        case transcriptionError, summary, actionItems, source, sourceFileName, importedAt, folderID, tags, suggestedTags, languages
        case speakers, speakerSplit, speakerNamesAtSummary
        case notes, liveSummary, liveSummaryUpdatedAt, liveSummaryCutoff, detectedApp, showEnglish
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(MeetingID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        state = try c.decode(MeetingState.self, forKey: .state)
        audioFormat = try c.decode(MeetingAudioFormat.self, forKey: .audioFormat)
        chunks = try c.decode([MeetingChunkRecord].self, forKey: .chunks)
        marks = try c.decode([MeetingMark].self, forKey: .marks)
        segments = try c.decode([MeetingSegment].self, forKey: .segments)
        transcriptProgress = try c.decodeIfPresent(Double.self, forKey: .transcriptProgress)
        transcriptionError = try c.decodeIfPresent(String.self, forKey: .transcriptionError)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        actionItems = try c.decodeIfPresent(String.self, forKey: .actionItems)
        source = try c.decodeIfPresent(MeetingSource.self, forKey: .source) ?? .recording
        sourceFileName = try c.decodeIfPresent(String.self, forKey: .sourceFileName)
        importedAt = try c.decodeIfPresent(Date.self, forKey: .importedAt)
        folderID = try c.decodeIfPresent(FolderID.self, forKey: .folderID)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        suggestedTags = try c.decodeIfPresent([String].self, forKey: .suggestedTags) ?? []
        languages = try c.decodeIfPresent([SpeechLanguage].self, forKey: .languages) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        liveSummary = try c.decodeIfPresent(String.self, forKey: .liveSummary)
        liveSummaryUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .liveSummaryUpdatedAt)
        liveSummaryCutoff = try c.decodeIfPresent(TimeInterval.self, forKey: .liveSummaryCutoff) ?? 0
        detectedApp = try c.decodeIfPresent(String.self, forKey: .detectedApp)
        speakers = try c.decodeIfPresent([MeetingSpeaker].self, forKey: .speakers) ?? []
        speakerSplit = try c.decodeIfPresent(SpeakerSplitState.self, forKey: .speakerSplit) ?? .none
        speakerNamesAtSummary = try c.decodeIfPresent([String: String].self, forKey: .speakerNamesAtSummary)
        showEnglish = try c.decodeIfPresent(Bool.self, forKey: .showEnglish) ?? true
    }

    /// `names` are the speaker names the text was generated with; nil means the current ones.
    public mutating func setGeneratedText(_ text: String, kind: MeetingTextKind, names: [String: String]? = nil) {
        if kind == .summary {
            summary = text
            speakerNamesAtSummary = names ?? MeetingSpeakers.names(in: self)
        } else { actionItems = text }
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

public struct MeetingDayGroup: Sendable, Identifiable {
    public var day: Date
    public var label: String
    public var meetings: [MeetingManifest]

    public var id: Date { day }
}

public enum MeetingListProjection {
    public static func groups(
        meetings: [MeetingManifest],
        now: Date = Date(),
        calendar: Calendar = .current,
        query: String = ""
    ) -> [MeetingDayGroup] {
        let filtered = meetings.filter { matches($0, query: query) }
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.startedAt) }
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d, yyyy"

        return grouped.keys.sorted(by: >).compactMap { day in
            guard let items = grouped[day], !items.isEmpty else { return nil }
            let label: String
            if day == today { label = "Today" }
            else if day == yesterday { label = "Yesterday" }
            else { label = formatter.string(from: day) }
            return MeetingDayGroup(day: day, label: label, meetings: items.sorted { $0.startedAt > $1.startedAt })
        }
    }

    public static func matches(_ meeting: MeetingManifest, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        if LibraryTagSearch.matches(meeting.tags, query: needle) { return true }
        return meeting.title.localizedCaseInsensitiveContains(needle)
            || meeting.segments.contains {
                $0.speaker.localizedCaseInsensitiveContains(needle)
                    || $0.text.localizedCaseInsensitiveContains(needle)
                    || ($0.translation?.localizedCaseInsensitiveContains(needle) ?? false)
            }
    }
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
        let destination = directory.appendingPathComponent("meeting.json")
        let temporary = directory.appendingPathComponent(".meeting.json.\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: [])
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize()
            try handle.close()
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
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

    public func list() throws -> [MeetingManifest] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let children = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try children.compactMap { child in
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  FileManager.default.fileExists(atPath: child.appendingPathComponent("meeting.json").path)
            else { return nil }
            return try load(id: MeetingID(rawValue: child.lastPathComponent))
        }.sorted { $0.startedAt > $1.startedAt }
    }

    public func delete(id: MeetingID) throws {
        let rootURL = root.standardizedFileURL
        let directory = rootURL.appendingPathComponent(id.rawValue, isDirectory: true).standardizedFileURL
        guard directory.deletingLastPathComponent() == rootURL else { return }
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}

private struct MeetingSchemaVersion: Decodable {
    var schemaVersion: Int
}
