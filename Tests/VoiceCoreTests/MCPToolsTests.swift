import Foundation
import Testing
@testable import VoiceCore

struct MCPToolsTests {
    @Test func listActionItemsDefaults() throws {
        #expect(try MCPTools.check("list_action_items", nil).get() == .listActionItems(status: .open, meeting: nil, limit: 50))
        #expect(try MCPTools.check("list_action_items", .object(["status": .string("done"), "meeting": .string("m"), "limit": .number(200)])).get() == .listActionItems(status: .done, meeting: "m", limit: 200))
    }
    @Test func listActionItemsRejectsBadStatus() {
        #expect(throws: MCPArgumentError.self) { try MCPTools.check("list_action_items", .object(["status": .string("later")])).get() }
    }
    @Test func listActionItemsLimitBounds() {
        for limit in [0, 201] {
            #expect(throws: MCPArgumentError.self) { try MCPTools.check("list_action_items", .object(["limit": .number(Double(limit))])).get() }
        }
    }
    @Test func actionItemFormat() throws {
        let date = ISO8601DateFormatter().date(from: "2026-10-19T12:00:00Z")!
        let item = ActionItemParser.parse("- Send X", meetingID: MeetingID(rawValue: "m")).items[0]
        let row = ActionItemRow(item: item, doneAt: nil)
        let json = MCPFormat.actionItem(row, meetingTitle: "Sync", meetingDate: date)
        #expect(json == .object(["meeting_id": .string("m"), "meeting_title": .string("Sync"), "meeting_date": .string("2026-10-19"), "text": .string("Send X"), "owner": .null, "done": .bool(false), "done_at": .null]))
        let finished = MCPFormat.actionItem(ActionItemRow(item: item, doneAt: date), meetingTitle: "Sync", meetingDate: date)
        #expect(finished["done"] == .bool(true))
        #expect(finished["done_at"] == .string(MCPFormat.iso(date)))
    }

