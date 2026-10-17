# Meeting Speakers (Part 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After Stop, after an upload, and on demand, split the call voices into Other 1, Other 2, … with SpeakerKit, and let the owner set the number of people, rename speakers, fix single lines, with the names used everywhere.

**Architecture:** All speaker decisions are pure functions in `VoiceCore` (`MeetingSpeakers`, TDD) acting on `MeetingManifest`. Each line keeps a `speakerID` and a copy of its display name (`speakerName`), so every existing use of `MeetingSegment.speaker` (export, prompts, search, summary) shows names with no change at the call sites. A small `SpeakerSplitter` actor in `WhisperEngine` wraps SpeakerKit; `AppModel.findSpeakers` loads audio, runs it, and saves through the meeting window's session when it owns the meeting, otherwise the store (the Show English routing).

**Tech Stack:** Swift 6.4 (tools 6.0), SwiftUI/AppKit, Swift Testing, SpeakerKit from the pinned `WhisperKit` 1.1.1 package, macOS 15 floor.

**Spec:** `docs/superpowers/specs/2026-10-17-meeting-speakers-design.md` (Part 1: sections 1–7, 9–11). Mockup: `docs/design/proposal-meeting-speakers.html`. Part 2 (section 8) is not in this plan.

## Global Constraints

- Swift package, tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only.
- No new package. SpeakerKit is a product of the already pinned `WhisperKit` package (`exact: "1.1.1"`); add a `THIRD_PARTY_NOTICES.md` entry for its model weights (`argmaxinc/speakerkit-coreml`, CC-BY-4.0, downloaded at runtime, not redistributed).
- TDD for everything in `VoiceCore`: failing test first. `swift test` passes before every commit.
- Build with `Scripts/build-app.sh` only; run with `Scripts/run-dev-app.sh`.
- Never send audio or text off this Mac. The only network use is the one-time model download from Hugging Face, like the Whisper models.
- UI copy: plain English, no hedging, no emoji. Use the spec's section 10 strings exactly.
- Older meeting files load unchanged: `speakerID`/`speakerName` decode nil, `speakers` `[]`, `speakerSplit` `.none`, `speakerNamesAtSummary` nil.
- Commit per task, by path, `feat(core):` / `feat(engine):` / `feat(app):` / `docs:`.

## Review Focus

1. A meeting whose transcript is rebuilt after a split (Retry transcription on a failed meeting) — lines with the same track, text and start within 1 s keep their speaker; the rest fall back to the track default. Pinned by `carryOverKeepsSpeaker` (Task 1).
2. A rename that differs from an existing name only by case or spaces ("dani ", "Dani") — refused as a duplicate; the stored name is trimmed. Pinned by `renameTrimsAndRefusesCaseInsensitiveDuplicates` (Task 2).
3. Silence on the call track (the split returns no turns) — the split ends `.done`, no Other speakers, call lines keep "Others", People shows You only. Pinned by `splitWithNoTurnsLeavesCallLinesAsOthers` (Task 2).
4. The meeting window still owns the meeting when the split or an edit is saved — the write goes through its session, so the window's later saves do not overwrite it. Pinned by `sessionAppliesSpeakerEdits` (Task 3) and checked on the device (Task 7 checklist).
5. An upload, or an older recording with only `audio.m4a` — every line is placed, nobody is forced to You. Pinned by `uploadSplitPlacesAllLinesWithoutYou` (Task 2).

## File map

| File | Task | Responsibility |
|---|---|---|
| `Sources/VoiceCore/Meeting.swift`, `MeetingTranslation.swift` | 1 | `speakerID`, `speakerName` on lines; `MeetingSpeaker`, `SpeakerSplitState`, manifest fields; carry-over |
| `Sources/VoiceCore/MeetingSpeakers.swift` (new) | 2 | Placing lines, applying a split, names carried over, edits, People, notice |
| `Sources/VoiceCore/MeetingSession.swift`, `Meeting.swift` | 3 | Session edits; summary saves stamp the names |
| `Sources/WhisperEngine/SpeakerSplitter.swift` (new), `Package.swift`, `THIRD_PARTY_NOTICES.md` | 4 | SpeakerKit wrapper |
| `Sources/BugVoice/AppModel+Speakers.swift` (new), `MeetingController*.swift`, `UploadController.swift` | 5 | `findSpeakers`, `editMeetingSpeakers`, hooks after Stop, recovery, upload |
| `Sources/BugVoice/UI/MeetingSpeakersRow.swift` (new), `UI/MeetingsPage.swift`, `UI/MeetingWindow/MeetingTranscriptView.swift` | 6 | Speakers row, line menu, notices, colours |
| `docs/…` | 7 | Device checks 195–206, handoff, roadmap |

