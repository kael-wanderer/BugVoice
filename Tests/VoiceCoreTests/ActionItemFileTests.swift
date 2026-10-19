import Foundation
import Testing
@testable import VoiceCore

struct ActionItemFileTests {
    func item(_ meeting: String = "m", _ text: String = "Send X") -> ActionItem {
        ActionItemParser.parse("- " + text, meetingID: MeetingID(rawValue: meeting)).items[0]
    }
    @Test func setAndClear() {
        var file = ActionItemFile()
        let date = Date(timeIntervalSince1970: 1)
        file.setDone(item(), true, at: date)
        #expect(file.doneAt(item()) == date)
        file.setDone(item(), false, at: date)
        #expect(file.done.isEmpty)
    }
    @Test func sameTextOtherMeetingIndependent() {
        var file = ActionItemFile()
        file.setDone(item(), true, at: Date())
        #expect(file.doneAt(item("other")) == nil)
    }
    @Test func doneTwiceKeepsFirstDate() {
        var file = ActionItemFile()
        let date = Date(timeIntervalSince1970: 1)
        file.setDone(item(), true, at: date)
        file.setDone(item(), true, at: date.addingTimeInterval(10))
        #expect(file.done.count == 1)
        #expect(file.doneAt(item()) == date)
    }
    @Test func pruneRemovesDeletedMeetings() {
        var file = ActionItemFile()
        file.setDone(item(), true, at: Date())
        file.setDone(item("other"), true, at: Date())
        file.prune(keeping: [MeetingID(rawValue: "other")])
        #expect(file.done.map(\.meetingID) == [MeetingID(rawValue: "other")])
    }
    @Test func capDropsOldest() {
        var file = ActionItemFile()
        for n in 0...5_000 { file.setDone(item("m", "Item \(n)"), true, at: Date(timeIntervalSince1970: Double(n))) }
        #expect(file.done.count == 5_000)
        #expect(file.doneAt(item("m", "Item 0")) == nil)
        #expect(file.doneAt(item("m", "Item 5000")) != nil)
    }
    @Test func roundTripAndTolerantDecode() throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = Data(#"{"done":[{"meetingID":"m","key":"k","doneAt":"2026-10-19T00:00:00Z"}]}"#.utf8)
        let file = try decoder.decode(ActionItemFile.self, from: data)
        #expect(file.schemaVersion == 1)
        #expect(file.done.first?.meetingID == MeetingID(rawValue: "m"))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        #expect(try decoder.decode(ActionItemFile.self, from: encoder.encode(file)) == file)
        #expect(try decoder.decode(ActionItemFile.self, from: Data("{}".utf8)).done.isEmpty)
    }
    @Test func storeSurvivesCorruptFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("action-items.json")
        try Data("bad".utf8).write(to: url)
        #expect(await ActionItemStore(url: url).load() == ActionItemFile())
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("action-items.corrupt-") && $0.hasSuffix(".json") })
    }
    @Test func olderRevisionIsIgnored() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ActionItemStore(url: root.appendingPathComponent("action-items.json"))
        var file = ActionItemFile(); file.setDone(item(), true, at: Date(timeIntervalSince1970: 1))
        try await store.save(file, revision: 2)
        try await store.save(ActionItemFile(), revision: 1)
        #expect(await store.load() == file)
    }
}
