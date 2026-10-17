import Foundation
import Testing
@testable import VoiceCore

struct MCPFormatTests {
    private func meeting(segments: Int) -> MeetingManifest {
        MeetingManifest(
            title: "Standup", startedAt: Date(timeIntervalSince1970: 0), state: .ready,
            segments: (0..<segments).map { MeetingSegment(id: "s\($0)", start: Double($0), end: Double($0) + 1, text: "line \($0)", track: .mic) })
    }

    @Test func meetingTranscriptPagesAt1500() {
        let m = meeting(segments: 1600)
        let first = MCPFormat.meeting(m, folder: nil, parts: [.transcript], fromLine: 1)
        let lines = first.components(separatedBy: "\n")
        #expect(lines.contains("[0:00] You: line 0"))
        #expect(lines.filter { $0.hasPrefix("[") }.count == 1500)
        #expect(lines.last == "More: call get_meeting with from_line 1501.")
        let second = MCPFormat.meeting(m, folder: nil, parts: [.transcript], fromLine: 1501)
        let rest = second.components(separatedBy: "\n")
        #expect(rest.filter { $0.hasPrefix("[") }.count == 100)
        #expect(rest.contains("[25:00] You: line 1500"))
        #expect(!second.contains("More:"))
    }

    @Test func meetingLineFormat() {
        var m = meeting(segments: 0)
        m.segments = [
            MeetingSegment(id: "a", start: 83, end: 85, text: "hi", track: .file, translation: "chào", speakerName: "Luna"),
            MeetingSegment(id: "b", start: 3_725, end: 3_726, text: "bye", track: .file, translation: "", speakerName: "Luna"),
        ]
        let text = MCPFormat.meeting(m, folder: "Work", parts: [.transcript], fromLine: 1)
        let lines = text.components(separatedBy: "\n")
        let i = try? #require(lines.firstIndex(of: "[1:23] Luna: hi"))
        #expect(i.map { lines[$0 + 1] } == "    English: chào")
        #expect(lines.contains("[1:02:05] Luna: bye"))
        #expect(!lines.contains("    English: "))
        #expect(text.hasPrefix("# Standup\n"))
        #expect(text.contains("Folder: Work"))
        #expect(text.contains("People: Luna"))
    }

    @Test func meetingSectionsFollowParts() {
        var m = meeting(segments: 1)
        m.summary = "Sum."
        m.actionItems = "- Do"
        m.notes = "Mine"
        let all = MCPFormat.meeting(m, folder: nil, parts: Set(MCPMeetingPart.allCases), fromLine: 1)
        #expect(all.contains("## Summary\n\nSum."))
        #expect(all.contains("## Action items\n\n- Do"))
        #expect(all.contains("## My notes\n\nMine"))
        #expect(all.contains("## Transcript"))
        let some = MCPFormat.meeting(m, folder: nil, parts: [.summary], fromLine: 1)
        #expect(!some.contains("## Transcript") && !some.contains("## My notes"))
    }

    @Test func peopleInFirstAppearanceOrder() {
        var m = meeting(segments: 0)
        m.segments = [
            MeetingSegment(start: 5, end: 6, text: "x", track: .system),
            MeetingSegment(start: 1, end: 2, text: "y", track: .mic),
            MeetingSegment(start: 3, end: 4, text: "z", track: .system),
        ]
        #expect(MCPFormat.people(m) == ["You", "Others"])
    }

    @Test func noteMarksUnsaved() {
        #expect(MCPFormat.note(title: "T", folder: nil, tags: [], modified: .init(timeIntervalSince1970: 0), body: "b", unsaved: true).contains("Unsaved changes included."))
        let saved = MCPFormat.note(title: "T", folder: "Work", tags: ["a", "b"], modified: .init(timeIntervalSince1970: 0), body: "body", unsaved: false)
        #expect(saved.hasPrefix("# T\nFolder: Work · Tags: a, b · Modified: "))
        #expect(saved.hasSuffix("\n\nbody"))
        #expect(!saved.contains("Unsaved"))
    }

    @Test func isoDatesCarryOffset() {
        let s = MCPFormat.iso(Date(timeIntervalSince1970: 0))
        #expect(s.count >= 20)
        #expect(ISO8601DateFormatter().date(from: s) == Date(timeIntervalSince1970: 0))
    }

    @Test func askResultShapes() throws {
        let line = AskLine(id: "s1", start: 10, end: 12, speaker: "Luna", text: "We ship Friday.")
        let citation = AskCitation(id: "c1", part: .transcript, lines: [line])
        let info = AskItemInfo(title: "Standup", kind: .meeting, date: Date(timeIntervalSince1970: 0), people: ["Luna"])
        let card = AskCard(source: .meeting(MeetingID(rawValue: "m1")), info: info, citations: [citation])
        let answered = try MCPFormat.askResult(
            .answered(AskResult(answer: "Friday.", cards: [card]), wordSearchOnly: nil), meetings: 3, notes: 2, dictations: 1).get()
        #expect(answered["answer"] == .string("Friday."))
        let c0 = answered["cards"]?.arrayValue?.first
        #expect(c0?["item_id"] == .string("m1"))
        #expect(c0?["item_kind"] == .string("meeting"))
        #expect(c0?["people"] == .array([.string("Luna")]))
        let q = c0?["citations"]?.arrayValue?.first
        #expect(q?["quote"] == .string("We ship Friday."))
        #expect(q?["start"] == .number(10))
        #expect(q?["speaker"] == .string("Luna"))
        #expect(answered["searched"]?["meetings"] == .number(3))
        #expect(answered["word_search_only"] == nil)

        let nothing = try MCPFormat.askResult(.nothingFound(wordSearchOnly: .noModel), meetings: 0, notes: 0, dictations: 0).get()
        #expect(nothing == .object(["nothing_found": .bool(true), "word_search_only": .bool(true)]))

        #expect(MCPFormat.askResult(.failed(.tooSlow), meetings: 0, notes: 0, dictations: 0) == .failure(MCPFailure("Ask took too long. Try a smaller scope.")))
    }

    @Test func searchResultShape() {
        let p = AskPassage(
            source: .note(NoteID(rawValue: "n1")), part: .note, index: 0, date: Date(timeIntervalSince1970: 0),
            lines: [AskLine(id: "b0.0", text: "alpha")])
        let info: [AskSource: AskItemInfo] = [.note(NoteID(rawValue: "n1")): AskItemInfo(title: "N", kind: .note, date: .init(timeIntervalSince1970: 0))]
        let v = MCPFormat.searchResult(AskSearchResult(passages: [p], wordSearchOnly: .noModel), info: info)
        let first = v["passages"]?.arrayValue?.first
        #expect(first?["item_id"] == .string("n1"))
        #expect(first?["item_kind"] == .string("note"))
        #expect(first?["title"] == .string("N"))
        #expect(first?["text"] == .string("alpha"))
        #expect(first?["start"] == nil)
        #expect(v["word_search_only"] == .bool(true))
    }

    @Test func jsonIsPrettyAndSorted() {
        #expect(MCPFormat.json(.object(["b": .number(1), "a": .string("x")])) == "{\n  \"a\" : \"x\",\n  \"b\" : 1\n}")
    }

    @Test func secondsRoundToOneDecimal() {
        #expect(MCPFormat.seconds(38.239999771118164) == .number(38.2))
        #expect(MCPFormat.seconds(46.60000038146973) == .number(46.6))
    }
}
