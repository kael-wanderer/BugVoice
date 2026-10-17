import Foundation
import Testing
@testable import VoiceCore

struct MCPResolveTests {
    private func folder(_ id: String, _ name: String) -> LibraryFolder {
        LibraryFolder(id: FolderID(rawValue: id), name: name, createdAt: Date(timeIntervalSince1970: 0))
    }

    @Test func folderByIDThenFoldedName() throws {
        let f = [folder("f1", "Lộ trình"), folder("f2", "Work")]
        #expect(try MCPResolve.folder("f2", in: f).get() == FolderID(rawValue: "f2"))
        #expect(try MCPResolve.folder("lo trinh", in: f).get() == FolderID(rawValue: "f1"))
        #expect(try MCPResolve.folder("Lộ Trình", in: f).get() == FolderID(rawValue: "f1"))
        #expect(try MCPResolve.folder("WORK", in: f).get() == FolderID(rawValue: "f2"))
        #expect(try MCPResolve.folder(" work ", in: f).get() == FolderID(rawValue: "f2"))
    }

    @Test func unknownFolderListsNames() {
        guard case .failure(let m) = MCPResolve.folder("Roadmap", in: [folder("f", "Work")]) else { Issue.record("found"); return }
        #expect(m.message == "No folder named Roadmap. Folders: Work.")
        let two = MCPResolve.folder("x", in: [folder("b", "Work"), folder("a", "Personal")])
        #expect(two == .failure(MCPFailure("No folder named x. Folders: Personal, Work.")))
        #expect(MCPResolve.folder("x", in: []) == .failure(MCPFailure("No folder named x. No folders yet.")))
    }

    @Test func scopeMapping() {
        let f = [folder("f1", "Work")]
        #expect(MCPResolve.scope(.all, folders: f) == .success(.all))
        #expect(MCPResolve.scope(.unfiled, folders: f) == .success(.folder(nil)))
        #expect(MCPResolve.scope(.folder("work"), folders: f) == .success(.folder(FolderID(rawValue: "f1"))))
        #expect(MCPResolve.scope(.meeting("m"), folders: f) == .success(.meeting(MeetingID(rawValue: "m"))))
        #expect(MCPResolve.scope(.note("n"), folders: f) == .success(.note(NoteID(rawValue: "n"))))
        #expect(MCPResolve.scope(.folder("nope"), folders: f) == .failure(MCPFailure("No folder named nope. Folders: Work.")))
    }
}
