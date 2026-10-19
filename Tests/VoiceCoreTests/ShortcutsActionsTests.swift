import Foundation
import Testing
@testable import VoiceCore

struct ShortcutsActionsTests {
    @Test func errorCopy() {
        let pairs: [(ShortcutsError, String)] = [
            (.meetingAlreadyRecording, "A meeting is already recording."), (.noMeetingRecording, "No meeting is recording."),
            (.transcriptTimeout, "Still transcribing after 30 minutes. The transcript will finish in BugVoice › Meetings."),
            (.noFolder("Wrok"), "No folder named “Wrok”."), (.noMeeting("Standup"), "No meeting named “Standup”."),
            (.textTooLong, "Text too long — 8,000 characters at most"), (.emptyText, "No text to rewrite."),
            (.emptyInstruction, "No instruction given."), (.notReady, "BugVoice is still starting. Try again in a moment."),
            (.command(.noModel), "Command mode needs a text model — choose one in Settings › Models"),
            (.command(.modelFailed), "Command failed — model unavailable"), (.command(.outputTooLong), "The model's answer was too long"),
            (.other("Could not read the file."), "Could not read the file.")]
        for (error, message) in pairs { #expect(error.message == message) }
    }
    @Test func languageMapping() {
        #expect(ShortcutsLanguage.auto.languages == nil)
        #expect(ShortcutsLanguage.english.languages == [.en])
        #expect(ShortcutsLanguage.vietnamese.languages == [.vi])
    }
    @Test func folderResolution() {
        let folders = [LibraryFolder(id: FolderID(rawValue: "work"), name: "Work", createdAt: Date()), LibraryFolder(id: FolderID(rawValue: "personal"), name: "Cá nhân", createdAt: Date())]
        #expect(ShortcutsActions.folder("work", in: folders) == .success(folders[0].id))
        #expect(ShortcutsActions.folder(" ca nhan ", in: folders) == .success(folders[1].id))
        for blank: String? in [nil, "", "  "] { #expect(ShortcutsActions.folder(blank, in: folders) == .success(nil)) }
        #expect(ShortcutsActions.folder(" Wrok ", in: folders) == .failure(.noFolder("Wrok")))
    }
    @Test func rewriteLimits() {
        #expect(ShortcutsActions.checkRewrite(text: String(repeating: "a", count: 8000), instruction: "shorter") == nil)
        #expect(ShortcutsActions.checkRewrite(text: String(repeating: "a", count: 8001), instruction: "shorter") == .textTooLong)
        #expect(ShortcutsActions.checkRewrite(text: " \n", instruction: "shorter") == .emptyText)
        #expect(ShortcutsActions.checkRewrite(text: "hello", instruction: "  ") == .emptyInstruction)
    }
    @Test func limitBounds() {
        #expect(ShortcutsActions.clampLimit(nil) == 50)
        #expect(ShortcutsActions.clampLimit(0) == 1)
        #expect(ShortcutsActions.clampLimit(500) == 200)
        #expect(ShortcutsActions.clampLimit(20) == 20)
    }
    @Test func itemsOrderedFilteredAndFormatted() throws {
        let now = Date()
        let old = MeetingManifest(title: "Standup", startedAt: now.addingTimeInterval(-100), actionItems: "- Send the build to QA (Kael)\n- Update the docs")
        let new = MeetingManifest(title: "STANDUP", startedAt: now, actionItems: "- New task\n- Finished")
        let retro = MeetingManifest(title: "Retro", startedAt: now, actionItems: "- Other")
        var done = ActionItemFile()
        done.setDone(ActionItemParser.parse(new.actionItems, meetingID: new.id).items[1], true, at: now)
        let result = try ShortcutsActions.openActionItems(meetings: [old, new, retro], done: done, meeting: " standup ", limit: 2, now: now).get()
        #expect(result == ["New task — STANDUP", "Send the build to QA (Kael) — Standup"])
        #expect(try ShortcutsActions.openActionItems(meetings: [old], done: done, meeting: nil, limit: nil, now: now).get().last == "Update the docs — Standup")
        #expect(ShortcutsActions.openActionItems(meetings: [old], done: done, meeting: "Nope", limit: nil, now: now) == .failure(.noMeeting("Nope")))
        for item in ActionItemParser.parse(old.actionItems, meetingID: old.id).items { done.setDone(item, true, at: now) }
        #expect(ShortcutsActions.openActionItems(meetings: [old], done: done, meeting: "", limit: nil, now: now) == .success([]))
    }
}
