import Foundation
import Testing
@testable import VoiceCore

struct FixLastTests {
    private func chain(_ original: String?, _ languages: [SpeechLanguage], presses: Int) -> [SpeechLanguage] {
        var c = RedoChain(original: original)
        return (0..<presses).map { _ in c.next(languages: languages) }
    }

    @Test func twoLanguageSwapUnchanged() {
        #expect(chain("en", [.en, .vi], presses: 3) == [.vi, .en, .vi])
        #expect(chain("vi", [.en, .vi], presses: 2) == [.en, .vi])
        #expect(chain("zh", [.en, .vi], presses: 1) == [.en])
    }

    @Test func threeLanguageOrder() {
        let all: [SpeechLanguage] = [.en, .vi, .es]
        #expect(chain("en", all, presses: 4) == [.vi, .es, .en, .vi])
        #expect(chain("vi", all, presses: 3) == [.en, .es, .vi])
        #expect(chain("es", all, presses: 3) == [.en, .vi, .es])
    }

    @Test func detectedOutsideTheSet() {
        let all: [SpeechLanguage] = [.en, .vi, .es]
        #expect(chain("pt", all, presses: 4) == [.en, .vi, .es, .en])
        #expect(chain(nil, [.en, .vi], presses: 3) == [.en, .vi, .en])
        #expect(chain("EN", [.en, .vi], presses: 1) == [.vi])
    }

    @Test func peekDoesNotAdvance() {
        let c = RedoChain(original: "en")
        #expect(c.peek(languages: [.en, .vi, .es]) == .vi)
        #expect(c.tried.isEmpty)
    }

    /// With only the detected language ticked there is nothing else to redo in.
    @Test func hasOtherLanguage() {
        #expect(RedoChain(original: "es").hasOtherLanguage(in: [.en, .vi, .es]))
        #expect(!RedoChain(original: "es").hasOtherLanguage(in: [.es]))
        #expect(!RedoChain(original: "ES").hasOtherLanguage(in: [.es]))
        #expect(RedoChain(original: "pt").hasOtherLanguage(in: [.es]))
        #expect(RedoChain(original: nil).hasOtherLanguage(in: [.es]))
    }

    @Test func replaceCountsGraphemes() {
        var guarder = ReplacementGuard()
        let now = Date()
        guarder.recordInsertion(LastInsertion(text: "Xin chào", processID: 1, at: now))
        #expect(guarder.decide(now: now, frontProcessID: 1, sameFocus: true) == .replace(backspaces: 8))
    }

    @Test func typingBlocks() {
        var guarder = makeGuard("hello")
        guarder.keyTyped()
        #expect(guarder.decide(now: Date(), frontProcessID: 1, sameFocus: true) == .copyOnly)
    }

    @Test func recordClearsTyping() {
        var guarder = makeGuard("hello")
        guarder.keyTyped()
        guarder.recordInsertion(LastInsertion(text: "again", processID: 1, at: Date()))
        #expect(guarder.decide(now: Date(), frontProcessID: 1, sameFocus: true) == .replace(backspaces: 5))
    }

    @Test func otherAppBlocks() {
        let now = Date()
        let guarder = makeGuard("hello", at: now)
        #expect(guarder.decide(now: now, frontProcessID: 2, sameFocus: true) == .copyOnly)
        #expect(guarder.decide(now: now, frontProcessID: 1, sameFocus: false) == .copyOnly)
    }

    @Test func oldPasteBlocks() {
        let now = Date()
        let guarder = makeGuard("hello", at: now)
        #expect(guarder.decide(now: now.addingTimeInterval(120), frontProcessID: 1, sameFocus: true) == .copyOnly)
        #expect(guarder.decide(now: now.addingTimeInterval(119), frontProcessID: 1, sameFocus: true) == .replace(backspaces: 5))
    }

    @Test func multiLineIsCopied() {
        let now = Date()
        var guarder = makeGuard("a\nb", at: now)
        #expect(guarder.decide(now: now, frontProcessID: 1, sameFocus: true) == .copyOnly)
        guarder.recordInsertion(LastInsertion(text: String(repeating: "x", count: 501), processID: 1, at: now))
        #expect(guarder.decide(now: now, frontProcessID: 1, sameFocus: true) == .copyOnly)
        guarder.recordInsertion(LastInsertion(text: String(repeating: "x", count: 500), processID: 1, at: now))
        #expect(guarder.decide(now: now, frontProcessID: 1, sameFocus: true) == .replace(backspaces: 500))
    }

    @Test func nothingRecorded() {
        #expect(ReplacementGuard().decide(now: Date(), frontProcessID: 1, sameFocus: true) == nil)
    }

