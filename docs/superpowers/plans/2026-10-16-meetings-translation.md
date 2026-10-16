# Meetings v2 (5b) Live English Translation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a meeting's languages include one other than English, show each transcript line's English in a smaller grey line under it, live in the meeting window and saved with the meeting for the detail page and the Markdown export.

**Architecture:** Decisions live in `VoiceCore` (TDD): a `translation` field on each `MeetingSegment`, a `showEnglish` switch on the manifest, session setters, and `MeetingTranslation` (which lines need English, the numbered request, reading the reply, carrying English over to the final transcript at Stop). The app runs one request at a time through the Meetings model from a 1-second loop that starts with the meeting and keeps going after Stop, and shows the English in the meeting window's Transcript tab and on the detail page.

**Tech Stack:** Swift 6.4 (tools 6.0), SwiftUI/AppKit, Swift Testing (`import Testing`), macOS 15 floor.

**Spec:** `docs/superpowers/specs/2026-10-16-meetings-translation-design.md`. Mockup: `docs/design/proposal-meeting-translation.html` (open in a browser; light and dark). Read both before starting.

**How this plan was checked:** every code block below was compiled, tested and run on a copy of `main` at `b4d309c` before the plan was written: 610 VoiceCore and 84 BugVoiceMac tests passed, the app built with `Scripts/build-app.sh`, and it was tried by hand with a real meeting recording in English and Spanish against the owner's local Qwen 27B (English under Spanish lines about 5 s after they appeared, Show English off and on, Stop with English on the final lines, the detail page and its switch). Two findings from that run are in the code: Whisper labelled Spanish chunks `en`, so every line is sent and the model returns English lines unchanged; and with thinking on the model took 30 s per batch and wrote numbered reasoning before its answer, so requests turn thinking off and the last numbered line wins. The plan was then applied mechanically to a fresh copy of `main` and built and tested again. Copy the code exactly. If a step does not behave as written, stop and report; do not redesign.

## Global Constraints

- Swift package, tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only.
- Exactly one external dependency: WhisperKit pinned `exact: "1.1.1"`. Add none.
- TDD for everything in `VoiceCore`: failing test first, then code. `swift test` must pass before every commit.
- Build the app only with `Scripts/build-app.sh` (signs with `Bugler Local Dev`). Never ad hoc signing. Run it with `Scripts/run-dev-app.sh`, never a bare `open`.
- UI copy: plain English, no hedging words, no emoji. Use the exact strings in this plan: "Show English", "English needs a Meetings model.", "English:".
- Never send audio or text off this Mac except to the Meetings model the user configured. No new setting.
- Older meeting files must still load: `translation` decodes as nil and `showEnglish` as true when missing.
- Work in the worktree `../BugVoice-meetings-translation` on branch `feat/meetings-translation`. Do not merge, push or remove the worktree.
- Commit after each task, by path (`git add <paths>`), message style `feat(core): …`, `feat(app): …`, `docs: …`, with the trailer `Co-Authored-By: Codex <noreply@openai.com>`.
- Leave the untracked `.vscode/` alone. Search with `rg`.
- "Replace in" blocks are whole lines: find the old block exactly once in the file and replace it. "Replace the whole file" means write the file with exactly the content shown.

## Review Focus

1. Whisper reports `en` for a chunk of Spanish speech — its lines still get English, because no line is skipped by chunk language. Pinned by `pendingSkipsTranslatedAndEmptyLinesOldestFirst` (Task 2).
2. A reasoning model writes numbered lines in its reasoning before the answer — the answer's lines win. Pinned by `parseReadsNumberedLinesAndIgnoresTheRest` and `requestNumbersLinesAndFlattensNewlines` (thinking off) (Task 2).
3. The transcript merger trims repeated words from a line that already has English — the stale English is cleared so the line is translated again. Pinned by `trimmedLineLosesItsTranslationAndUntouchedLineKeepsIt` (Task 1).
4. Stop replaces every live line with the final pass — English carries over to final lines with the same text, track and start within 1 s. Pinned by `carryOverMatchesTextTrackAndStart` (Task 2) and `stopCarriesLiveEnglishToTheFinalLines` (Task 2).
5. Dictation during a meeting — translation never runs while dictation is busy or listening, nor while the live or final summary runs (`translateIfDue`, Task 4). Checked on the device by row 194.

## File map

| File | Task | Responsibility |
|---|---|---|
| `Sources/VoiceCore/Meeting.swift`, `MeetingSession.swift`, `MeetingTranscription.swift` | 1 | `translation` on lines, `showEnglish` on the manifest, session setters, merger clears stale English |
| `Sources/VoiceCore/MeetingTranslation.swift`, `MeetingSession.swift` | 2 | Which lines need English, request, reply, carry-over at Stop |
| `Sources/VoiceCore/MeetingExport.swift`, `Meeting.swift` | 3 | `  English:` lines in the Markdown export; meeting search matches English |
| `Sources/BugVoice/MeetingController+Translation.swift`, `MeetingController.swift`, `UI/MeetingWindow/*` | 4 | The translation loop; English and Show English in the meeting window |
| `Sources/BugVoice/AppModel.swift`, `UI/MeetingsPage.swift` | 5 | English and Show English on the meeting detail page |
| `docs/…` | 6 | Device checks 188–194, handoff, roadmap |

## Setup

```bash
cd /Users/cong.bui/Kael/19-AppBuild/BugVoice
git worktree add ../BugVoice-meetings-translation -b feat/meetings-translation main
cd ../BugVoice-meetings-translation
swift test
```
Expected: all tests pass before you start (595 VoiceCore, 84 BugVoiceMac).

---

### Task 1: English fields on meeting lines

**Files:**
- Modify: `Sources/VoiceCore/Meeting.swift`, `Sources/VoiceCore/MeetingSession.swift`, `Sources/VoiceCore/MeetingTranscription.swift`, `Tests/VoiceCoreTests/MeetingSessionTests.swift`, `Tests/VoiceCoreTests/MeetingTranscriptionTests.swift`

**Interfaces:**
- Produces: `MeetingSegment.translation: String?` (nil: not translated; empty: done, nothing to show; init parameter `translation: String? = nil`, decoded as optional); `MeetingManifest.showEnglish: Bool` (init parameter default `true`, decoded with `true` when missing); `MeetingSession.setTranslations(_ translations: [String: String]) async throws` (by segment id; unknown ids ignored) and `setShowEnglish(_:) async throws`, both allowed while recording, paused, transcribing or ready, `MeetingSessionError.invalidState` otherwise. `MeetingTranscriptMerger.merge` sets `translation = nil` on a line it trims.

- [ ] **Step 1: Write the failing tests**

**Replace in** `Tests/VoiceCoreTests/MeetingSessionTests.swift`:

````swift
        #expect(old.liveSummaryCutoff == 0)
        #expect(old.detectedApp == nil)
    }
````

**with:**

````swift
        #expect(old.liveSummaryCutoff == 0)
        #expect(old.detectedApp == nil)
    }

    @Test func translationsAndShowEnglishSaveWhileRecording() async throws {
        let rig = SessionRig()
        let session = rig.makeSession()
        try await session.start(languages: [.en, .es])
        try await session.persistInterim(interim(id: "system-0", track: .system, text: "hola a todos"))
        let id = try #require(await session.snapshot()?.segments.first?.id)
        try await session.setTranslations([id: "hello everyone", "gone": "ignored"])
        try await session.setShowEnglish(false)
        let saved = await rig.store.meetings.values.first
        #expect(saved?.segments.map(\.translation) == ["hello everyone"])
        #expect(saved?.showEnglish == false)
    }

    @Test func translationsAreRejectedAfterCancel() async throws {
        let rig = SessionRig()
        let session = rig.makeSession()
        try await session.start()
        try await session.cancel()
        await #expect(throws: MeetingSessionError.self) { try await session.setTranslations(["x": "y"]) }
        await #expect(throws: MeetingSessionError.self) { try await session.setShowEnglish(false) }
    }

    @Test func manifestWithoutTranslationFieldsDecodesWithDefaults() throws {
        var meeting = MeetingManifest(startedAt: Date(timeIntervalSince1970: 0))
        meeting.segments = [MeetingSegment(id: "a", start: 0, end: 1, text: "hola", track: .system, translation: "hello")]
        meeting.showEnglish = false
        let roundTrip = try JSONDecoder().decode(MeetingManifest.self, from: JSONEncoder().encode(meeting))
        #expect(roundTrip == meeting)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(meeting)) as! [String: Any]
        object.removeValue(forKey: "showEnglish")
        var segment = (object["segments"] as! [[String: Any]])[0]
        segment.removeValue(forKey: "translation")
        object["segments"] = [segment]
        let old = try JSONDecoder().decode(MeetingManifest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.showEnglish == true)
        #expect(old.segments.first?.translation == nil)
    }
````

**Replace in** `Tests/VoiceCoreTests/MeetingTranscriptionTests.swift`:

