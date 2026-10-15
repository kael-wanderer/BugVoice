import Foundation
import Testing
@testable import VoiceCore

func insightsCalendar(_ zone: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}

func insightsDate(_ key: String) -> Date {
    InsightsDayKey.date(for: key, calendar: insightsCalendar())!
}

func dictationResult(
    _ text: String,
    outcome: DictationOutcome = .inserted,
    app: String? = "Ghostty",
    style: Style = .terminal,
    raw: String? = nil,
    cleaned: String? = nil,
    recording: Double = 6
) -> DictationResult {
    DictationResult(
        startedAt: insightsDate("2026-10-15"), appName: app, bundleID: nil, style: style, language: "en",
        raw: raw ?? text, cleaned: cleaned, finalText: text, outcome: outcome, rawReason: nil,
        errorMessage: nil, timings: StageTimings(recording: recording)
    )
}

struct InsightsTests {
    @Test func dayKeyRoundTrip() {
        let calendar = insightsCalendar()
        let date = InsightsDayKey.date(for: "2026-10-15", calendar: calendar)!
        #expect(InsightsDayKey.key(for: date, calendar: calendar) == "2026-10-15")
        #expect(InsightsDayKey.date(for: "nope", calendar: calendar) == nil)
    }

    @Test func dayKeyUsesCalendarTimeZone() {
        let instant = ISO8601DateFormatter().date(from: "2026-10-14T20:00:00Z")!
        #expect(InsightsDayKey.key(for: instant, calendar: insightsCalendar("Asia/Ho_Chi_Minh")) == "2026-10-15")
        #expect(InsightsDayKey.key(for: instant, calendar: insightsCalendar("UTC")) == "2026-10-14")
    }

    @Test func insertedDictationCountsWordsAppStyle() throws {
        let delta = try #require(InsightsDelta.dictation(dictationResult("deploy the api now"), noteID: nil))
        #expect(delta.day.words == 4)
        #expect(delta.day.dictations == 1)
        #expect(delta.day.secondsSpoken == 6)
        #expect(delta.day.wordsByApp == ["Ghostty": 4])
        #expect(delta.day.wordsByStyle == ["terminal": 4])
        #expect(delta.day.noteWords == 0)
    }

    @Test func copiedNotConsumedCountsLikeInserted() throws {
        let delta = try #require(InsightsDelta.dictation(dictationResult("one two", outcome: .copiedNotConsumed), noteID: nil))
        #expect(delta.day.words == 2)
    }

    @Test func secureFieldAddsNothing() {
        #expect(InsightsDelta.dictation(dictationResult("hunter two", outcome: .copiedSecureField), noteID: nil) == nil)
    }

    @Test func failedOutcomesAddNothing() {
        for outcome in [DictationOutcome.discardedTooShort, .nothingHeard, .transcriptionFailed, .cancelled, .noteDeleted, .noteSaveFailed] {
            #expect(InsightsDelta.dictation(dictationResult("words here", outcome: outcome), noteID: nil) == nil)
        }
    }

    @Test func emptyTextAddsNothing() {
        #expect(InsightsDelta.dictation(dictationResult("   "), noteID: nil) == nil)
    }

    @Test func noteDictationCountsNoteWordsNotWords() throws {
        let id = NoteID(rawValue: "note-1")
        let delta = try #require(InsightsDelta.dictation(dictationResult("buy milk today", outcome: .insertedInNote), noteID: id))
        #expect(delta.day.words == 0)
        #expect(delta.day.noteWords == 3)
        #expect(delta.day.notes == 1)
        #expect(delta.day.noteIDs == ["note-1"])
        #expect(delta.day.dictations == 1)
        #expect(delta.day.wordsByApp.isEmpty)
    }

    @Test func missingAppNameIsUnknown() throws {
        let none = try #require(InsightsDelta.dictation(dictationResult("a b", app: nil), noteID: nil))
        let empty = try #require(InsightsDelta.dictation(dictationResult("a b", app: ""), noteID: nil))
        #expect(none.day.wordsByApp == ["Unknown": 2])
        #expect(empty.day.wordsByApp == ["Unknown": 2])
    }