## Setup

```bash
cd /Users/cong.bui/Kael/19-AppBuild/BugVoice
git worktree add ../BugVoice-meeting-speakers -b feat/meeting-speakers main
cd ../BugVoice-meeting-speakers
swift test
```
Expected: 619 VoiceCore and 84 BugVoiceMac tests pass.

---

### Task 1: Speaker fields on lines and meetings

**Files:**
- Modify: `Sources/VoiceCore/Meeting.swift` (`MeetingSegment`, `MeetingManifest`)
- Modify: `Sources/VoiceCore/MeetingTranslation.swift` (`carryOver`)
- Test: `Tests/VoiceCoreTests/MeetingSpeakersTests.swift` (new), `Tests/VoiceCoreTests/MeetingTranslationTests.swift`

**Interfaces:**
- Produces:
  - `MeetingSegment.speakerID: String?`, `MeetingSegment.speakerName: String?` (init parameters default nil). `speaker` returns `speakerName` when non-nil, else today's track default ("You" / "Others" / "Speaker").
  - `public struct MeetingSpeaker: Codable, Equatable, Sendable, Identifiable { id: String; name: String?; colorIndex: Int; centroid: [Float]? }`
  - `public enum SpeakerSplitState: Codable, Equatable, Sendable { case none, running, done, failed(String) }`
  - `MeetingManifest.speakers: [MeetingSpeaker]` (default `[]`), `speakerSplit: SpeakerSplitState` (default `.none`), `speakerNamesAtSummary: [String: String]?` (default nil); all three decoded with defaults when missing.
  - `MeetingTranslation.carryOver` also carries `speakerID` and `speakerName` with the translation, on the same match rule.

- [ ] **Step 1: Failing tests**

```swift
@Test func olderFilesDecodeWithoutSpeakers() throws {
    // A manifest JSON written before this change (copy one from MeetingTests' fixtures, no speaker keys).
    let meeting = try JSONDecoder.meeting.decode(MeetingManifest.self, from: olderManifestJSON)
    #expect(meeting.speakers == [])
    #expect(meeting.speakerSplit == .none)
    #expect(meeting.speakerNamesAtSummary == nil)
    #expect(meeting.segments.allSatisfy { $0.speakerID == nil && $0.speakerName == nil })
}

@Test func speakerNameWinsOverTrackDefault() {
    #expect(MeetingSegment(start: 0, end: 1, text: "a", track: .system).speaker == "Others")
    #expect(MeetingSegment(start: 0, end: 1, text: "a", track: .system, speakerID: "s1", speakerName: "Dani").speaker == "Dani")
}

@Test func splitStateRoundTrips() throws {
    for state in [SpeakerSplitState.none, .running, .done, .failed("No call audio")] {
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(SpeakerSplitState.self, from: data) == state)
    }
}
```
In `MeetingTranslationTests`:
```swift
@Test func carryOverKeepsSpeaker() {
    let live = [MeetingSegment(id: "a", start: 10, end: 12, text: "Hello", track: .system, speakerID: "s2", speakerName: "Mariel")]
    let final = [MeetingSegment(id: "b", start: 10.4, end: 12, text: "Hello", track: .system),
                 MeetingSegment(id: "c", start: 30, end: 31, text: "New", track: .system)]
    let carried = MeetingTranslation.carryOver(from: live, to: final)
    #expect(carried[0].speakerID == "s2" && carried[0].speakerName == "Mariel")
    #expect(carried[1].speakerID == nil && carried[1].speakerName == nil)
}
```
Use whatever JSON decoder `MeetingTests` already uses for manifests in place of `JSONDecoder.meeting`.

