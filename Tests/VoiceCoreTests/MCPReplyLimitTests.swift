import Foundation
import Testing
@testable import VoiceCore

struct MCPReplyLimitTests {
    @Test func shortTextIsUnchanged() {
        #expect(MCPFormat.capped("a\nb", notice: "N", limit: 100) == "a\nb")
    }

    @Test func longTextIsCutAtALineAndEndsWithTheNotice() {
        let text = (1...50).map { "line \($0)" }.joined(separator: "\n")
        let out = MCPFormat.capped(text, notice: MCPFormat.noteTooLong, limit: 200)
        #expect(out.utf8.count <= 200)
        #expect(out.hasSuffix("\n" + MCPFormat.noteTooLong))
        let kept = out.dropLast(MCPFormat.noteTooLong.count + 1)
        #expect(text.hasPrefix(kept))
        #expect(text.contains(kept + "\n"))
    }

    @Test func cutNeverSplitsACharacter() {
        let text = String(repeating: "ộ", count: 100)
        let out = MCPFormat.capped(text, notice: "N", limit: 51)
        #expect(out.utf8.count <= 51)
        #expect(out.hasSuffix("\nN"))
        #expect(!out.contains("\u{FFFD}"))
    }

    @Test func noteNoticeText() {
        #expect(MCPFormat.noteTooLong == "More: this note is longer than an agent reply can hold. Open it in BugVoice.")
        #expect(MCPFormat.maxReplyBytes == 3_500_000)
    }

    @Test func rowsAreDroppedFromTheEndToFit() throws {
        let rows = (0..<100).map { JSONValue.object(["id": .string("item-\($0)"), "pad": .string(String(repeating: "x", count: 50))]) }
        let out = MCPFormat.jsonRows(rows, limit: 2_000)
        #expect(out.utf8.count <= 2_000)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(out.utf8))
        let kept = try #require(decoded.arrayValue)
        #expect(kept.count > 0 && kept.count < 100)
        #expect(kept == Array(rows.prefix(kept.count)))
        let all = MCPFormat.jsonRows(rows, limit: 1_000_000)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(all.utf8)).arrayValue?.count == 100)
    }

    @Test func fittedPicksTheNoticeByTool() throws {
        let long = (1...400).map { "line \($0)" }.joined(separator: "\n")
        let note = MCPFormat.fitted(long, for: .getNote(id: "n"), limit: 500)
        #expect(note.utf8.count <= 500 && note.hasSuffix(MCPFormat.noteTooLong))
        let meeting = MCPFormat.fitted(long, for: .getMeeting(id: "m", parts: [.transcript], fromLine: 1), limit: 500)
        #expect(meeting.utf8.count <= 500 && meeting.hasSuffix(MCPFormat.replyTooLong))
        let rows = (0..<50).map { JSONValue.object(["id": .string("n\($0)")]) }
        let list = MCPFormat.fitted(MCPFormat.json(.array(rows)), for: .listNotes(folder: nil, tag: nil, text: nil, limit: 50), limit: 300)
        #expect(list.utf8.count <= 300)
        let kept = try #require(try JSONDecoder().decode(JSONValue.self, from: Data(list.utf8)).arrayValue)
        #expect(!kept.isEmpty && kept == Array(rows.prefix(kept.count)))
        #expect(MCPFormat.fitted("short", for: .getNote(id: "n")) == "short")
    }
}
