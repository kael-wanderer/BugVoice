import Foundation
import Testing
@testable import VoiceCore

struct LivePreviewTests {
    @Test func policy() {
        let settings = AppSettings()
        func enabled(_ s: AppSettings = AppSettings(), secure: Bool = false, meeting: Bool = false, ready: Bool = true) -> Bool {
            LivePreviewPolicy.isEnabled(settings: s, secureField: secure, meetingRecording: meeting, modelReady: ready)
        }
        #expect(enabled(settings))
        var off = settings
        off.speech.livePreview = false
        #expect(!enabled(off))
        off = settings
        off.speech.engine = .openAICompatible
        #expect(!enabled(off))
        #expect(!enabled(secure: true))
        #expect(!enabled(meeting: true))
        #expect(!enabled(ready: false))
    }

    @Test func cadence() {
        let t = Date(timeIntervalSince1970: 1_000)
        #expect(!LivePreviewCadence.shouldStart(recorded: 0.9, running: false, lastReturnedAt: nil, now: t))
        #expect(LivePreviewCadence.shouldStart(recorded: 1, running: false, lastReturnedAt: nil, now: t))
        #expect(!LivePreviewCadence.shouldStart(recorded: 3, running: true, lastReturnedAt: nil, now: t))
        #expect(!LivePreviewCadence.shouldStart(recorded: 3, running: false, lastReturnedAt: t, now: t + 0.5))
        #expect(LivePreviewCadence.shouldStart(recorded: 3, running: false, lastReturnedAt: t, now: t + 0.6))
        #expect(LivePreviewCadence.window == 15)
    }

    @Test func displayCollapsesAndStrips() {
        #expect(LivePreviewText.display("  Hey [BLANK_AUDIO]  Linh\n") == "Hey Linh")
        #expect(LivePreviewText.display("hello subtitles by the amara org community team") == "hello team")
    }

    @Test func hallucinationShowsNothing() {
        for text in ["Thank you.", "", "[Music]", "[BLANK_AUDIO]", "Cảm ơn các bạn đã theo dõi"] {
            #expect(LivePreviewText.display(text) == nil)
        }
    }

    @Test func shortTextUnchanged() {
        let text = "Hey Linh, please check the login screen before lunch today."
        #expect(LivePreviewText.display(text) == text)
    }

    @Test func longTextKeepsEnd() throws {
        let text = String(repeating: "please check the upload queue before lunch ", count: 8) + "today"
        let display = try #require(LivePreviewText.display(text))
        #expect(display.hasPrefix("…"))
        #expect(display.count <= 141)
        #expect(display.hasSuffix("today"))
        #expect(text.split(separator: " ").contains(Substring(display.dropFirst()).split(separator: " ")[0]))
    }

    @Test func cutsAtWordBoundaryVietnamese() throws {
        let text = String(repeating: "sáng nay mình họp với team mobile cần sửa lỗi đăng nhập ", count: 6)
        let display = try #require(LivePreviewText.display(text))
        #expect(display.hasPrefix("…"))
        #expect(display.count <= 141)
        #expect(display.hasSuffix("nhập"))
        let words = Set(text.split(separator: " "))
        #expect(display.dropFirst().split(separator: " ").allSatisfy { words.contains($0) })
        let decomposed = text.decomposedStringWithCanonicalMapping
        #expect(LivePreviewText.display(decomposed) == display)
    }

    @Test func singleHugeWord() {
        let text = String(repeating: "ắ", count: 300)
        #expect(LivePreviewText.display(text) == "…" + String(text.suffix(140)))
    }
}

@Test func previewUsesSmallSeparateModel() {
    #expect(LivePreviewModel.name == "openai_whisper-base")
}