- [ ] **Step 2:** `swift test --filter "MeetingSpeakersTests|MeetingTranslationTests"` — fails to compile (no `speakerID`).
- [ ] **Step 3:** Add the fields and types. `MeetingManifest` already decodes with defaults for newer fields; follow that pattern for the three new ones. In `carryOver`, copy `speakerID` and `speakerName` wherever it copies `translation`.
- [ ] **Step 4:** `swift test` — all pass.
- [ ] **Step 5:** Commit `feat(core): speaker fields on meeting lines and manifests`.

---

### Task 2: `MeetingSpeakers` — placing lines, splits, edits

**Files:**
- Create: `Sources/VoiceCore/MeetingSpeakers.swift`
- Test: `Tests/VoiceCoreTests/MeetingSpeakersTests.swift`

**Interfaces:**
- Consumes: Task 1 types.
- Produces (all `public`, in `public enum MeetingSpeakers`):
  - `struct Turn: Equatable, Sendable { voice: Int; start: TimeInterval; end: TimeInterval }`
  - `struct SplitResult: Equatable, Sendable { turns: [Turn]; centroids: [Int: [Float]] }`
  - `enum Edit: Equatable, Sendable { case rename(speakerID: String, name: String); case assign(segmentID: String, speakerID: String); case newPerson(segmentID: String, name: String) }`
  - `enum EditError: Error, Equatable { case duplicateName(String); case unknownSpeaker; case unknownSegment }`
  - `static let youID = "you"`, `static let colorCount = 6`
  - `static func splitTracks(for meeting: MeetingManifest, hasCallAudio: Bool) -> Set<MeetingTrack>` — `[.system]` for a recording with `system.m4a`; `[.mic, .system]` for a recording without it; `[.file]` for an upload.
  - `static func place(_ segments: [MeetingSegment], turns: [Turn], tracks: Set<MeetingTrack>) -> [String: Int]` — segment id → voice.
  - `static func applySplit(_ result: SplitResult, to meeting: MeetingManifest, tracks: Set<MeetingTrack>) -> MeetingManifest`
  - `static func apply(_ edit: Edit, to meeting: MeetingManifest) throws -> MeetingManifest`
  - `static func people(in meeting: MeetingManifest) -> Int` — count of `speakers`.
  - `static func peopleRange(in meeting: MeetingManifest) -> ClosedRange<Int>` — `2...10` when `speakers` contains `you` and any call line exists; else `1...10`.
  - `static func voices(forPeople people: Int, in meeting: MeetingManifest) -> Int` — `people - 1` when `speakers` contains `you`, else `people`.
  - `static func names(in meeting: MeetingManifest) -> [String: String]` — speaker id → display name.
  - `static func namesChangedSinceSummary(_ meeting: MeetingManifest) -> Bool` — true when `summary` or `actionItems` is non-empty and `speakerNamesAtSummary != names(in:)` (a nil stamp with any `speakers` counts as changed).
  - `static func defaultName(for id: String) -> String` — "You" for `you`, "Other N" for `sN`.

Rules the tests pin (spec sections 5, 7):
- `place`: a line on a split track gets the voice whose turns overlap it the most (sum of overlap seconds per voice); with no overlap, the voice of the nearest turn whose gap is ≤ 1 s; otherwise no entry. Ties go to the voice whose overlapping (or nearest) turn starts earlier. Lines on other tracks get no entry.
- `applySplit`:
  - Voices are numbered `s1`, `s2`, … in order of their first placed line. Voices with no placed line are dropped.
  - When `tracks == [.system]`, every `.mic` line gets `speakerID = "you"` and a `you` speaker is kept (name carried from the old `you`). Otherwise no `you` speaker.
  - Old speaker names carry over: among old `sN` speakers that have a name and a centroid, and new voices with a centroid, take pairs closest first by cosine distance, each old and each new used once; the new speaker takes the old name.
  - Old `pN` speakers and single-line fixes are dropped: every line on a split track is re-placed; unplaced lines get `speakerID = nil`.
  - Colours: `you` 0, then speakers in order 1, 2, …, cycling `% colorCount`.
  - Every line's `speakerName` is set from its speaker (`name ?? defaultName`), or nil when `speakerID` is nil.
  - `speakerSplit = .done`.
