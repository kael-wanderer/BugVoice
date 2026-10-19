import Foundation
import Testing
@testable import VoiceCore

struct ActionItemBoardTests {
    let now = Date(timeIntervalSince1970: 1_792_411_200)
    func meeting(_ id: String = "m", title: String = "Weekly mobile sync", age: Double = 0, items: String? = "- Send X (Kael)\n- Check crash rate (Tuấn)\n- Read notes") -> MeetingManifest {
        MeetingManifest(id: MeetingID(rawValue: id), title: title, startedAt: now.addingTimeInterval(-age * 86400), actionItems: items)
    }
    func board(_ meetings: [MeetingManifest], done: ActionItemFile = ActionItemFile(), status: ActionItemStatus = .open, owner: ActionItemOwnerFilter = .anyone, range: ActionItemRange = .all, query: String = "", keep: Set<String> = []) -> ActionItemBoard {
        ActionItemBoard(meetings: meetings, done: done, status: status, owner: owner, range: range, query: query, now: now, keepVisible: keep)
    }
    @Test func groupsNewestFirst() {
        #expect(board([meeting("old", age: 3), meeting("new")]).groups.map(\.meetingID.rawValue) == ["new", "old"])
    }
    @Test func openDoneAllFilters() {
        let m = meeting(); var done = ActionItemFile()
        done.setDone(ActionItemParser.parse(m.actionItems, meetingID: m.id).items[0], true, at: now)
        #expect(board([m], done: done).groups[0].rows.count == 2)
        #expect(board([m], done: done, status: .done).groups[0].rows.count == 1)
        #expect(board([m], done: done, status: .all).groups[0].rows.count == 3)
    }
    @Test func ownerFilter() {
        #expect(board([meeting()], owner: .owner("Tuấn")).groups[0].rows.map(\.item.text) == ["Check crash rate"])
        #expect(board([meeting()], owner: .none).groups[0].rows.map(\.item.text) == ["Read notes"])
    }
    @Test func rangeFilter() {
        #expect(board([meeting(age: 10)], range: .week).groups.isEmpty)
        #expect(board([meeting(age: 10)], range: .month).groups.count == 1)
    }
    @Test func queryMatchesTitleAndText() {
        #expect(board([meeting(title: "Tuấn sync")], query: "tuan").groups.count == 1)
        #expect(board([meeting()], query: "CRASH").groups[0].rows.count == 1)
    }
    @Test func keepVisibleStaysInOpen() {
        let m = meeting(); let item = ActionItemParser.parse(m.actionItems, meetingID: m.id).items[0]
        var done = ActionItemFile(); done.setDone(item, true, at: now)
        #expect(board([m], done: done, keep: [item.id]).groups[0].rows.count == 3)
    }
    @Test func meetingsWithoutItemsSkipped() {
        #expect(board([meeting("a", items: nil), meeting("b", items: ""), meeting("c", items: "No action items")]).groups.isEmpty)
    }
    @Test func staleDoneNotShown() {
        var done = ActionItemFile(); done.setDone(ActionItemParser.parse("- Old", meetingID: meeting().id).items[0], true, at: now)
        let b = board([meeting()], done: done, status: .done)
        #expect(b.groups.isEmpty); #expect(b.doneTotal == 0); #expect(done.done.count == 1)
    }
    @Test func totalsIgnoreFilters() {
        let b = board([meeting()], status: .done, owner: .none, range: .week, query: "missing")
        #expect(b.openTotal == 3 && b.doneTotal == 0)
        #expect(b.owners == ["Kael", "Tuấn"])
    }
    @Test func copyMarkdownFormat() {
        let date = ISO8601DateFormatter().date(from: "2026-10-13T12:00:00Z")!
        let m = MeetingManifest(title: "Weekly mobile sync", startedAt: date, actionItems: "- Send the 2.4 build to QA before Wednesday (Kael)\n- Check the Android crash rate after rollout (Tuấn)\n- Book a design review for the new onboarding\n- Completed")
        let other = MeetingManifest(title: "Helpdesk SLA review", startedAt: date.addingTimeInterval(-3 * 86400), actionItems: "- Draft the escalation rule for P1 tickets (Kael)")
        var done = ActionItemFile(); done.setDone(ActionItemParser.parse(m.actionItems, meetingID: m.id).items[3], true, at: now)
        #expect(board([other, m], done: done, status: .all).copyMarkdown() == "## Weekly mobile sync — 13 Oct\n- [ ] Send the 2.4 build to QA before Wednesday (Kael)\n- [ ] Check the Android crash rate after rollout (Tuấn)\n- [ ] Book a design review for the new onboarding\n\n## Helpdesk SLA review — 10 Oct\n- [ ] Draft the escalation rule for P1 tickets (Kael)")
    }
}