````swift
    }

    private func chunkResult(
        _ id: String,
````

**with:**

````swift
    }

    @Test func trimmedLineLosesItsTranslationAndUntouchedLineKeepsIt() {
        let first = chunkResult("mic-0", track: .mic, offset: 0, duration: 30, segments: [
            .init(start: 28, end: 29.5, text: "vamos el viernes", track: .mic, sourceChunkID: "mic-0", translation: "let's go Friday")
        ])
        let second = chunkResult("mic-1", track: .mic, offset: 29, duration: 30, segments: [
            .init(start: 29, end: 30, text: "el viernes después", track: .mic, sourceChunkID: "mic-1", translation: "on Friday after")
        ])

        let merged = MeetingTranscriptMerger.merge([first, second], overlapWindow: 2)

        #expect(merged.map(\.text) == ["vamos el viernes", "después"])
        #expect(merged.map(\.translation) == ["let's go Friday", nil])
    }

    private func chunkResult(
        _ id: String,
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter 'MeetingSessionTests|MeetingTranscriptionTests'`
Expected: build error, `extra argument 'translation' in call` or `value of type 'MeetingSession' has no member 'setTranslations'`.

- [ ] **Step 3: Write the implementation**

**Replace in** `Sources/VoiceCore/Meeting.swift`:

````swift
    public var track: MeetingTrack
    public var sourceChunkID: String?

    public var speaker: String {
````

**with:**

````swift
    public var track: MeetingTrack
    public var sourceChunkID: String?
    /// English for a non-English line: nil until translated, empty when the line needs none.
    public var translation: String?

    public var speaker: String {
````

**Replace in** `Sources/VoiceCore/Meeting.swift`:

````swift
        text: String,
        track: MeetingTrack,
        sourceChunkID: String? = nil
    ) {
        self.id = id
````

**with:**

````swift
        text: String,
        track: MeetingTrack,
        sourceChunkID: String? = nil,
        translation: String? = nil
    ) {
        self.id = id
````

**Replace in** `Sources/VoiceCore/Meeting.swift`:

````swift
        self.track = track
        self.sourceChunkID = sourceChunkID
    }
}
````

**with:**

````swift
        self.track = track
        self.sourceChunkID = sourceChunkID
        self.translation = translation
    }
}
````

**Replace in** `Sources/VoiceCore/Meeting.swift`:

````swift
    /// Bundle ID of the app whose microphone use offered this recording.
    public var detectedApp: String?

    public init(
````

**with:**

````swift
    /// Bundle ID of the app whose microphone use offered this recording.
    public var detectedApp: String?
    /// Show English under non-English transcript lines, and translate new ones.
    public var showEnglish: Bool

    public init(
````

**Replace in** `Sources/VoiceCore/Meeting.swift`:

````swift
        liveSummaryUpdatedAt: Date? = nil,
        liveSummaryCutoff: TimeInterval = 0,
        detectedApp: String? = nil
    ) {
        self.schemaVersion = schemaVersion
````

**with:**

````swift
        liveSummaryUpdatedAt: Date? = nil,
        liveSummaryCutoff: TimeInterval = 0,
        detectedApp: String? = nil,
        showEnglish: Bool = true
    ) {
        self.schemaVersion = schemaVersion
````

**Replace in** `Sources/VoiceCore/Meeting.swift`:

````swift
        self.liveSummaryCutoff = liveSummaryCutoff
        self.detectedApp = detectedApp
    }
````

**with:**

````swift
        self.liveSummaryCutoff = liveSummaryCutoff
        self.detectedApp = detectedApp
        self.showEnglish = showEnglish
    }
````

**Replace in** `Sources/VoiceCore/Meeting.swift`:

````swift
        case audioFormat, chunks, marks, segments, transcriptProgress
        case transcriptionError, summary, actionItems, source, sourceFileName, importedAt, folderID, tags, suggestedTags, languages
        case notes, liveSummary, liveSummaryUpdatedAt, liveSummaryCutoff, detectedApp
    }
````

**with:**

````swift
        case audioFormat, chunks, marks, segments, transcriptProgress
        case transcriptionError, summary, actionItems, source, sourceFileName, importedAt, folderID, tags, suggestedTags, languages
        case notes, liveSummary, liveSummaryUpdatedAt, liveSummaryCutoff, detectedApp, showEnglish
    }
````

**Replace in** `Sources/VoiceCore/Meeting.swift`:

````swift
        liveSummaryCutoff = try c.decodeIfPresent(TimeInterval.self, forKey: .liveSummaryCutoff) ?? 0
        detectedApp = try c.decodeIfPresent(String.self, forKey: .detectedApp)
    }
````

**with:**

````swift
        liveSummaryCutoff = try c.decodeIfPresent(TimeInterval.self, forKey: .liveSummaryCutoff) ?? 0
        detectedApp = try c.decodeIfPresent(String.self, forKey: .detectedApp)
        showEnglish = try c.decodeIfPresent(Bool.self, forKey: .showEnglish) ?? true
    }
````

**Replace in** `Sources/VoiceCore/MeetingSession.swift`:

````swift
        meeting.liveSummaryUpdatedAt = updatedAt
        meeting.liveSummaryCutoff = cutoff
        manifest = meeting
        try await store.save(meeting)
````

**with:**

````swift
        meeting.liveSummaryUpdatedAt = updatedAt
        meeting.liveSummaryCutoff = cutoff
        manifest = meeting
        try await store.save(meeting)
    }

    /// English for transcript lines by segment id; ids no longer in the transcript are ignored.
    public func setTranslations(_ translations: [String: String]) async throws {
        guard var meeting = manifest, Self.acceptsNotes(meeting.state) else { throw MeetingSessionError.invalidState }
        for index in meeting.segments.indices {
            if let english = translations[meeting.segments[index].id] { meeting.segments[index].translation = english }
        }
        manifest = meeting
        try await store.save(meeting)
    }

    public func setShowEnglish(_ show: Bool) async throws {
        guard var meeting = manifest, Self.acceptsNotes(meeting.state) else { throw MeetingSessionError.invalidState }
        meeting.showEnglish = show
        manifest = meeting
        try await store.save(meeting)
````

**Replace in** `Sources/VoiceCore/MeetingTranscription.swift`:

````swift
                let pieces = segment.text.split(whereSeparator: \.isWhitespace)
                segment.text = pieces.dropFirst(overlap).joined(separator: " ")
                if !segment.text.isEmpty { merged.append(segment) }
            }
````

**with:**

````swift
                let pieces = segment.text.split(whereSeparator: \.isWhitespace)
                segment.text = pieces.dropFirst(overlap).joined(separator: " ")
                // The English was for the longer text.
                segment.translation = nil
                if !segment.text.isEmpty { merged.append(segment) }
            }
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter 'MeetingSessionTests|MeetingTranscriptionTests'`
Expected: all pass.

Run: `swift test`
Expected: the whole suite passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceCore/Meeting.swift Sources/VoiceCore/MeetingSession.swift Sources/VoiceCore/MeetingTranscription.swift Tests/VoiceCoreTests/MeetingSessionTests.swift Tests/VoiceCoreTests/MeetingTranscriptionTests.swift
git commit -m "feat(core): English translation fields on meeting lines" -m "Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 2: Which lines need English, the request and the reply

**Files:**
- Create: `Sources/VoiceCore/MeetingTranslation.swift`, `Tests/VoiceCoreTests/MeetingTranslationTests.swift`
- Modify: `Sources/VoiceCore/MeetingSession.swift`, `Tests/VoiceCoreTests/MeetingSessionTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces: `MeetingTranslation.batchSize = 12`, `retryDelay: TimeInterval = 30`, `systemPrompt`, `isOffered(_ languages: [SpeechLanguage]) -> Bool`, `pending(in: MeetingManifest) -> [MeetingSegment]` (empty when Show English is off or no language other than English is chosen; lines without a translation and with text, oldest first, at most 12), `request(lines:budget:) -> CleanupRequest` (`N. text` lines, `maxTokens` at most 2 048, `disableThinking: true`), `parse(_ reply: String, lines: [MeetingSegment]) -> [String: String]` (segment id to English; unchanged lines map to `""`; the last repeat of a number wins), `carryOver(from live: [MeetingSegment], to final: [MeetingSegment]) -> [MeetingSegment]`. `MeetingSession.stop` carries live English over to the final lines.

- [ ] **Step 1: Write the failing tests**

**Replace in** `Tests/VoiceCoreTests/MeetingSessionTests.swift`:

````swift
        #expect(old.showEnglish == true)
        #expect(old.segments.first?.translation == nil)
    }
````

**with:**

````swift
        #expect(old.showEnglish == true)
        #expect(old.segments.first?.translation == nil)
    }

    @Test func stopCarriesLiveEnglishToTheFinalLines() async throws {
        let rig = SessionRig(finalChunks: [chunk("system-final-0", track: .system, segments: [
            MeetingSegment(start: 1.4, end: 2, text: "hola a todos", track: .system, sourceChunkID: "system-final-0"),
            MeetingSegment(start: 5, end: 6, text: "adiós", track: .system, sourceChunkID: "system-final-0")
        ])])
        let session = rig.makeSession()
        try await session.start(languages: [.en, .es])
        try await session.persistInterim(interim(id: "system-0", track: .system, text: "hola a todos"))
        let id = try #require(await session.snapshot()?.segments.first?.id)
        try await session.setTranslations([id: "hello everyone"])
        let stopped = try await session.stop()
        #expect(stopped.segments.map(\.translation) == ["hello everyone", nil])
    }
````

**Create** `Tests/VoiceCoreTests/MeetingTranslationTests.swift`:

````swift
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
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter 'MeetingTranslationTests|MeetingSessionTests'`
Expected: build error, `cannot find 'MeetingTranslation' in scope`.

- [ ] **Step 3: Write the implementation**

**Replace in** `Sources/VoiceCore/MeetingSession.swift`:

````swift
            meeting = manifest ?? meeting
            meeting.chunks = chunks.map(\.record)
            meeting.segments = MeetingTranscriptMerger.merge(chunks)
            meeting.transcriptProgress = 1
            meeting.transcriptionError = nil
````

**with:**

````swift
            meeting = manifest ?? meeting
            meeting.chunks = chunks.map(\.record)
            meeting.segments = MeetingTranslation.carryOver(from: meeting.segments, to: MeetingTranscriptMerger.merge(chunks))
            meeting.transcriptProgress = 1
            meeting.transcriptionError = nil
````

**Create** `Sources/VoiceCore/MeetingTranslation.swift`:

````swift
import Foundation

/// English under non-English meeting lines: which lines need it, what to send, how to read the reply.
public enum MeetingTranslation {
    /// Lines per request.
    public static let batchSize = 12
    /// Wait after a failed request before the next one.
    public static let retryDelay: TimeInterval = 30

    public static let systemPrompt = """
    You translate meeting transcript lines into English. Each input line starts with its number. \
    Return the same numbers, one line each, as `N. English text`. Keep names, product names and \
    technical terms as they are. When a line is already English, return it unchanged. Return only \
    the numbered lines.
    """

    /// Whether a meeting in these languages gets English lines.
    public static func isOffered(_ languages: [SpeechLanguage]) -> Bool {
        languages.contains { $0 != .en && $0 != .auto }
    }

    /// The lines that need English next, oldest first, at most `batchSize`.
    /// English lines are sent too: Whisper's chunk language is often "en" for
    /// Spanish speech, so the model decides and returns English lines unchanged.
    public static func pending(in meeting: MeetingManifest) -> [MeetingSegment] {
        guard meeting.showEnglish, isOffered(meeting.languages) else { return [] }
        let lines = meeting.segments.filter {
            $0.translation == nil && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return Array(lines.sorted { $0.start < $1.start }.prefix(batchSize))
    }

    public static func request(lines: [MeetingSegment], budget: MeetingTextBudget) -> CleanupRequest {
        let user = lines.enumerated().map { index, segment in
            "\(index + 1). " + segment.text.split(whereSeparator: \.isNewline).joined(separator: " ")
        }.joined(separator: "\n")
        // Thinking off: a reasoning model takes about five times as long and adds nothing here.
        return CleanupRequest(system: systemPrompt, user: user, maxTokens: min(2_048, budget.outputTokens), disableThinking: true)
    }

    /// English by segment id. Lines the reply left out are missing; a line
    /// returned unchanged maps to "" so it is not sent again. When a number
    /// repeats, the last one wins: a model that writes its reasoning into the
    /// reply puts the answer after it.
    public static func parse(_ reply: String, lines: [MeetingSegment]) -> [String: String] {
        var result: [String: String] = [:]
        for raw in reply.split(whereSeparator: \.isNewline) {
            let text = raw.trimmingCharacters(in: .whitespaces)
            let digits = text.prefix { $0.isASCII && $0.isNumber }
            guard let number = Int(digits), lines.indices.contains(number - 1) else { continue }
            let rest = text.dropFirst(digits.count)
            guard rest.first == "." || rest.first == ")" else { continue }
            let english = rest.dropFirst().trimmingCharacters(in: .whitespaces)
            let segment = lines[number - 1]
            guard !english.isEmpty else { continue }
            result[segment.id] = comparable(english) == comparable(segment.text) ? "" : english
        }
        return result
    }

    /// Keeps the English of live lines on final lines with the same text and
    /// track that start within 1 second of them.
    public static func carryOver(from live: [MeetingSegment], to final: [MeetingSegment]) -> [MeetingSegment] {
        final.map { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard segment.translation == nil,
                  let match = live.first(where: {
                      $0.translation != nil && $0.track == segment.track && abs($0.start - segment.start) <= 1
                          && $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == text
                  }) else { return segment }
            var carried = segment
            carried.translation = match.translation
            return carried
        }
    }

    private static func comparable(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) })
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter 'MeetingTranslationTests|MeetingSessionTests'`
Expected: all pass.

Run: `swift test`
Expected: the whole suite passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceCore/MeetingSession.swift Sources/VoiceCore/MeetingTranslation.swift Tests/VoiceCoreTests/MeetingSessionTests.swift Tests/VoiceCoreTests/MeetingTranslationTests.swift
git commit -m "feat(core): which meeting lines need English, the request and the reply" -m "Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 3: English in the Markdown export and meeting search

**Files:**
- Modify: `Sources/VoiceCore/Meeting.swift`, `Sources/VoiceCore/MeetingExport.swift`, `Tests/VoiceCoreTests/MeetingExportTests.swift`, `Tests/VoiceCoreTests/MeetingListProjectionTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces: `MeetingExporter.markdown(_:)` writes `  English: <text>` under each line with a non-empty translation, regardless of Show English; SubRip and `transcriptText` are unchanged. `MeetingListProjection.matches` also matches English.

- [ ] **Step 1: Write the failing tests**

**Replace in** `Tests/VoiceCoreTests/MeetingExportTests.swift`:

````swift
    }

    private func manifest(segments: [MeetingSegment]) -> MeetingManifest {
        MeetingManifest(
````

**with:**

````swift
    }

    @Test func markdownWritesEnglishUnderTranslatedLines() {
        var translated = segment(start: 5, end: 6, text: "Buenos\ndías", track: .system)
        translated.translation = "Good morning"
        var unchanged = segment(start: 7, end: 8, text: "OK", track: .system)
        unchanged.translation = ""
        var meeting = manifest(segments: [translated, unchanged, segment(start: 9, end: 10, text: "Hola", track: .system)])
        meeting.showEnglish = false
        #expect(MeetingExporter.markdown(meeting).hasSuffix(
            "## Transcript\n0:05 | Others | Buenos días\n  English: Good morning\n0:07 | Others | OK\n0:09 | Others | Hola"
        ))
        #expect(!MeetingExporter.srt(meeting).contains("English"))
        #expect(!MeetingExporter.transcriptText(meeting).contains("English"))
    }

    private func manifest(segments: [MeetingSegment]) -> MeetingManifest {
        MeetingManifest(
````

**Replace in** `Tests/VoiceCoreTests/MeetingListProjectionTests.swift`:

````swift
    }

    @Test func deletedMeetingIsAbsentFromStoreListingAndSearch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
````

**with:**

````swift
    }

    @Test func searchMatchesEnglishLines() {
        var item = meeting("one", "2026-10-14T08:00:00Z", title: "Reunión")
        item.segments = [MeetingSegment(start: 4, end: 5, text: "Mover el lanzamiento", track: .system, translation: "Move the launch")]
        #expect(MeetingListProjection.matches(item, query: "launch"))
    }

    @Test func deletedMeetingIsAbsentFromStoreListingAndSearch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter 'MeetingExportTests|MeetingListProjectionTests'`
Expected: both new tests fail with an expectation failure.

- [ ] **Step 3: Write the implementation**

**Replace in** `Sources/VoiceCore/Meeting.swift`:

````swift
        if LibraryTagSearch.matches(meeting.tags, query: needle) { return true }
        return meeting.title.localizedCaseInsensitiveContains(needle)
            || meeting.segments.contains { $0.text.localizedCaseInsensitiveContains(needle) }
    }
}
````

**with:**

````swift
        if LibraryTagSearch.matches(meeting.tags, query: needle) { return true }
        return meeting.title.localizedCaseInsensitiveContains(needle)
            || meeting.segments.contains {
                $0.text.localizedCaseInsensitiveContains(needle)
                    || ($0.translation?.localizedCaseInsensitiveContains(needle) ?? false)
            }
    }
}
````

**Replace in** `Sources/VoiceCore/MeetingExport.swift`:

````swift
        }
        lines.append("## Transcript")
        lines.append(contentsOf: ordered(meeting.segments).map {
            "\(displayTime($0.start)) | \($0.speaker) | \(flattenNewlines($0.text))"
        })
        return lines.joined(separator: "\n")
    }
````

**with:**

````swift
        }
        lines.append("## Transcript")
        for segment in ordered(meeting.segments) {
            lines.append("\(displayTime(segment.start)) | \(segment.speaker) | \(flattenNewlines(segment.text))")
            if let english = segment.translation, !english.isEmpty {
                lines.append("  English: \(flattenNewlines(english))")
            }
        }
        return lines.joined(separator: "\n")
    }
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter 'MeetingExportTests|MeetingListProjectionTests'`
Expected: all pass.