    @Test func toolListHasAllThirteen() {
        let names = MCPTools.definitions["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
        #expect(names.count == 13)
        #expect(Set(names) == Set(MCPTool.allCases.map(\.rawValue)))
        for t in MCPTools.definitions["tools"]?.arrayValue ?? [] {
            #expect(t["inputSchema"]?["type"] == .string("object"))
            #expect((t["description"]?.stringValue ?? "").isEmpty == false)
        }
    }
    @Test func folderScopeParses() {
        #expect(MCPScopeArgument.parse(nil) == .all)
        #expect(MCPScopeArgument.parse("all") == .all)
        #expect(MCPScopeArgument.parse("folder:Lộ trình") == .folder("Lộ trình"))
        #expect(MCPScopeArgument.parse("meeting:abc") == .meeting("abc"))
        #expect(MCPScopeArgument.parse("note:n1") == .note("n1"))
        #expect(MCPScopeArgument.parse("unfiled") == .unfiled)
        #expect(MCPScopeArgument.parse("everything") == nil)
        #expect(MCPScopeArgument.parse("folder:") == nil)
    }
    @Test func checkAppliesDefaultsAndLimits() throws {
        #expect(try MCPTools.check("search", .object(["query": .string("bot")])).get() == .search(query: "bot", scope: .all, limit: 20))
        #expect(try MCPTools.check("list_notes", .object(["limit": .number(500)])).get() == .listNotes(folder: nil, tag: nil, text: nil, limit: 200))
        #expect(try MCPTools.check("list_notes", nil).get() == .listNotes(folder: nil, tag: nil, text: nil, limit: 50))
        #expect(try MCPTools.check("search", .object(["query": .string("bot"), "limit": .number(99)])).get() == .search(query: "bot", scope: .all, limit: 40))
        #expect(try MCPTools.check("get_meeting", .object(["id": .string("m")])).get()
            == .getMeeting(id: "m", parts: Set(MCPMeetingPart.allCases), fromLine: 1))
        #expect(try MCPTools.check("summarize_meeting", .object(["id": .string("m"), "kind": .string("action_items")])).get()
            == .summarizeMeeting(id: "m", kind: .actionItems, replace: false))
        #expect(try MCPTools.check("list_folders", nil).get() == .listFolders)
    }
    @Test func checkReadsAllArguments() throws {
        #expect(try MCPTools.check("edit_note", .object([
            "id": .string("n"), "body": .string("x"), "mode": .string("append"),
            "title": .string("T"), "folder": .string("Work"), "tags": .array([.string("a")]),
        ])).get() == .editNote(id: "n", body: "x", mode: .append, title: "T", folder: "Work", tags: ["a"]))
        #expect(try MCPTools.check("get_meeting", .object([
            "id": .string("m"), "parts": .array([.string("transcript")]), "from_line": .number(1501),
        ])).get() == .getMeeting(id: "m", parts: [.transcript], fromLine: 1501))
        #expect(try MCPTools.check("ask", .object(["question": .string("q"), "scope": .string("unfiled")])).get()
            == .ask(question: "q", scope: .unfiled))
        #expect(try MCPTools.check("create_note", .object(["title": .string("T"), "body": .string("b")])).get()
            == .createNote(title: "T", body: "b", folder: nil, tags: []))
        #expect(try MCPTools.check("get_job", .object(["job_id": .string("j")])).get() == .getJob(jobID: "j"))
    }
    @Test func listMeetingsDates() throws {
        guard case .listMeetings(_, _, let from, let to, _, _) = try MCPTools.check(
            "list_meetings", .object(["from": .string("2026-10-01"), "to": .string("2026-10-02")])).get()
        else { Issue.record("wrong call"); return }
        let calendar = Calendar.current
        #expect(from == calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        let endOfTo = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3))!.addingTimeInterval(-1)
        #expect(to == endOfTo)
        #expect(throws: MCPArgumentError.self) { try MCPTools.check("list_meetings", .object(["from": .string("last week")])).get() }
    }
    @Test func checkRejectsBadArguments() {
        #expect(throws: MCPArgumentError.self) { try MCPTools.check("search", .object([:])).get() }
        #expect(throws: MCPArgumentError.self) { try MCPTools.check("upload_audio", .object(["path": .string("rel/a.mp3")])).get() }
        #expect(throws: MCPArgumentError.self) { try MCPTools.check("upload_audio", .object(["path": .string("/tmp/a.txt")])).get() }
        #expect(throws: MCPArgumentError.self) { try MCPTools.check("edit_note", .object(["id": .string("n"), "body": .string("x"), "mode": .string("merge")])).get() }
        #expect(throws: MCPArgumentError.self) { try MCPTools.check("ask", .object(["question": .string("q"), "scope": .string("everything")])).get() }
        #expect(throws: MCPArgumentError.self) { try MCPTools.check("list_notes", .object(["limit": .string("ten")])).get() }
        #expect(throws: MCPArgumentError.self) { try MCPTools.check("list_notes", .string("x")).get() }
    }
    @Test func argumentErrorSentences() {
        #expect(MCPTools.check("search", .object([:])) == .failure(MCPArgumentError(message: "query must be a non-empty string.")))
        #expect(MCPTools.check("upload_audio", .object(["path": .string("/tmp/a.txt")]))
            == .failure(MCPArgumentError(message: "File type not supported: .txt. Supported: MP3, WAV, M4A, AIFF, CAF, MP4, MOV, M4V.")))
    }
    @Test func checkUnknownToolFails() {
        #expect(MCPTools.check("delete_note", nil) == .failure(MCPArgumentError(message: "Unknown tool: delete_note.")))
    }
    @Test func uploadExtensionCaseInsensitive() throws {
        #expect(try MCPTools.check("upload_audio", .object(["path": .string("/x/A.MP4")])).get()
            == .uploadAudio(path: "/x/A.MP4", title: nil, folder: nil, tags: []))
    }
}