    @Test func countsAsTyping() {
        let control: UInt64 = 0x0004_0000
        let option: UInt64 = 0x0008_0000
        #expect(FixLast.countsAsTyping(keyCode: 0, flags: 0, userData: 0, shortcutKeyCodes: [15, 37, 9]))
        #expect(!FixLast.countsAsTyping(keyCode: 15, flags: control | option, userData: 0, shortcutKeyCodes: [15, 37, 9]))
        #expect(FixLast.countsAsTyping(keyCode: 0, flags: control | option, userData: 0, shortcutKeyCodes: [15, 37, 9]))
        #expect(FixLast.countsAsTyping(keyCode: 6, flags: 0x0010_0000, userData: 0, shortcutKeyCodes: [15, 37, 9]))
        #expect(!FixLast.countsAsTyping(keyCode: 51, flags: 0, userData: FixLast.syntheticEventMarker, shortcutKeyCodes: []))
    }

    private func makeGuard(_ text: String, at: Date = Date()) -> ReplacementGuard {
        var guarder = ReplacementGuard()
        guarder.recordInsertion(LastInsertion(text: text, processID: 1, at: at))
        return guarder
    }
}

extension FixLastTests {
    @Test func selectBackAllowsNewlines() {
        #expect(makeGuard("a\nb").decideSelectBack(now: Date(), frontProcessID: 1, sameFocus: true) == .selectBack(characters: 3))
    }
    @Test func selectBackLimit() {
        #expect(makeGuard(String(repeating: "a", count: 2001)).decideSelectBack(now: Date(), frontProcessID: 1, sameFocus: true) == .copyOnly)
        #expect(makeGuard(String(repeating: "a", count: 2000)).decideSelectBack(now: Date(), frontProcessID: 1, sameFocus: true) == .selectBack(characters: 2000))
    }
    @Test func selectBackTypingBlocks() {
        var g = makeGuard("hello")
        g.keyTyped()
        #expect(g.decideSelectBack(now: Date(), frontProcessID: 1, sameFocus: true) == .copyOnly)
    }
}

extension FixLastTests {
    private func fidelityPrevious() -> DictationResult {
        var result = DictationResult(startedAt: Date(), appName: nil, bundleID: nil, style: .work, language: "en", raw: "we should not ship Friday", cleaned: "We should ship Friday.", finalText: "we should not ship Friday", outcome: .inserted, rawReason: .detailChanged, errorMessage: nil, timings: StageTimings())
        result.uncleanedText = result.raw
        result.fidelityIssues = [.init(kind: .negation, direction: .lost, token: "not")]
        return result
    }

    @Test func fallbackSwapsToCleaned() {
        let previous = fidelityPrevious()
        guard case .replace(let r, let kind, let title) = FixLast.pasteRawPlan(previous) else { Issue.record("Expected a cleaned replacement"); return }
        #expect(kind == .cleaned && title == "Replaced with cleaned text")
        #expect(r.finalText == "We should ship Friday." && r.rawReason == nil)
        #expect(r.cleaned == previous.cleaned && r.fidelityIssues == previous.fidelityIssues)
    }

    @Test func swappedBackKeepsCleaned() {
        var previous = fidelityPrevious()
        previous.finalText = previous.cleaned!
        previous.rawReason = nil
        guard case .replace(let r, let kind, let title) = FixLast.pasteRawPlan(previous) else { Issue.record("Expected a raw replacement"); return }
        #expect(kind == .raw && title == "Replaced with raw text")
        #expect(r.finalText == r.uncleanedText && r.rawReason == .detailChanged && r.cleaned != nil)
        #expect(r.fidelityIssues == previous.fidelityIssues)
    }

    @Test func ordinaryPasteRawUnchanged() {
        var previous = fidelityPrevious()
        previous.fidelityIssues = []
        previous.rawReason = nil
        previous.finalText = previous.cleaned!
        guard case .replace(let r, let kind, let title) = FixLast.pasteRawPlan(previous) else { Issue.record("Expected a raw replacement"); return }
        #expect(r.finalText == r.uncleanedText && r.cleaned == nil && r.rawReason == nil)
        #expect(kind == .raw && title == "Replaced with raw text")
    }

    @Test func alreadyRawWithoutCleaned() {
        var previous = fidelityPrevious()
        previous.cleaned = nil
        previous.fidelityIssues = []
        previous.rawReason = .cleanupOff
        #expect(FixLast.pasteRawPlan(previous) == .alreadyRaw)
    }

    @Test func terminalTrimOnSwap() {
        var previous = fidelityPrevious()
        previous.style = .terminal
        previous.raw = "git status 5"
        previous.uncleanedText = previous.raw
        previous.finalText = previous.raw
        previous.cleaned = "git status."
        previous.fidelityIssues = [.init(kind: .number, direction: .lost, token: "5")]
        guard case .replace(let r, _, _) = FixLast.pasteRawPlan(previous) else { Issue.record("Expected a cleaned replacement"); return }
        #expect(r.finalText == "git status" && r.cleaned == "git status.")
    }
}