Run: `swift test`
Expected: the whole suite passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceCore/Meeting.swift Sources/VoiceCore/MeetingExport.swift Tests/VoiceCoreTests/MeetingExportTests.swift Tests/VoiceCoreTests/MeetingListProjectionTests.swift
git commit -m "feat(core): English lines in the Markdown export and meeting search" -m "Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 4: Live English in the meeting window

**Files:**
- Create: `Sources/BugVoice/MeetingController+Translation.swift`
- Modify: `Sources/BugVoice/MeetingController.swift`, `Sources/BugVoice/UI/MeetingWindow/MeetingTranscriptView.swift`, `Sources/BugVoice/UI/MeetingWindow/MeetingWindowView.swift`

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: in `MeetingController`: `showEnglish: Bool` (loaded from the meeting), `translationNeedsModel: Bool`, `translationTask`, `translationLoop`, `translationRetryAt`, `translationHeld` (true from Stop until the final summary is written), `showTranslations(from:)`. In `MeetingController+Translation.swift`: `offersEnglish`, `startTranslationLoop()` (called from `start(detected:)`, cancelled by `cancel()`), `translateIfDue()`, `setShowEnglish(_:) async`, `setShowEnglishInSession(id:show:) async throws -> Bool`. `MeetingTranscriptView` gains `offersEnglish`, `showEnglish`, `englishNeedsModel`, `onShowEnglish`.