- `apply(.rename)`: trims; empty → `name = nil` (default label); a trimmed name equal, ignoring case, to another speaker's display name → `duplicateName(name)`; updates `speakerName` on that speaker's lines.
- `apply(.assign)`: moves one line; a speaker left with no line is removed.
- `apply(.newPerson)`: trims; empty or duplicate → error; new id `pN` with the next unused N, next colour; moves the line.

- [ ] **Step 1: Failing tests** (helpers `line(_ id:, _ start:, _ end:, _ track:)` and `turn(_ voice:, _ start:, _ end:)` in the test file):

```swift
@Test func mostOverlapWinsAndNearTurnWithinOneSecond() {
    let lines = [line("a", 0, 4, .system), line("b", 10, 11, .system), line("c", 20, 21, .system), line("m", 0, 4, .mic)]
    let turns = [turn(0, 0, 1), turn(1, 1, 4), turn(1, 11.8, 15)]
    let placed = MeetingSpeakers.place(lines, turns: turns, tracks: [.system])
    #expect(placed == ["a": 1, "b": 1])   // b: gap 0.8 s; c: gap > 1 s; m: other track
}

@Test func tiesGoToTheEarlierTurn() {
    let placed = MeetingSpeakers.place([line("a", 0, 2, .system)], turns: [turn(3, 0, 1), turn(4, 1, 2)], tracks: [.system])
    #expect(placed == ["a": 3])
}

@Test func recordedSplitNumbersVoicesByFirstLineAndKeepsMicAsYou() {
    var meeting = recorded([line("m", 0, 2, .mic), line("a", 3, 5, .system), line("b", 6, 8, .system)])
    meeting = MeetingSpeakers.applySplit(.init(turns: [turn(7, 6, 8), turn(2, 3, 5), turn(9, 20, 21)], centroids: [:]), to: meeting, tracks: [.system])
    #expect(meeting.speakers.map(\.id) == ["you", "s1", "s2"])     // voice 9 had no line: dropped
    #expect(meeting.segments.map(\.speakerName) == ["You", "Other 1", "Other 2"])
    #expect(meeting.speakers.map(\.colorIndex) == [0, 1, 2])
    #expect(meeting.speakerSplit == .done)
    #expect(MeetingSpeakers.people(in: meeting) == 3)
    #expect(MeetingSpeakers.peopleRange(in: meeting) == 2...10)
    #expect(MeetingSpeakers.voices(forPeople: 3, in: meeting) == 2)
}

@Test func uploadSplitPlacesAllLinesWithoutYou() {
    var meeting = upload([line("a", 0, 2, .file), line("b", 3, 5, .file)])
    meeting = MeetingSpeakers.applySplit(.init(turns: [turn(0, 0, 2), turn(1, 3, 5)], centroids: [:]), to: meeting, tracks: [.file])
    #expect(meeting.speakers.map(\.id) == ["s1", "s2"])
    #expect(MeetingSpeakers.peopleRange(in: meeting) == 1...10)
    #expect(MeetingSpeakers.voices(forPeople: 2, in: meeting) == 2)
}

@Test func splitWithNoTurnsLeavesCallLinesAsOthers() {
    var meeting = recorded([line("m", 0, 2, .mic), line("a", 3, 5, .system)])
    meeting = MeetingSpeakers.applySplit(.init(turns: [], centroids: [:]), to: meeting, tracks: [.system])
    #expect(meeting.speakers.map(\.id) == ["you"])
    #expect(meeting.segments[1].speaker == "Others")
    #expect(meeting.speakerSplit == .done)
}

@Test func splitAgainCarriesNamesToClosestVoicesAndClearsLineFixes() throws {
    var meeting = recorded([line("a", 0, 2, .system), line("b", 3, 5, .system), line("c", 6, 8, .system)])
    meeting = MeetingSpeakers.applySplit(.init(turns: [turn(0, 0, 2), turn(1, 3, 8)], centroids: [0: [1, 0], 1: [0, 1]]), to: meeting, tracks: [.system])
    meeting = try MeetingSpeakers.apply(.rename(speakerID: "s1", name: "Dani"), to: meeting)
    meeting = try MeetingSpeakers.apply(.rename(speakerID: "s2", name: "Mariel"), to: meeting)
    meeting = try MeetingSpeakers.apply(.newPerson(segmentID: "c", name: "David"), to: meeting)
    // New split: voice 5 sounds like Mariel, voice 6 like Dani, voice 7 is new.
    meeting = MeetingSpeakers.applySplit(.init(turns: [turn(5, 0, 2), turn(6, 3, 5), turn(7, 6, 8)],
                                               centroids: [5: [0.1, 1], 6: [1, 0.1], 7: [0.7, 0.7]]), to: meeting, tracks: [.system])
    #expect(meeting.segments.map(\.speakerName) == ["Mariel", "Dani", "Other 3"])
    #expect(!meeting.speakers.contains { $0.id.hasPrefix("p") })
}

@Test func renameTrimsAndRefusesCaseInsensitiveDuplicates() throws {
    var meeting = split3()   // you, s1, s2 with one line each
    meeting = try MeetingSpeakers.apply(.rename(speakerID: "s1", name: "  Dani "), to: meeting)
    #expect(meeting.speakers[1].name == "Dani")
    #expect(throws: MeetingSpeakers.EditError.duplicateName("dani")) {
        try MeetingSpeakers.apply(.rename(speakerID: "s2", name: "dani"), to: meeting)
    }
    meeting = try MeetingSpeakers.apply(.rename(speakerID: "s1", name: " "), to: meeting)
    #expect(meeting.segments[1].speakerName == "Other 1")
}

@Test func assignMovesOneLineAndRemovesEmptySpeakers() throws {
    var meeting = split3()
    meeting = try MeetingSpeakers.apply(.assign(segmentID: meeting.segments[2].id, speakerID: "s1"), to: meeting)
    #expect(meeting.speakers.map(\.id) == ["you", "s1"])
    #expect(meeting.segments[2].speakerName == "Other 1")
    #expect(throws: MeetingSpeakers.EditError.unknownSpeaker) {
        try MeetingSpeakers.apply(.assign(segmentID: meeting.segments[0].id, speakerID: "s9"), to: meeting)
    }
}

@Test func newPersonGetsNextIdAndColour() throws {
    var meeting = split3()
    meeting = try MeetingSpeakers.apply(.newPerson(segmentID: meeting.segments[1].id, name: "David"), to: meeting)
    #expect(meeting.speakers.last == MeetingSpeaker(id: "p1", name: "David", colorIndex: 3, centroid: nil))
    #expect(meeting.segments[1].speaker == "David")
}

@Test func namesChangedNoticeFollowsTheSummaryStamp() throws {
    var meeting = split3()
    meeting.summary = "- Release on Friday"
    #expect(MeetingSpeakers.namesChangedSinceSummary(meeting))
    meeting.speakerNamesAtSummary = MeetingSpeakers.names(in: meeting)
    #expect(!MeetingSpeakers.namesChangedSinceSummary(meeting))
    meeting = try MeetingSpeakers.apply(.rename(speakerID: "s1", name: "Dani"), to: meeting)
    #expect(MeetingSpeakers.namesChangedSinceSummary(meeting))
    meeting.summary = nil
    #expect(!MeetingSpeakers.namesChangedSinceSummary(meeting))
}

@Test func exportAndSearchUseNames() throws {
    let meeting = try MeetingSpeakers.apply(.rename(speakerID: "s1", name: "Dani"), to: split3())
    #expect(MeetingExport.markdown(meeting).contains("| Dani |"))
    #expect(MeetingListProjection.matches(meeting, query: "dani"))
}
```
`recorded`, `upload` and `split3` build manifests (`source: .recording` / `.upload`; `split3` = recorded `[mic 0–2, system 3–5, system 6–8]` after `applySplit` with voices 0 and 1). For `exportAndSearchUseNames`, add a speaker-name match to `MeetingListProjection.matches` if the test fails (it searches `segments` text today).

