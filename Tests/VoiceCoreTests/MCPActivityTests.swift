import Foundation
import Testing
@testable import VoiceCore

struct MCPActivityTests {
    @Test func activityKeepsNewestTwenty() {
        var a = MCPActivity()
        for i in 0..<25 { a.record(.init(time: Date(timeIntervalSince1970: Double(i)), client: "c", tool: "ask", error: nil)) }
        #expect(a.entries.count == 20)
        #expect(a.entries.first?.time == Date(timeIntervalSince1970: 24))
        #expect(a.entries.last?.time == Date(timeIntervalSince1970: 5))
    }
}
