import Foundation

/// Turns folder names and scope arguments from agents into the app's own ids.
public enum MCPResolve {
    /// An exact id first, then a name compared without case or diacritics.
    public static func folder(_ nameOrID: String, in folders: [LibraryFolder]) -> Result<FolderID, MCPFailure> {
        let text = nameOrID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let byID = folders.first(where: { $0.id.rawValue == text }) { return .success(byID.id) }
        let key = AskText.fold(text)
        if let byName = folders.first(where: { AskText.fold($0.name) == key }) { return .success(byName.id) }
        let names = LibraryFolders.sorted(folders).map(\.name)
        let known = names.isEmpty ? "No folders yet." : "Folders: \(names.joined(separator: ", "))."
        return .failure(MCPFailure("No folder named \(text). \(known)"))
    }

    /// `.note` is read-only here: Ask never changes a note for an agent.
    public static func scope(_ s: MCPScopeArgument, folders: [LibraryFolder]) -> Result<AskScope, MCPFailure> {
        switch s {
        case .all: .success(.all)
        case .unfiled: .success(.folder(nil))
        case .folder(let name): folder(name, in: folders).map { .folder($0) }
        case .meeting(let id): .success(.meeting(MeetingID(rawValue: id)))
        case .note(let id): .success(.note(NoteID(rawValue: id)))
        }
    }
}
