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
}
