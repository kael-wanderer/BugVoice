import Testing
@testable import VoiceCore

struct CleanupTimeoutTests {
    @Test func addsATenthOfASecondPerWord() {
        #expect(CleanupTimeout.limit(base: 3, raw: "hello world") == 3.2)
        let fortyFive = Array(repeating: "word", count: 45).joined(separator: " ")
        #expect(abs(CleanupTimeout.limit(base: 3, raw: fortyFive) - 7.5) < 0.0001)
    }

    @Test func capsAtFifteenSeconds() {
        let long = Array(repeating: "word", count: 500).joined(separator: " ")
        #expect(CleanupTimeout.limit(base: 3, raw: long) == 15)
    }

    @Test func neverShortensALongerBase() {
        let long = Array(repeating: "word", count: 500).joined(separator: " ")
        #expect(CleanupTimeout.limit(base: 20, raw: long) == 20)
    }
}