- [ ] **Step 1: `MeetingController+Translation.swift`**

**Create** `Sources/BugVoice/MeetingController+Translation.swift`:

````swift
import Foundation
import VoiceCore

/// English under non-English transcript lines, through the Meetings model.
extension MeetingController {
    /// The Transcript tab offers Show English for this meeting.
    var offersEnglish: Bool {
        MeetingTranslation.isOffered(languages) || segments.contains { !($0.translation ?? "").isEmpty }
    }

    /// Ticks once a second from Start until a new meeting starts, so lines
    /// still without English after Stop are translated too.
    func startTranslationLoop() {
        translationLoop?.cancel()
        translationRetryAt = nil
        translationNeedsModel = false
        translationLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.translateIfDue()
            }
        }
    }

    /// Sends the next batch of lines that need English, one request at a time.
    func translateIfDue() {
        guard translationTask == nil, !translationHeld, let session else { return }
        // Dictation, the live summary and the final summary go first on the same model.
        guard model.dictation?.isBusy != true, !model.isListening else { return }
        guard summaryTask == nil, summaryState != .finalizing else { return }
        if let retry = translationRetryAt, Date() < retry { return }
        translationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.translationTask = nil }
            guard let meeting = await session.snapshot(),
                  [.recording, .paused, .ready].contains(meeting.state) else { return }
            let lines = MeetingTranslation.pending(in: meeting)
            guard !lines.isEmpty else { return }
            guard let textModel = await self.model.meetingTextModel() else {
                self.translationNeedsModel = true
                self.translationRetryAt = Date().addingTimeInterval(MeetingTranslation.retryDelay)
                return
            }
            self.translationNeedsModel = false
            let request = MeetingTranslation.request(lines: lines, budget: MeetingTextBudget(settings: self.model.settings.meetings))
            do {
                let english = MeetingTranslation.parse(try await textModel.clean(request), lines: lines)
                guard !english.isEmpty else {
                    self.translationRetryAt = Date().addingTimeInterval(MeetingTranslation.retryDelay)
                    return
                }
                try await session.setTranslations(english)
                self.translationRetryAt = nil
                if let saved = await session.snapshot() { self.showTranslations(from: saved) }
                if !self.isActive { await self.model.reloadMeetings() }
            } catch {
                self.translationRetryAt = Date().addingTimeInterval(MeetingTranslation.retryDelay)
            }
        }
    }

    /// Show English in the meeting window; saved on the meeting.
    func setShowEnglish(_ show: Bool) async {
        // A failed save leaves the switch as it was.
        guard let session, (try? await session.setShowEnglish(show)) != nil else { return }
        showEnglish = show
        translationRetryAt = nil
        if !isActive { await model.reloadMeetings() }
    }

    /// Show English from the detail page; false when the window's session does not own the meeting.
    func setShowEnglishInSession(id: MeetingID, show: Bool) async throws -> Bool {
        guard session != nil, await session?.snapshot()?.id == id else { return false }
        try await session?.setShowEnglish(show)
        if shownMeetingID == id { showEnglish = show }
        translationRetryAt = nil
        return true
    }
}
````

- [ ] **Step 2: `MeetingController.swift`**

**Replace in** `Sources/BugVoice/MeetingController.swift`:

````swift
    @ObservationIgnored var lastRefreshActiveTime: TimeInterval?
    @ObservationIgnored var notesAtLastRefresh = ""
    @ObservationIgnored var summaryTask: Task<Void, Never>?
    @ObservationIgnored var askTask: Task<Void, Never>?
    @ObservationIgnored private var notesSaveTask: Task<Void, Never>?
    @ObservationIgnored private var markFeedbackTask: Task<Void, Never>?
    @ObservationIgnored private(set) var session: MeetingSession?
    @ObservationIgnored private var capture: MeetingAudioCaptureCoordinator?
````

**with:**

````swift
    @ObservationIgnored var lastRefreshActiveTime: TimeInterval?
    @ObservationIgnored var notesAtLastRefresh = ""
    @ObservationIgnored var summaryTask: Task<Void, Never>?
    @ObservationIgnored var askTask: Task<Void, Never>?
    /// Show English for the shown meeting; written by `MeetingController+Translation`.
    var showEnglish = true
    /// The last translation try found no Meetings model.
    var translationNeedsModel = false
    @ObservationIgnored var translationTask: Task<Void, Never>?
    @ObservationIgnored var translationLoop: Task<Void, Never>?
    /// No translation before this time after a failed request.
    @ObservationIgnored var translationRetryAt: Date?
    /// True from Stop until the final summary is written.
    @ObservationIgnored var translationHeld = false
    @ObservationIgnored private var notesSaveTask: Task<Void, Never>?
    @ObservationIgnored private var markFeedbackTask: Task<Void, Never>?
    @ObservationIgnored private(set) var session: MeetingSession?
    @ObservationIgnored private var capture: MeetingAudioCaptureCoordinator?