- [ ] **Step 2:** `swift test --filter MeetingSpeakersTests` — fails (no `MeetingSpeakers`).
- [ ] **Step 3:** Implement in `Sources/VoiceCore/MeetingSpeakers.swift` to the rules above. Cosine distance: `1 - dot / (|a||b|)`; skip pairs with different lengths or a zero vector.
- [ ] **Step 4:** `swift test` — all pass.
- [ ] **Step 5:** Commit `feat(core): place meeting lines on speakers, rename and fix lines`.

---

### Task 3: Session edits and the summary stamp

**Files:**
- Modify: `Sources/VoiceCore/MeetingSession.swift`, `Sources/VoiceCore/Meeting.swift`
- Test: `Tests/VoiceCoreTests/MeetingSessionTests.swift`

**Interfaces:**
- Consumes: Task 2.
- Produces:
  - `MeetingManifest.setGeneratedText(_ text: String, kind: MeetingTextKind)` (mutating): sets `summary` or `actionItems`; for `.summary` also sets `speakerNamesAtSummary = MeetingSpeakers.names(in: self)`.
  - `MeetingSession.updateSpeakers(_ change: @Sendable (MeetingManifest) throws -> MeetingManifest) async throws` — allowed in `acceptsNotes` states, else `MeetingSessionError.invalidState`; saves.
  - `MeetingSession.saveGeneratedText` uses `setGeneratedText`.

