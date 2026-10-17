import Testing
@testable import VoiceCore

struct AskScopeTests {
    @Test func folderScopeExcludesDictations() {
        #expect(!AskScope.folder(FolderID(rawValue: "work")).includes(.dictations, folderID: FolderID(rawValue: "work")))
    }
    @Test func unfiledScope() {
        let source = AskSource.note(NoteID(rawValue: "n"))
        #expect(AskScope.folder(nil).includes(source, folderID: nil))
        #expect(!AskScope.folder(nil).includes(source, folderID: FolderID(rawValue: "work")))
    }
    @Test func meetingScopeOneItem() {
        let id = MeetingID(rawValue: "m")
        #expect(AskScope.meeting(id).includes(.meeting(id), folderID: nil))
        #expect(!AskScope.meeting(id).includes(.meeting(MeetingID(rawValue: "other")), folderID: nil))
        #expect(!AskScope.meeting(id).includes(.note(NoteID(rawValue: "n")), folderID: nil))
    }
    @Test func allIncludesEverything() {
        for source in [AskSource.note(NoteID(rawValue: "n")), .meeting(MeetingID(rawValue: "m")), .dictations] {
            #expect(AskScope.all.includes(source, folderID: nil))
        }
        #expect(AskScope.note(NoteID(rawValue: "n")).includes(.note(NoteID(rawValue: "n")), folderID: nil))
        #expect(!AskScope.note(NoteID(rawValue: "n")).includes(.dictations, folderID: nil))
    }
}
