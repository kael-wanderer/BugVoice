import Foundation
import Testing
@testable import VoiceCore

struct StyleTests {
    @Test func legacyChatDecodesAsPersonal() throws {
        let styles = try JSONDecoder().decode([Style].self, from: Data(#"["chat","work","terminal"]"#.utf8))
        #expect(styles == [.personal, .work, .terminal])
    }

    @Test func unknownStyleStillFailsToDecode() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Style.self, from: Data(#""poem""#.utf8))
        }
    }

    @Test func encodesRawValue() throws {
        let data = try JSONEncoder().encode([Style.personal, .work])
        #expect(String(decoding: data, as: UTF8.self) == #"["personal","work"]"#)
    }

    @Test func titlesInPageOrder() {
        #expect(Style.allCases.map(\.title) == ["Personal messages", "Work messages", "Email", "Document", "Terminal", "Other"])
    }

    @Test func historyEntryWithChatStyleStillDecodes() throws {
        let entry = HistoryEntry(
            id: UUID(), startedAt: Date(timeIntervalSince1970: 0), appName: "Slack",
            bundleID: "com.tinyspeck.slackmacgap", style: .personal, language: "en",
            raw: "hi", cleaned: nil, text: "hi", outcome: "inserted", rawReason: nil,
            timings: StageTimings(recording: 1)
        )
        let json = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
            .replacingOccurrences(of: #""style":"personal""#, with: #""style":"chat""#)
        #expect(json.contains(#""style":"chat""#))
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: Data(json.utf8))
        #expect(decoded.style == .personal)
        #expect(decoded.text == "hi")
    }
}