- [ ] **Step 1: Failing tests**

```swift
@Test func sessionAppliesSpeakerEdits() async throws {
    let (session, store) = try await readyRecordedSession(lines: [/* mic 0–2, system 3–5 */])
    try await session.updateSpeakers { try MeetingSpeakers.apply(.rename(speakerID: "you", name: "Cong"),
        to: MeetingSpeakers.applySplit(.init(turns: [.init(voice: 0, start: 3, end: 5)], centroids: [:]), to: $0, tracks: [.system])) }
    let saved = try await store.load(id: session.snapshot()!.id)
    #expect(saved.segments.map(\.speaker) == ["Cong", "Other 1"])
}

@Test func speakerEditsRefusedWhenInterrupted() async throws {
    let session = try await interruptedSession()
    await #expect(throws: MeetingSessionError.invalidState) { try await session.updateSpeakers { $0 } }
}

@Test func summarySaveStampsSpeakerNames() async throws {
    let (session, _) = try await readyRecordedSession(lines: [/* mic 0–2 */])
    try await session.updateSpeakers { MeetingSpeakers.applySplit(.init(turns: [], centroids: [:]), to: $0, tracks: [.system]) }
    try await session.saveGeneratedText("- Done", kind: .summary)
    #expect(await session.snapshot()?.speakerNamesAtSummary == ["you": "You"])
}
```
Build the sessions with the helpers `MeetingSessionTests` already uses for `setShowEnglish`.

- [ ] **Step 2:** Run — fails. **Step 3:** Implement; switch the store path in `AppModel.performMeetingText` (`current.summary = text` / `current.actionItems = text`) to `current.setGeneratedText(text, kind: kind)` in the same commit. **Step 4:** `swift test` passes. **Step 5:** Commit `feat(core): speaker edits through the meeting session; summary remembers names`.

---

### Task 4: `SpeakerSplitter` (SpeakerKit)

**Files:**
- Modify: `Package.swift` (WhisperEngine dependencies: add `.product(name: "SpeakerKit", package: "WhisperKit")`)
- Create: `Sources/WhisperEngine/SpeakerSplitter.swift`
- Modify: `THIRD_PARTY_NOTICES.md`

**Interfaces:**
- Produces: `public actor SpeakerSplitter { public init(downloadBase: URL); public func split(audio: URL, voices: Int?) async throws -> MeetingSpeakers.SplitResult; public func unload() async }`

