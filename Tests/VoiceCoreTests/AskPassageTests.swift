import Foundation
import Testing
@testable import VoiceCore

@Suite struct AskPassageTests {
    private func meeting(
        segments: [MeetingSegment] = [], state: MeetingState = .ready,
        summary: String? = nil, actionItems: String? = nil, notes: String = ""
    ) -> MeetingManifest {
        var m = MeetingManifest(
            id: MeetingID(rawValue: "m1"), startedAt: Date(timeIntervalSince1970: 1000),
            state: state, segments: segments)
        m.summary = summary
        m.actionItems = actionItems
        m.notes = notes
        return m
    }

    private func segs(_ n: Int, gap: Double = 5, translation: String? = nil) -> [MeetingSegment] {
        (0..<n).map {
            MeetingSegment(
                id: "s\($0)", start: Double($0) * gap, end: Double($0) * gap + 2,
                text: "line \($0)", track: .mic, translation: translation)
        }
    }

    @Test func foldsVietnameseAndSpanish() {
        #expect(AskText.fold("Quyết định") == "quyet dinh")
        #expect(AskText.fold("Opción") == "opcion")
        #expect(AskText.fold("Đi") == "di")
        #expect(AskText.tokens("Quyết-định, v2!") == ["quyet", "dinh", "v2"])
    }

    @Test func transcriptWindowsOverlapByOne() {
        let ps = AskPassageBuilder.passages(meeting: meeting(segments: segs(14)))
        let t = ps.filter { $0.part == .transcript }
        #expect(t.map { $0.lines.first?.id } == ["s0", "s5", "s10"])
        #expect(t.allSatisfy { $0.lines.count <= 6 })
        #expect(t.map(\.id) == ["meeting-m1#transcript#0", "meeting-m1#transcript#1", "meeting-m1#transcript#2"])
        #expect(t[0].lines[0].speaker == "You")
        #expect(t[0].date == Date(timeIntervalSince1970: 1000))
    }

    @Test func windowStopsAt60Seconds() {
        let ps = AskPassageBuilder.passages(meeting: meeting(segments: segs(6, gap: 30)))
        let t = ps.filter { $0.part == .transcript }
        #expect(t.count > 1)
        for p in t {
            let span = (p.lines.last!.end ?? 0) - (p.lines.first!.start ?? 0)
            #expect(p.lines.count == 1 || span <= 60)
        }
        #expect(t.flatMap(\.lines).map(\.id).contains("s5"))
    }

    @Test func translationInSearchText() {
        let ps = AskPassageBuilder.passages(meeting: meeting(segments: segs(1, translation: "two weeks")))
        #expect(ps[0].searchText == "line 0\ntwo weeks")
        #expect(ps[0].lines[0].translation == "two weeks")
    }

    @Test func emptyTranslationNotInSearchText() {
        let ps = AskPassageBuilder.passages(meeting: meeting(segments: segs(1, translation: "")))
        #expect(ps[0].searchText == "line 0")
    }

    @Test func notReadyMeetingHasNoPassages() {
        let m = meeting(segments: segs(3), state: .transcribing, summary: "x")
        #expect(AskPassageBuilder.passages(meeting: m).isEmpty)
    }

    @Test func summaryActionItemsAndMyNotesArePassages() {
        let m = meeting(summary: "Sum", actionItems: "- do it", notes: "mine")
        let parts = AskPassageBuilder.passages(meeting: m).map(\.part)
        #expect(parts == [.summary, .actionItems, .myNotes])
        let p = AskPassageBuilder.passages(meeting: m)[0]
        #expect(p.lines[0].id == "b0.0")
        #expect(p.lines[0].start == nil)
    }

    @Test func noteBlocksAtMost800() {
        let block = String(repeating: "word ", count: 30) // 150 chars
        let body = Array(repeating: block, count: 20).joined(separator: "\n\n")
        let note = NoteDocument(id: NoteID(rawValue: "n1"), title: "T", body: body, modifiedAt: Date(timeIntervalSince1970: 5))
        let ps = AskPassageBuilder.passages(note: note).filter { $0.part == .note }
        #expect(ps.count > 1)
        #expect(ps.allSatisfy { $0.searchText.count <= 800 })
        #expect(ps[0].id == "note-n1#note#0")
        #expect(ps[0].date == Date(timeIntervalSince1970: 5))
        let long = NoteDocument(id: NoteID(rawValue: "n2"), title: "", body: String(repeating: "a", count: 2000), modifiedAt: .now)
        #expect(AskPassageBuilder.passages(note: long).allSatisfy { $0.searchText.count <= 800 })
        let ids = ps.flatMap(\.lines).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func noteTitleIsOwnPassage() {
        let note = NoteDocument(id: NoteID(rawValue: "n1"), title: "Plan", body: "Body", modifiedAt: .now)
        let ps = AskPassageBuilder.passages(note: note)
        #expect(ps.map(\.part) == [.title, .note])
        #expect(ps[0].searchText == "Plan")
        #expect(AskPassageBuilder.passages(note: NoteDocument(title: "", body: "  \n", modifiedAt: .now)).isEmpty)
    }

    @Test func dictationPassagePerEntry() {
        func entry(_ text: String, app: String?) -> HistoryEntry {
            HistoryEntry(
                id: UUID(), startedAt: Date(timeIntervalSince1970: 9), appName: app, bundleID: nil,
                style: .other, language: "en", raw: text, cleaned: nil, text: text,
                outcome: "inserted", rawReason: nil, timings: StageTimings(recording: 1))
        }
        let ps = AskPassageBuilder.passages(dictations: [entry("hello", app: "Slack"), entry("", app: "X"), entry("bye", app: nil)])
        #expect(ps.count == 2)
        #expect(ps[0].part == .dictation)
        #expect(ps[0].lines[0].speaker == "Slack")
        #expect(ps[0].id.hasPrefix("dictations#dictation#"))
        #expect(ps[1].lines[0].speaker == nil)
        #expect(ps[0].date == Date(timeIntervalSince1970: 9))
    }

    @Test func hashChangesWithText() {
        let a = AskPassageBuilder.passages(meeting: meeting(segments: segs(1)))[0]
        var other = segs(1); other[0].text = "different"
        let b = AskPassageBuilder.passages(meeting: meeting(segments: other))[0]
        #expect(a.contentHash != b.contentHash)
        #expect(a.contentHash.count == 16)
        #expect(a.contentHash == AskPassageBuilder.passages(meeting: meeting(segments: segs(1)))[0].contentHash)
        // FNV-1a 64 of "a"
        #expect(AskPassageBuilder.fnv1a("a") == "af63dc4c8601ec8c")
    }
}
