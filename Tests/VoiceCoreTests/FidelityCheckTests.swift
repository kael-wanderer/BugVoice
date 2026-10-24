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


@Test func droppedNot() { #expect(FidelityCheck.issues(raw: "we should not ship Friday", cleaned: "We should ship Friday.") == [.init(kind: .negation, direction: .lost, token: "not")]) }
@Test func contractionExpanded() { #expect(FidelityCheck.issues(raw: "don't merge it", cleaned: "Do not merge it.").isEmpty) }
@Test func vietnameseNegation() { #expect(FidelityCheck.issues(raw: "đừng xoá file này", cleaned: "Xoá file này.") == [.init(kind: .negation, direction: .lost, token: "đừng")]) }
@Test func markerNegationNotCounted() { #expect(FidelityCheck.issues(raw: "send it today no I mean tomorrow", cleaned: "Send it tomorrow.").isEmpty) }
@Test func addedNegationIgnored() { #expect(FidelityCheck.issues(raw: "that works", cleaned: "That does not work.").isEmpty) }
@Test func pathChanged() { #expect(FidelityCheck.issues(raw: "edit Sources/VoiceCore/History.swift", cleaned: "Edit Sources/History.swift.") == [.init(kind: .path, direction: .lost, token: "Sources/VoiceCore/History.swift")]) }
@Test func identifiersLost() {
    #expect(FidelityCheck.issues(raw: "rename user_profile to UserProfile", cleaned: "Rename user profile to user profile.").map(\.token) == ["user_profile", "UserProfile"])
}
@Test func projectWordJoinAllowed() { #expect(FidelityCheck.issues(raw: "check the app model class", cleaned: "Check the AppModel class.").isEmpty) }
@Test func flagsKept() { #expect(FidelityCheck.issues(raw: "run swift test --filter Foo", cleaned: "Run swift test --filter Foo").isEmpty) }
@Test func punctuationAroundTokens() { #expect(FidelityCheck.issues(raw: "open Info.plist and AppModel at 15", cleaned: "Open `Info.plist` and **AppModel** at **15**.").isEmpty) }
@Test func sentenceStartCapital() { #expect(FidelityCheck.issues(raw: "info.plist needs a bump", cleaned: "Info.plist needs a bump.").isEmpty) }
@Test func abbreviationsAreNotPaths() { #expect(FidelityCheck.issues(raw: "e.g. at 3 a.m.", cleaned: "For example, at 3 AM.").isEmpty) }
@Test func twoHundredWordsUnderFiveMilliseconds() {
    let raw = Array(repeating: "please do not change Sources/App.swift or AppModel before 15 users", count: 20).joined(separator: " ")
    _ = FidelityCheck.issues(raw: raw, cleaned: raw)
    let samples = (0..<20).map { _ in
        let start = ContinuousClock.now
        _ = FidelityCheck.issues(raw: raw, cleaned: raw)
        return ContinuousClock.now - start
    }.sorted()
    let median = (samples[9] + samples[10]) / 2
    #expect(median < .milliseconds(5))
}


@Test func correctionKeepsEarlierSentencesProtected() {
    #expect(FidelityCheck.issues(raw: "Keep 15. Use 20, sorry 30.", cleaned: "Use 30.") == [.init(kind: .number, direction: .lost, token: "15")])
}

@Test func correctionDropsEarlierDetailsInItsSentence() {
    #expect(FidelityCheck.issues(raw: "do not use OldName in old/file.swift, actually use NewName", cleaned: "Use NewName.").isEmpty)
}

@Test func identifierCaseInsideSentenceIsExact() {
    #expect(FidelityCheck.issues(raw: "use appModel", cleaned: "Use AppModel.") == [.init(kind: .identifier, direction: .lost, token: "appModel")])
}

@Test func negationWordBoundariesAndCounts() {
    #expect(FidelityCheck.issues(raw: "notable nobodyish sinus", cleaned: "Notable nobodyish sinus.").isEmpty)
    #expect(FidelityCheck.issues(raw: "not now and never later", cleaned: "Not now or later.") == [.init(kind: .negation, direction: .lost, token: "never")])
}

@Test(arguments: [
    ("ninety nine", "99"), ("noventa y nueve", "99"), ("chín mươi chín", "99"),
    ("one million", "1000000"), ("un millón", "1000000"), ("một triệu", "1000000"),
    ("hai trăm linh năm", "205"), ("cien", "100"), ("một trăm", "100")
])
func numberWordComposition(_ words: String, _ digits: String) {
    #expect(FidelityCheck.issues(raw: "value " + words, cleaned: "Value " + digits).isEmpty)
}


@Test func describePairsNumbers() {
    let issues: [FidelityIssue] = [.init(kind: .number, direction: .lost, token: "5"), .init(kind: .number, direction: .invented, token: "50")]
    #expect(FidelityCheck.describe(issues) == ["5 → 50"])
    #expect(FidelityCheck.hudTitle(issues, pastedRaw: true) == "Raw — cleanup changed a number")
}
@Test func hudTitles() {
    #expect(FidelityCheck.hudTitle([.init(kind: .negation, direction: .lost, token: "not")], pastedRaw: true) == "Raw — cleanup dropped “not”")
    #expect(FidelityCheck.hudTitle([.init(kind: .path, direction: .lost, token: "a/b")], pastedRaw: true) == "Raw — cleanup changed a path")
    #expect(FidelityCheck.hudTitle([.init(kind: .identifier, direction: .lost, token: "AppModel")], pastedRaw: false) == "Check — cleanup changed a name")
    #expect(FidelityCheck.hudTitle([.init(kind: .negation, direction: .lost, token: "not"), .init(kind: .path, direction: .lost, token: "a/b")], pastedRaw: true) == "Raw — cleanup changed 2 details")
    #expect(FidelityCheck.describe([.init(kind: .number, direction: .invented, token: "30%")]) == ["added 30%"])
    #expect(FidelityCheck.describe([.init(kind: .path, direction: .lost, token: "a/b")]) == ["lost `a/b`"])
}
@Test func hudDetails() {
    #expect(FidelityCheck.hudDetail(pastedRaw: true, pasteRawLetter: "R") == "⌃⌥R pastes the cleaned text")
    #expect(FidelityCheck.hudDetail(pastedRaw: false, pasteRawLetter: "X") == "⌃⌥X pastes raw")
}

@Test func describeMultipleNumbersAndUnpairedDetails() {
    let issues: [FidelityIssue] = [
        .init(kind: .number, direction: .lost, token: "5"),
        .init(kind: .number, direction: .lost, token: "10"),
        .init(kind: .number, direction: .invented, token: "50"),
        .init(kind: .number, direction: .invented, token: "100"),
        .init(kind: .number, direction: .invented, token: "30%"),
        .init(kind: .negation, direction: .lost, token: "đừng"),
        .init(kind: .identifier, direction: .lost, token: "AppModel")
    ]
    #expect(FidelityCheck.describe(issues) == ["5 → 50", "10 → 100", "added 30%", "dropped “đừng”", "lost `AppModel`"])
    #expect(FidelityCheck.hudTitle(issues, pastedRaw: false) == "Check — cleanup changed 5 details")
    #expect(FidelityCheck.describe([.init(kind: .number, direction: .lost, token: "15")]) == ["lost 15"])
    #expect(FidelityCheck.describe([]).isEmpty)
}

}
