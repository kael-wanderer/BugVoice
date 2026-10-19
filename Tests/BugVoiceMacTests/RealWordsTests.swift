import Testing
@testable import BugVoiceMac

struct RealWordsTests {
    @Test @MainActor func cellIsReal() { #expect(RealWords.isRealWord("cell")) }
    @Test @MainActor func sellIsReal() { #expect(RealWords.isRealWord("sell")) }
    @Test @MainActor func nameIsNotReal() { #expect(!RealWords.isRealWord("Kael")) }
    @Test @MainActor func nonsenseIsNotReal() { #expect(!RealWords.isRealWord("Qzxv")) }
    @Test @MainActor func emptyIsNotReal() { #expect(!RealWords.isRealWord("")) }
}
