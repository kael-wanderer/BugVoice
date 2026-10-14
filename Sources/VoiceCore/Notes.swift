import Foundation

public struct NoteID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        rawValue = UUID().uuidString.lowercased()
    }

    public var description: String { rawValue }
}

public struct NotesTextRange: Codable, Equatable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public func isValid(inUTF16Length totalLength: Int) -> Bool {
        guard location >= 0, length >= 0, totalLength >= 0 else { return false }
        let (end, overflow) = location.addingReportingOverflow(length)
        return !overflow && end <= totalLength
    }
}

public struct NotesListItem: Equatable, Sendable, Identifiable {
    public let id: NoteID
    public let title: String
    public let body: String
    public let modifiedAt: Date

    public init(id: NoteID, title: String, body: String, modifiedAt: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.modifiedAt = modifiedAt
    }
}

public struct NoteDocument: Equatable, Sendable, Identifiable {
    public let id: NoteID
    public var title: String
    public var body: String
    public var revision: UInt64
    public var modifiedAt: Date

    public init(id: NoteID = NoteID(), title: String, body: String, revision: UInt64 = 0, modifiedAt: Date = .now) {
        self.id = id
        self.title = title
        self.body = body
        self.revision = revision
        self.modifiedAt = modifiedAt
    }
}

public struct NoteFileVersion: Equatable, Sendable {
    public let modifiedAt: Date
    public let byteCount: Int64
    public let contentHash: UInt64

    public init(modifiedAt: Date, byteCount: Int64, contentHash: UInt64) {
        self.modifiedAt = modifiedAt
        self.byteCount = byteCount
        self.contentHash = contentHash
    }
}