    @Test func cleanupFixesFromRawVersusCleaned() throws {
        let result = dictationResult(
            "The meeting is on Thursday.",
            raw: "um so the meeting is on friday no I mean thursday",
            cleaned: "The meeting is on Thursday."
        )
        let delta = try #require(InsightsDelta.dictation(result, noteID: nil))
        #expect(delta.day.cleanupFixes == WordErrorRate.editDistance(
            reference: "um so the meeting is on friday no I mean thursday",
            hypothesis: "The meeting is on Thursday."))
        #expect(delta.day.cleanupFixes > 0)
    }

    @Test func punctuationOnlyCleanupIsZeroFixes() throws {
        let delta = try #require(InsightsDelta.dictation(
            dictationResult("Hello, world.", raw: "hello world", cleaned: "Hello, world."), noteID: nil))
        #expect(delta.day.cleanupFixes == 0)
    }

    @Test func noCleanedTextMeansZeroFixes() throws {
        let delta = try #require(InsightsDelta.dictation(dictationResult("plain words"), noteID: nil))
        #expect(delta.day.cleanupFixes == 0)
    }

    @Test func meetingDelta() throws {
        let delta = try #require(InsightsDelta.meeting(seconds: 1800))
        #expect(delta.day.meetings == 1)
        #expect(delta.day.meetingSeconds == 1800)
        #expect(InsightsDelta.meeting(seconds: 0) == nil)
    }

    @Test func historyEntryDelta() throws {
        let entry = HistoryEntry(
            id: UUID(), startedAt: insightsDate("2026-10-15"), appName: "Code", bundleID: nil, style: .other,
            language: "en", raw: "a b c", cleaned: nil, text: "a b c", outcome: "inserted", rawReason: nil,
            timings: StageTimings(recording: 3))
        let delta = try #require(InsightsDelta.history(entry))
        #expect(delta.day.words == 3)
        #expect(delta.day.wordsByApp == ["Code": 3])
        #expect(delta.day.wordsByStyle == ["other": 3])
    }

    @Test func mergeAddsAndCountsEachNoteOnce() {
        var day = InsightsDay()
        var a = InsightsDay(); a.words = 2; a.wordsByApp = ["Code": 2]; a.noteIDs = ["n1"]; a.notes = 1; a.noteWords = 5
        var b = InsightsDay(); b.words = 3; b.wordsByApp = ["Code": 1, "Notion": 2]; b.noteIDs = ["n1"]; b.notes = 1; b.noteWords = 4
        day.merge(a)
        day.merge(b)
        #expect(day.words == 5)
        #expect(day.wordsByApp == ["Code": 3, "Notion": 2])
        #expect(day.notes == 1)
        #expect(day.noteWords == 9)
    }

    @Test func activity() {
        var day = InsightsDay()
        #expect(!day.hasActivity)
        day.meetings = 1
        #expect(day.hasActivity)
    }

    @Test func fileAddFilesUnderDayKey() throws {
        var file = InsightsFile()
        let delta = try #require(InsightsDelta.dictation(dictationResult("a b"), noteID: nil))
        file.add(delta, at: insightsDate("2026-10-15"), calendar: insightsCalendar())
        file.add(delta, at: insightsDate("2026-10-15"), calendar: insightsCalendar())
        #expect(file.days["2026-10-15"]?.words == 4)
    }

    @Test func dayDecodesMissingKeysAsZero() throws {
        let day = try JSONDecoder().decode(InsightsDay.self, from: Data(#"{"words": 7}"#.utf8))
        #expect(day.words == 7)
        #expect(day.wordsByApp.isEmpty)
        let file = try JSONDecoder().decode(InsightsFile.self, from: Data(#"{"days": {}}"#.utf8))
        #expect(file.schemaVersion == 1)
        #expect(!file.backfilledFromHistory)
    }
}
