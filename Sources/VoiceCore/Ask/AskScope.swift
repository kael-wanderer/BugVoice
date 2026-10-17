import Foundation

public enum AskScope: Equatable, Sendable {
    case note(NoteID), folder(FolderID?), meeting(MeetingID), all

    public func includes(_ source: AskSource, folderID: FolderID?) -> Bool {
        switch self {
        case .all: return true
        case .note(let id): return source == .note(id)
        case .meeting(let id): return source == .meeting(id)
        case .folder(let id): return source != .dictations && id == folderID
        }
    }

    /// Longest question asked across items; This note keeps the note chat's own rules.
    public static let maxQuestionLength = 1_000

    public func questionIsTooLong(_ question: String) -> Bool {
        if case .note = self { return false }
        return question.trimmingCharacters(in: .whitespacesAndNewlines).count > Self.maxQuestionLength
    }
}