- [ ] **Step 1:** Add the product to `WhisperEngine`. `swift build` resolves with no new package (`Package.resolved` unchanged; check `git diff Package.resolved` is empty).
- [ ] **Step 2:** Implement. Create `SpeakerKit(PyannoteConfig(downloadBase: downloadBase.path, download: true, load: false, verbose: false))` lazily on first `split`, the same load-once pattern as `WhisperKitTranscriber.loadedKit`. Load audio with `AudioProcessor.loadAudioAsFloatArray(fromPath:)` (16 kHz mono). Diarize with `PyannoteDiarizationOptions(numberOfSpeakers: voices, clusterDistanceThreshold: Tuning.clusterDistanceThreshold, minClusterSize: Tuning.minClusterSize)`. Map each `SpeakerSegment` with `speaker.speakerId != nil` to `Turn(voice:start:end:)` (`Double(startTime)`, `Double(endTime)`); centroids from `speakerCentroidEmbeddings`. `enum Tuning { static let clusterDistanceThreshold: Float? = nil; static let minClusterSize: Int? = nil }` until the tuning in Task 7 sets them.
- [ ] **Step 3:** Notice entry under the WhisperKit one:

```markdown
## SpeakerKit models

- Source: https://huggingface.co/argmaxinc/speakerkit-coreml (Pyannote "community-1", converted to Core ML by Argmax)
- Licence: CC-BY-4.0.
- Use: telling meeting voices apart on device (`Sources/WhisperEngine/SpeakerSplitter.swift`).
- Downloaded at runtime into BugVoice's models folder; not redistributed in this repository.
```
- [ ] **Step 4:** `swift build` and `swift test` pass. **Step 5:** Commit `feat(engine): SpeakerKit speaker splitter`.

---

### Task 5: Finding speakers and saving edits in the app

**Files:**
- Create: `Sources/BugVoice/AppModel+Speakers.swift`
- Modify: `Sources/BugVoice/AppModel.swift` (own a `SpeakerSplitter(downloadBase: paths.models)`), `MeetingController.swift`, `MeetingController+Assistant.swift` or wherever `stop`/`recover` end, `UploadController.swift`

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces:
  - `AppModel.findSpeakers(id: MeetingID, people: Int?) async` — runs one at a time per meeting (`speakerTasks[id]`).
  - `AppModel.editMeetingSpeakers(id: MeetingID, edit: MeetingSpeakers.Edit) async -> MeetingSpeakers.EditError?` — returns the error for the UI (duplicate name), sets `saveError` for other failures.
  - `MeetingController.updateSpeakersInSession(id: MeetingID, change: @Sendable (MeetingManifest) throws -> MeetingManifest) async throws -> Bool` and the same on `UploadController` — false when the session does not own the meeting (the `setShowEnglishInSession` pattern).

`findSpeakers` steps:
1. Load the manifest (store). Audio: `system.m4a` when `source == .recording` and the file exists; else `audio.m4a`. No file → save `.failed("No call audio")` and return. Tracks: `MeetingSpeakers.splitTracks(for:hasCallAudio:)`.
2. Save `speakerSplit = .running` (through `updateSpeakers` routing), reload meetings.
3. `voices = people.map { MeetingSpeakers.voices(forPeople: $0, in: manifest) }`; `try await splitter.split(audio:voices:)`.
4. Save `MeetingSpeakers.applySplit(result, to: $0, tracks:)` via the routing closure (applied to the current manifest, not the one loaded in step 1). On error save `.failed(error.localizedDescription)`. Reload meetings.

Hooks (each after the transcript is final, before any summary):
- `MeetingController.stop()`: when `transcribed`, `await model.findSpeakers(id:, people: nil)` before `generateFinalSummary()`, then `await refreshSnapshot()` so the window shows names.
- `MeetingController.recover(id:)`: after the transcript completes.
- `UploadController.run`: after `queue.apply(id: job.id, event: .ready)`.
- Do not hook meetings that end with no segments.

- [ ] **Step 1:** Implement. **Step 2:** `swift build`, `swift test` pass. **Step 3:** Build with `Scripts/build-app.sh`, run with `Scripts/run-dev-app.sh`, record 20 s with two `say` voices on the call track (`say -v Samantha …`, `say -v Daniel …` through the speakers), Stop, and check `meeting.json` has `speakerSplit: done`, `speakers` you/s1/s2, and lines with `speakerName`. Move the test meeting to `~/.Trash`. **Step 4:** Commit `feat(app): find speakers after Stop, recovery and uploads`.