````

**Replace in** `Sources/BugVoice/MeetingController.swift`:

````swift
            isPaused = false
            statusMessage = nil
            model.setSystemAudioCaptureObserved(true)
            startMonitor()
            onShowWindow?()
        } catch {
            isRecording = false
            isPaused = false
````

**with:**

````swift
            isPaused = false
            statusMessage = nil
            model.setSystemAudioCaptureObserved(true)
            startMonitor()
            startTranslationLoop()
            onShowWindow?()
        } catch {
            isRecording = false
            isPaused = false
````

**Replace in** `Sources/BugVoice/MeetingController.swift`:

````swift
        notesAtLastRefresh = meeting.notes
        finalSummary = meeting.summary
        summaryState = .waiting
        answer = nil
    }

    /// Picks up transcript lines, marks and progress the session saved.
    private func refreshSnapshot() async {
````

**with:**

````swift
        notesAtLastRefresh = meeting.notes
        finalSummary = meeting.summary
        summaryState = .waiting
        answer = nil
        showEnglish = meeting.showEnglish
    }

    /// Shows English the translation loop saved, also after Stop when no snapshot refresh runs.
    func showTranslations(from meeting: MeetingManifest) {
        guard meeting.id == shownMeetingID, segments != meeting.segments else { return }
        segments = meeting.segments
    }

    /// Picks up transcript lines, marks and progress the session saved.
    private func refreshSnapshot() async {
````

**Replace in** `Sources/BugVoice/MeetingController.swift`:

````swift
    func stop() async {
        guard let session, isRecording || isPaused else { return }
        let recordedSeconds = elapsed
        await flushNotes()
        isRecording = false
        isPaused = false
        isTranscribing = true
        var transcribed = false
````

**with:**

````swift
    func stop() async {
        guard let session, isRecording || isPaused else { return }
        let recordedSeconds = elapsed
        await flushNotes()
        translationHeld = true
        defer { translationHeld = false }
        isRecording = false
        isPaused = false
        isTranscribing = true
        var transcribed = false
````

**Replace in** `Sources/BugVoice/MeetingController.swift`:

````swift
        guard let session else { return }
        await flushNotes()
        monitorTask?.cancel()
        monitorTask = nil
        isRecording = false
        isPaused = false
        isTranscribing = false
        do { _ = try await session.cancel() }
````

**with:**

````swift
        guard let session else { return }
        await flushNotes()
        monitorTask?.cancel()
        monitorTask = nil
        translationLoop?.cancel()
        translationLoop = nil
        isRecording = false
        isPaused = false
        isTranscribing = false
        do { _ = try await session.cancel() }
````

- [ ] **Step 3: `MeetingTranscriptView.swift`**

**Replace in** `Sources/BugVoice/UI/MeetingWindow/MeetingTranscriptView.swift`:

````swift
    let elapsed: TimeInterval
    let isListening: Bool
    @State private var query = ""
    @State private var followNewest = true
````

**with:**

````swift
    let elapsed: TimeInterval
    let isListening: Bool
    /// Show English is offered for this meeting.
    let offersEnglish: Bool
    let showEnglish: Bool
    let englishNeedsModel: Bool
    let onShowEnglish: (Bool) -> Void
    @State private var query = ""
    @State private var followNewest = true
````

**Replace in** `Sources/BugVoice/UI/MeetingWindow/MeetingTranscriptView.swift`:

````swift
        let needle = query.trimmingCharacters(in: .whitespaces)
        let lines = segments
            .filter { needle.isEmpty || $0.text.localizedCaseInsensitiveContains(needle) }
            .map(Row.line)
        let markRows = needle.isEmpty ? marks.map(Row.mark) : []
````

**with:**

````swift
        let needle = query.trimmingCharacters(in: .whitespaces)
        let lines = segments
            .filter {
                needle.isEmpty || $0.text.localizedCaseInsensitiveContains(needle)
                    || (showEnglish && ($0.translation?.localizedCaseInsensitiveContains(needle) ?? false))
            }
            .map(Row.line)
        let markRows = needle.isEmpty ? marks.map(Row.mark) : []
````

**Replace in** `Sources/BugVoice/UI/MeetingWindow/MeetingTranscriptView.swift`:

````swift
                    .controlSize(.small)
                    .disabled(segments.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ZStack(alignment: .bottomTrailing) {
````

**with:**

````swift
                    .controlSize(.small)
                    .disabled(segments.isEmpty)
                if offersEnglish {
                    Toggle("Show English", isOn: Binding(get: { showEnglish }, set: onShowEnglish))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.caption)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            if offersEnglish && showEnglish && englishNeedsModel {
                Text("English needs a Meetings model.")
                    .font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            Divider()
            ZStack(alignment: .bottomTrailing) {
````

**Replace in** `Sources/BugVoice/UI/MeetingWindow/MeetingTranscriptView.swift`:

````swift
                    .foregroundStyle(segment.track == .mic ? Color.accentColor : .secondary)
                    .frame(width: 46, alignment: .leading)
                Text(segment.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
        case .mark(let mark):
````

**with:**

````swift
                    .foregroundStyle(segment.track == .mic ? Color.accentColor : .secondary)
                    .frame(width: 46, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(segment.text)
                    if let english = english(segment) {
                        Text(english).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
        case .mark(let mark):
````

**Replace in** `Sources/BugVoice/UI/MeetingWindow/MeetingTranscriptView.swift`:

````swift
    }

    private func copy() {
        let text = segments.sorted { $0.start < $1.start }.map(MeetingPromptLines.line).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
````

**with:**

````swift
    }

    /// The English shown under a line, or nil.
    private func english(_ segment: MeetingSegment) -> String? {
        guard showEnglish, let english = segment.translation, !english.isEmpty else { return nil }
        return english
    }

    private func copy() {
        let text = segments.sorted { $0.start < $1.start }.map { segment in
            MeetingPromptLines.line(segment) + (english(segment).map { "\n  English: \($0)" } ?? "")
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
````

- [ ] **Step 4: `MeetingWindowView.swift`**

**Replace in** `Sources/BugVoice/UI/MeetingWindow/MeetingWindowView.swift`:

````swift
                marks: controller.marks,
                elapsed: controller.elapsed,
                isListening: controller.isRecording
            )
        case .summary:
````

**with:**

````swift
                marks: controller.marks,
                elapsed: controller.elapsed,
                isListening: controller.isRecording,
                offersEnglish: controller.offersEnglish,
                showEnglish: controller.showEnglish,
                englishNeedsModel: controller.translationNeedsModel,
                onShowEnglish: { show in Task { await controller.setShowEnglish(show) } }
            )
        case .summary:
````

- [ ] **Step 5: Build and test**

Run: `swift build`
Expected: builds with no errors.

Run: `swift test`
Expected: the whole suite passes.

Run: `Scripts/build-app.sh`
Expected: ends with `Built …/build/BugVoice.app`.

- [ ] **Step 6: Run the app once**

Run: `Scripts/run-dev-app.sh`, press ⌃⌥M, open the language chip and turn on Spanish, open Transcript, and run `say -v "Eddy (Spanish (Spain))" "Buenos días a todos. ¿Podemos mover el lanzamiento a noviembre?"` in Terminal.
Expected: the Transcript bar shows Show English, on; about 35 s later the Spanish line shows with its English in a smaller grey line under it. Turn Show English off: the English lines hide. Stop the meeting, close the window and move the test meeting to the Trash.

- [ ] **Step 7: Commit**

```bash
git add Sources/BugVoice/MeetingController+Translation.swift Sources/BugVoice/MeetingController.swift Sources/BugVoice/UI/MeetingWindow/MeetingTranscriptView.swift Sources/BugVoice/UI/MeetingWindow/MeetingWindowView.swift
git commit -m "feat(app): live English under non-English lines in the meeting window" -m "Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 5: English on the meeting detail page

**Files:**
- Modify: `Sources/BugVoice/AppModel.swift`, `Sources/BugVoice/UI/MeetingsPage.swift`

**Interfaces:**
- Consumes: Tasks 1 and 4.
- Produces: `AppModel.setMeetingShowEnglish(id:show:) async` (through the meeting window's session while it owns the meeting, otherwise straight to the store); the detail Transcript tab shows English under each line while Show English is on, and a Show English switch above the lines when any line has English.

- [ ] **Step 1: `AppModel.swift`**

**Replace in** `Sources/BugVoice/AppModel.swift`:

````swift
    }

    func setNoteLabels(id: NoteID, folderID: FolderID?, tags: [String]) async {
        do {
````

**with:**

````swift
    }

    /// Show English from the meeting detail page. Routed like notes.
    func setMeetingShowEnglish(id: MeetingID, show: Bool) async {
        do {
            if let meetings, try await meetings.setShowEnglishInSession(id: id, show: show) {
                await reloadMeetings()
                return
            }
            var meeting = try await meetingStore.load(id: id)
            guard meeting.showEnglish != show else { return }
            meeting.showEnglish = show
            try await meetingStore.save(meeting)
            await reloadMeetings()
        } catch {
            saveError = "Could not update meeting: \(error.localizedDescription)"
        }
    }

    func setNoteLabels(id: NoteID, folderID: FolderID?, tags: [String]) async {
        do {
````

- [ ] **Step 2: `MeetingsPage.swift`**

**Replace in** `Sources/BugVoice/UI/MeetingsPage.swift`:

````swift
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).padding(8)
                }
                let segments = meeting.segments.sorted { $0.start < $1.start }
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
````

**with:**

````swift
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).padding(8)
                }
                if meeting.segments.contains(where: { !($0.translation ?? "").isEmpty }) {
                    HStack {
                        Spacer()
                        Toggle("Show English", isOn: Binding(
                            get: { meeting.showEnglish },
                            set: { show in Task { await model.setMeetingShowEnglish(id: meeting.id, show: show) } }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.caption)
                    }
                    .padding(.horizontal, 9)
                }
                let segments = meeting.segments.sorted { $0.start < $1.start }
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
````

**Replace in** `Sources/BugVoice/UI/MeetingsPage.swift`:

````swift
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 108, alignment: .leading)
                            Text(segment.speaker).font(.caption.weight(.semibold)).frame(width: 60, alignment: .leading)
                            Text(segment.text).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 7)
````

**with:**

````swift
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 108, alignment: .leading)
                            Text(segment.speaker).font(.caption.weight(.semibold)).frame(width: 60, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(segment.text).font(.body)
                                if meeting.showEnglish, let english = segment.translation, !english.isEmpty {
                                    Text(english).font(.callout).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 7)
````

- [ ] **Step 3: Build and test**

Run: `swift build`
Expected: builds with no errors.

Run: `swift test`
Expected: the whole suite passes.

Run: `Scripts/build-app.sh`
Expected: ends with `Built …/build/BugVoice.app`.

- [ ] **Step 4: Run the app once**

Run: `Scripts/run-dev-app.sh`, record a short EN · ES meeting as in Task 4, Stop, wait for the final summary, then click Open in Meetings and close the meeting window.
Expected: the detail Transcript tab shows the English under the Spanish lines and a Show English switch above them; turning it off hides them and stays off after choosing another meeting and back. Move the test meeting to the Trash.

- [ ] **Step 5: Commit**

```bash
git add Sources/BugVoice/AppModel.swift Sources/BugVoice/UI/MeetingsPage.swift
git commit -m "feat(app): English lines and Show English on the meeting detail page" -m "Co-Authored-By: Codex <noreply@openai.com>"
```

---

### Task 6: Checklist rows, handoff and roadmap

**Files:**
- Modify: `docs/ROADMAP.md`, `docs/progress/HANDOFF.md`, `docs/testing/manual-checklist.md`

- [ ] **Step 1: `ROADMAP.md`**

**Replace in** `docs/ROADMAP.md`:

````markdown
| 3 | Models per feature | Pick a model for dictation, meetings and notes separately; cloud API keys (OpenAI, Anthropic, OpenRouter…); coding CLIs (claude, codex, gemini, pi) as providers for slow tasks | Groundwork for 4–6 |
| 4 | Upload audio/video | Upload page (drop or browse → file card → Transcribe → progress), as in OpenWhispr. AVFoundation formats (MP3, WAV, M4A, AIFF, CAF, MP4, MOV, M4V). Result is a meeting with an "Uploaded" badge: timestamped transcript labelled "Speaker", click a line to play, Summary, Action items, export. Keeps `audio.m4a` only | Reuses the meeting pipeline; keeps timestamps so item 6 can cite audio |
| 5 | Meetings v2 | 5a: Meeting detected popup; meeting window docked to the right third with My notes / Transcript / Summary (live) tabs and Ask anything about this meeting; marks feedback and marks on the detail page. Spec: `docs/superpowers/specs/2026-10-16-meetings-v2-design.md`. 5b: live English translation in the Transcript tab | 5a implemented 2026-10-16 (plan `docs/superpowers/plans/2026-10-16-meetings-v2.md`); device checks 172–187 pending. 5b next |
| 6 | Ask AI + MCP server | Chat that answers from notes, dictations and meetings; an MCP server so coding agents read the same data. Answers cite their proof as recording + time range ("Standup, 0:20–0:50"); clicking a citation opens the recording and plays that range. Citations are checked against real segments. The Scratchpad AI box gets a source picker (This note / This folder / All folders); the meeting window Ask box gains All meetings | One retrieval layer serves both |
| 7 | Calendar + export | Calendar via EventKit (Google and Microsoft accounts already added to macOS Calendar, no sign-in); export to Apple Notes and Notion | Polish |
````

**with:**

````markdown
| 3 | Models per feature | Pick a model for dictation, meetings and notes separately; cloud API keys (OpenAI, Anthropic, OpenRouter…); coding CLIs (claude, codex, gemini, pi) as providers for slow tasks | Groundwork for 4–6 |
| 4 | Upload audio/video | Upload page (drop or browse → file card → Transcribe → progress), as in OpenWhispr. AVFoundation formats (MP3, WAV, M4A, AIFF, CAF, MP4, MOV, M4V). Result is a meeting with an "Uploaded" badge: timestamped transcript labelled "Speaker", click a line to play, Summary, Action items, export. Keeps `audio.m4a` only | Reuses the meeting pipeline; keeps timestamps so item 6 can cite audio |
| 5 | Meetings v2 | 5a: Meeting detected popup; meeting window docked to the right third with My notes / Transcript / Summary (live) tabs and Ask anything about this meeting; marks feedback and marks on the detail page. Spec: `docs/superpowers/specs/2026-10-16-meetings-v2-design.md`. 5b: live English translation under each Transcript line. Spec: `docs/superpowers/specs/2026-10-16-meetings-translation-design.md` | 5a implemented 2026-10-16 (plan `docs/superpowers/plans/2026-10-16-meetings-v2.md`); device checks 172–187 pending. 5b implemented 2026-10-16 (plan `docs/superpowers/plans/2026-10-16-meetings-translation.md`); device checks 188–194 pending |
| 6 | Ask AI + MCP server | Chat that answers from notes, dictations and meetings; an MCP server so coding agents read the same data. Answers cite their proof as recording + time range ("Standup, 0:20–0:50"); clicking a citation opens the recording and plays that range. Citations are checked against real segments. The Scratchpad AI box gets a source picker (This note / This folder / All folders); the meeting window Ask box gains All meetings | One retrieval layer serves both |
| 7 | Calendar + export | Calendar via EventKit (Google and Microsoft accounts already added to macOS Calendar, no sign-in); export to Apple Notes and Notion | Polish |
````

- [ ] **Step 2: `HANDOFF.md`**

**Replace in** `docs/progress/HANDOFF.md`:

````markdown
Stop that follows the notes). Notes are stored on the meeting manifest. Device
checks 172–187 pending.

**Packaging:** app icon (Antenna Mic) and `Scripts/build-dmg.sh`; current version 0.1.0 build 10.
````

**with:**

````markdown
Stop that follows the notes). Notes are stored on the meeting manifest. Device
checks 172–187 pending.

Meetings v2 (5b) implemented: spec
`docs/superpowers/specs/2026-10-16-meetings-translation-design.md`, plan
`docs/superpowers/plans/2026-10-16-meetings-translation.md`. When a meeting's
languages include one other than English, each new line gets its English under
it, through the Meetings model (12 lines per request, thinking off, one request
at a time, after dictation and the summaries). English is saved on each line
(`MeetingSegment.translation`), carried over to the final transcript at Stop,
shown on the detail page and written to the Markdown export. Show English
(`MeetingManifest.showEnglish`) hides it. Device checks 188–194 pending.

**Packaging:** app icon (Antenna Mic) and `Scripts/build-dmg.sh`; current version 0.1.0 build 10.
````

- [ ] **Step 3: `manual-checklist.md`**

**Replace in** `docs/testing/manual-checklist.md`:

````markdown
| 186 | Meeting detail | Open the meeting: My notes tab, edit it; playback timeline; Transcript; Send to Scratchpad › My notes; Export › Markdown | Notes show and save; marks are orange ticks and Mark lines, a click plays from the mark; Send creates "Title · My notes"; the export has `## My notes` | |
| 187 | Meeting window | Quit BugVoice with Force Quit 5 s after typing notes during a meeting; relaunch | The recovered meeting keeps the notes | |

Review-focus inputs: zero-length file; 48 kHz stereo or 5.1; video track only;
````

**with:**

````markdown
| 186 | Meeting detail | Open the meeting: My notes tab, edit it; playback timeline; Transcript; Send to Scratchpad › My notes; Export › Markdown | Notes show and save; marks are orange ticks and Mark lines, a click plays from the mark; Send creates "Title · My notes"; the export has `## My notes` | |
| 187 | Meeting window | Quit BugVoice with Force Quit 5 s after typing notes during a meeting; relaunch | The recovered meeting keeps the notes | |
| 188 | Meeting translation | Start a meeting with languages EN · ES (or EN · VI); open Transcript; play Spanish speech (`say -v "Eddy (Spanish (Spain))" "Buenos días a todos"`) and English speech | Show English switch in the Transcript bar, on; each Spanish line gets a smaller grey English line under it within about 10 s of appearing; English lines get none | |
| 189 | Meeting translation | Start a meeting with languages EN only | No Show English switch; no English lines | |
| 190 | Meeting translation | Turn Show English off, talk, turn it on | Off hides the English and no new lines get it; on shows them again and the new lines get English | |
| 191 | Meeting translation | Set the Meetings model to none; start an EN · ES meeting | "English needs a Meetings model." under the Transcript bar; recording goes on | |
| 192 | Meeting translation | Stop | After the final summary, the final lines show English (most carried over at once, the rest within a minute) | |
| 193 | Meeting detail | Open the meeting: Transcript; Show English off and on; Export › Markdown; search the Meetings list for an English word | English under each translated line; the switch hides it and is kept; the export has `  English: …` under translated lines; search finds the meeting | |
| 194 | Meeting translation | Hold Right Option and dictate during an EN · ES meeting | Dictation is not slowed; translation waits for it | |

Review-focus inputs: zero-length file; 48 kHz stereo or 5.1; video track only;
````

- [ ] **Step 4: Final check**

Run: `swift test && Scripts/build-app.sh`
Expected: 610 VoiceCore and 84 BugVoiceMac tests pass and the app builds.

- [ ] **Step 5: Commit**

```bash
git add docs/ROADMAP.md docs/progress/HANDOFF.md docs/testing/manual-checklist.md
git commit -m "docs: Meetings translation checklist rows, handoff and roadmap" -m "Co-Authored-By: Codex <noreply@openai.com>"
```

Then stop and report: the list of commits, the test counts, and anything that did not behave as written.
