import Foundation

public struct BackupManifest: Codable, Equatable, Sendable {
    public static let currentFormat = 1

    public struct Counts: Codable, Equatable, Sendable {
        public var notes: Int
        public var meetings: Int
        public var dictations: Int
        public var dictionaryWords: Int
        public var folders: Int
        public var tags: Int

        public init(notes: Int, meetings: Int, dictations: Int, dictionaryWords: Int, folders: Int, tags: Int) {
            self.notes = notes
            self.meetings = meetings
            self.dictations = dictations
            self.dictionaryWords = dictionaryWords
            self.folders = folders
            self.tags = tags
        }
    }

    public struct File: Codable, Equatable, Sendable {
        public var path: String
        public var size: Int64

        public init(path: String, size: Int64) {
            self.path = path
            self.size = size
        }
    }

    public var format: Int
    public var createdAt: Date
    public var appVersion: String
    public var build: String
    public var counts: Counts
    public var files: [File]

    public init(format: Int, createdAt: Date, appVersion: String, build: String, counts: Counts, files: [File]) {
        self.format = format
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.build = build
        self.counts = counts
        self.files = files
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> BackupManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest: BackupManifest
        do {
            manifest = try decoder.decode(Self.self, from: data)
        } catch {
            throw BackupError.notABackup
        }
        guard manifest.format <= currentFormat else { throw BackupError.newerFormat }
        return manifest
    }

    public func problems(in dataDirectory: URL) -> [String] {
        files.compactMap { file in
            let url = dataDirectory.appendingPathComponent(file.path)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber,
                  size.int64Value == file.size else { return file.path }
            return nil
        }
    }

    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
}

public enum BackupError: Error, Equatable, LocalizedError {
    case notABackup
    case newerFormat
    case damaged(count: Int)
    case meetingActive
    case notEnoughSpace(bytes: Int64)
    case destinationInsideLibrary
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notABackup:
            "This file is not a BugVoice backup."
        case .newerFormat:
            "This backup is from a newer BugVoice format. Update BugVoice first."
        case .damaged(let count):
            "The backup is damaged: \(count) \(count == 1 ? "file is" : "files are") missing or the wrong size. Nothing was changed."
        case .meetingActive:
            "A meeting is recording. Stop the meeting first."
        case .notEnoughSpace(let bytes):
            "Not enough free space to restore. Free \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) and try again."
        case .destinationInsideLibrary:
            "Choose a folder outside the BugVoice data folder."
        case .failed(let message):
            message
        }
    }
}