---

### Task 6: Speakers row, line menu and names in the UI

**Files:**
- Create: `Sources/BugVoice/UI/MeetingSpeakersRow.swift`
- Modify: `Sources/BugVoice/UI/MeetingsPage.swift` (transcript, around the Show English row), `Sources/BugVoice/UI/MeetingWindow/MeetingTranscriptView.swift` (`rowView`)

**Interfaces:**
- Consumes: Task 5's `findSpeakers` and `editMeetingSpeakers`; Task 2's `people`, `peopleRange`, `namesChangedSinceSummary`.
- Produces: `struct MeetingSpeakersRow: View { let meeting: MeetingManifest }`, `enum SpeakerColors { static func color(_ index: Int) -> Color }` (six colours from the mockup's `--s0`…`--s5`, light and dark).

Build exactly the mockup's detail-page states (spec sections 5.1–5.4, copy from section 10):
- Row: "People in this meeting" − N + (bounded by `peopleRange`; − or + shows the inline confirm "Split again for N people? …" with Split again / Cancel, then `findSpeakers(id:, people: N)`), "Speakers", one chip per speaker (dot + name). Click a chip: inline `TextField`, Return or focus loss saves `.rename`, Escape cancels; a `duplicateName` error shows "Dani is already a speaker." under the row.
- `.running`: "Finding speakers…" with a small spinner instead of the row; chips disabled.
- `.failed`: "Speakers could not be found." [Try again] → `findSpeakers(id:, people: nil)`.
- `.none` with segments: "This meeting was recorded before speakers were split." [Find speakers].
- Notice when `namesChangedSinceSummary`: "Names changed. The summary still uses the old names." [Regenerate summary] (existing summary and action items generation) [Not now] (hides it until the names change again; view state only).
- Line label: speaker colour; clicking it opens a `Menu`: every speaker (dot + name), divider, "New person…" (small popover with a field; Return saves `.newPerson`). The row's existing tap-to-seek stays on the time and text.
- Meeting window `rowView`: label colour from the speaker's `colorIndex` when `speakerID` is set (`.mic` keeps the accent colour otherwise); no menus.

- [ ] **Step 1:** Implement. **Step 2:** `swift build`, `swift test`. **Step 3:** Build, run, and walk the mockup states on a meeting recorded with two `say` voices: rename, duplicate refused, fix one line, New person, People − and +, Regenerate summary notice, Find speakers on an older meeting (record a test meeting, quit the app, set its `speakerSplit` to `"none"` and remove its `speakers` with `jq`, relaunch; never edit the owner's own meetings). Capture the window (find its position first). Trash test meetings. **Step 4:** Commit `feat(app): rename speakers and fix lines on the meeting page`.

---

### Task 7: Tuning, device checks and docs

**Files:**
- Modify: `Sources/WhisperEngine/SpeakerSplitter.swift` (`Tuning`), `docs/progress/meetings-log.md` (checklist rows), `docs/progress/HANDOFF.md`, `docs/ROADMAP.md`

- [ ] **Step 1: Tune the automatic count** on the owner's clips (spec section 3): for each clip with a known number of people, run `SpeakerSplitter` with `voices: nil` and a small grid (`clusterDistanceThreshold` 0.6, 0.7, 0.8; `minClusterSize` nil, 3, 6) through a throwaway test target or the scratchpad `argmax-cli` (`diarize --cluster-distance-threshold`), and record found vs real counts in `meetings-log.md`. Set `Tuning` to the best row; leave nil if none beats the defaults. If no clips are available, keep nil and say so in the log.
- [ ] **Step 2: Checklist rows 195–206** in `meetings-log.md` (one per spec behaviour: split after Stop, upload split, People −/+, rename, duplicate refused, fix a line, New person, names in export, names in Ask, Regenerate notice, Find speakers on an older meeting, window shows names read only).
- [ ] **Step 3:** HANDOFF and ROADMAP: Part 1 done pending device checks; Part 2 waits for the same-podcast measurement (spec 8.4).
- [ ] **Step 4:** `swift test`; commit `docs: meeting speakers checklist, tuning, handoff`.
