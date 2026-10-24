import Foundation
import Testing
@testable import VoiceCore

struct FidelityCheckTests {

@Test func spokenNumberBecomesDigit() { #expect(FidelityCheck.issues(raw: "the timeout is fifteen seconds", cleaned: "The timeout is 15 seconds.").isEmpty) }
@Test func vietnameseNumberWord() { #expect(FidelityCheck.issues(raw: "họp lúc ba giờ chiều", cleaned: "Họp lúc 3 giờ chiều.").isEmpty) }
@Test func spanishCompound() { #expect(FidelityCheck.issues(raw: "son veinticinco euros", cleaned: "Son 25 euros.").isEmpty) }
@Test func digitSpelledOut() { #expect(FidelityCheck.issues(raw: "wait 5 minutes", cleaned: "Wait five minutes.").isEmpty) }
@Test func changedNumber() {
    #expect(FidelityCheck.issues(raw: "set the limit to 5", cleaned: "Set the limit to 50.") ==
        [.init(kind: .number, direction: .lost, token: "5"), .init(kind: .number, direction: .invented, token: "50")])
}
@Test func inventedNumber() { #expect(FidelityCheck.issues(raw: "around 20 users", cleaned: "Around 20 users, about 30%.") == [.init(kind: .number, direction: .invented, token: "30%")]) }
@Test func separatorsTimesPercent() {
    #expect(FidelityCheck.issues(raw: "1500 rows at 3 pm, 15 percent", cleaned: "1,500 rows at 3:00 PM, 15%.").isEmpty)
    #expect(FidelityCheck.issues(raw: "3 30", cleaned: "3:30").isEmpty)
}
@Test func decimalFromParts() { #expect(FidelityCheck.issues(raw: "version one point five", cleaned: "Version 1.5").isEmpty) }
@Test func listMarkersIgnored() { #expect(FidelityCheck.issues(raw: "first fix login second update docs", cleaned: "1. Fix login\n2. Update docs").isEmpty) }
@Test func ordinals() { #expect(FidelityCheck.issues(raw: "the first item", cleaned: "The 1st item.").isEmpty) }
@Test func placeholdersAreNotNumbers() { #expect(FidelityCheck.issues(raw: "send ⟦S1⟧ now", cleaned: "Send ⟦S1⟧ now.").isEmpty) }
@Test func selfCorrectionDropsEarlierNumber() {
    #expect(FidelityCheck.issues(raw: "meet at three, no I mean four", cleaned: "Meet at 4.").isEmpty)
    #expect(FidelityCheck.issues(raw: "gọi lúc 2 giờ à không 3 giờ", cleaned: "Gọi lúc 3 giờ.").isEmpty)
}

}
