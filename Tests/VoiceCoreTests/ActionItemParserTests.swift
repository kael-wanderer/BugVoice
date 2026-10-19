import Testing
@testable import VoiceCore

struct ActionItemParserTests {
    let id = MeetingID(rawValue: "m")
    @Test func bullets() {
        #expect(ActionItemParser.parse("- Send the build\n* Check crash rate\n• Book review\n1. Share report\n2) Read notes", meetingID: id).items.map(\.text) == ["Send the build", "Check crash rate", "Book review", "Share report", "Read notes"])
    }
    @Test func ownerShapes() {
        let cases = [("- Kael: send the build to QA", "send the build to QA", "Kael"), ("* **Tuấn** — check the crash rate", "check the crash rate", "Tuấn"), ("1. Share the report (owner: Linh)", "Share the report", "Linh"), ("- [ ] Book a design review — Minh Anh", "Book a design review", "Minh Anh"), ("- Ask (Kael)", "Ask", "Kael")]
        for (line, text, owner) in cases {
            let item = ActionItemParser.parse(line, meetingID: id).items.first
            #expect(item?.text == text)
            #expect(item?.owner == owner)
        }
    }
    @Test func colonPhraseNotOwner() {
        for line in ["Note: update the docs", "Follow up: pricing"] {
            let item = ActionItemParser.parse("- " + line, meetingID: id).items.first
            #expect(item?.owner == nil)
            #expect(item?.text == line)
        }
    }
    @Test func noOwner() { #expect(ActionItemParser.parse("- Read the streaming notes", meetingID: id).items.first?.owner == nil) }
    @Test func keyIgnoresMarkup() {
        let key = ActionItemParser.key("- Send X (Kael)")
        #expect(key == ActionItemParser.key("* [ ] Send  X (Kael)"))
        #expect(key == ActionItemParser.key("1. **Send** X (Kael)"))
        #expect(key != ActionItemParser.key("- Send Y (Kael)"))
    }
    @Test func otherLinesKept() {
        let parsed = ActionItemParser.parse("## Next steps\n- A\nNo action items\n\nThanks", meetingID: id)
        #expect(parsed.items.map(\.text) == ["A"])
        #expect(parsed.otherLines == ["## Next steps", "Thanks"])
    }
    @Test func nilAndEmpty() {
        for value: String? in [nil, ""] {
            let parsed = ActionItemParser.parse(value, meetingID: id)
            #expect(parsed.items.isEmpty && parsed.otherLines.isEmpty)
        }
    }
    @Test func duplicateKeysDropped() {
        let parsed = ActionItemParser.parse("- **Send** the build\n* Send the build\n- Other", meetingID: MeetingID(rawValue: "m"))
        #expect(parsed.items.map(\.text) == ["Send the build", "Other"])
    }
}
