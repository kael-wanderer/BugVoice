import Foundation
import Testing
@testable import VoiceCore

struct MeetingTranslationTests {
    private func line(_ id: String, _ start: Double, _ text: String, translation: String? = nil) -> MeetingSegment {
        MeetingSegment(id: id, start: start, end: start + 4, text: text, track: .system, sourceChunkID: "c", translation: translation)
    }

    private func meeting(_ segments: [MeetingSegment], languages: [SpeechLanguage] = [.en, .es]) -> MeetingManifest {
        MeetingManifest(startedAt: Date(timeIntervalSince1970: 0), segments: segments, languages: languages)
    }

    @Test func pendingSkipsTranslatedAndEmptyLinesOldestFirst() {
        let lines = [
            line("b", 20, "¿Podemos mover el lanzamiento?"),
            line("a", 10, "Buenos días"),
            line("en", 30, "Sounds good"),
            line("done", 40, "Perfecto", translation: "Perfect"),
            line("none", 45, "OK", translation: ""),
            line("blank", 50, "  ")
        ]
        #expect(MeetingTranslation.pending(in: meeting(lines)).map(\.id) == ["a", "b", "en"])
    }

    @Test func pendingIsEmptyForEnglishOnlyMeetingsOrWhenHidden() {
        let lines = [line("a", 10, "Buenos días")]
        #expect(MeetingTranslation.pending(in: meeting(lines, languages: [.en])).isEmpty)
        #expect(MeetingTranslation.pending(in: meeting(lines, languages: [])).isEmpty)
        var hidden = meeting(lines)
        hidden.showEnglish = false
        #expect(MeetingTranslation.pending(in: hidden).isEmpty)
    }

    @Test func pendingTakesAtMostOneBatch() {
        let lines = (0..<20).map { line("l\($0)", Double($0), "hola \($0)") }
        let pending = MeetingTranslation.pending(in: meeting(lines))
        #expect(pending.count == 12)
        #expect(pending.first?.id == "l0")
        #expect(MeetingTranslation.batchSize == 12)
    }

    @Test func offeredOnlyWithANonEnglishLanguage() {
        #expect(MeetingTranslation.isOffered([.en, .vi]))
        #expect(MeetingTranslation.isOffered([.es]))
        #expect(!MeetingTranslation.isOffered([.en]))
        #expect(!MeetingTranslation.isOffered([]))
    }

    @Test func requestNumbersLinesAndFlattensNewlines() {
        let request = MeetingTranslation.request(
            lines: [line("a", 1, "Buenos\ndías"), line("b", 2, "Hola")],
            budget: MeetingTextBudget(contextTokens: 8_192, outputTokens: 4_096)
        )
        #expect(request.user == "1. Buenos días\n2. Hola")
        #expect(request.system == MeetingTranslation.systemPrompt)
        #expect(request.system.contains("into English"))
        #expect(request.maxTokens == 2_048)
        #expect(request.disableThinking)
        #expect(MeetingTranslation.request(lines: [], budget: MeetingTextBudget(contextTokens: 8_192, outputTokens: 512)).maxTokens == 512)
    }

    @Test func parseReadsNumberedLinesAndIgnoresTheRest() {
        let lines = [line("a", 1, "Buenos días"), line("b", 2, "¿Vamos?"), line("c", 3, "Hola")]
        let reply = """
        We need to translate these lines.
        2. ¿Vamos? is a question
        1. Good morning
          2) Shall we go?
        7. Out of range
        3.
        """
        #expect(MeetingTranslation.parse(reply, lines: lines) == ["a": "Good morning", "b": "Shall we go?"])
    }

    @Test func unchangedLineIsSavedAsEmpty() {
        let lines = [line("a", 1, "OK, sounds good."), line("b", 2, "Hola")]
        #expect(MeetingTranslation.parse("1. ok sounds good\n2. Hello", lines: lines) == ["a": "", "b": "Hello"])
    }

    @Test func carryOverMatchesTextTrackAndStart() {
        let live = [
            MeetingSegment(id: "l1", start: 10, end: 14, text: "Buenos días ", track: .system, translation: "Good morning"),
            MeetingSegment(id: "l2", start: 20, end: 24, text: "Hola", track: .mic, translation: "Hello"),
            MeetingSegment(id: "l3", start: 30, end: 34, text: "Adiós", track: .system, translation: "Goodbye")
        ]
        let final = [
            MeetingSegment(id: "f1", start: 10.6, end: 14, text: "Buenos días", track: .system),
            MeetingSegment(id: "f2", start: 20, end: 24, text: "Hola", track: .system),
            MeetingSegment(id: "f3", start: 32, end: 34, text: "Adiós", track: .system),
            MeetingSegment(id: "f4", start: 40, end: 44, text: "Gracias", track: .system)
        ]
        #expect(MeetingTranslation.carryOver(from: live, to: final).map(\.translation) == ["Good morning", nil, nil, nil])
    }
}
