# Known Voices (Meeting Speakers Part 2) Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking. Executed natively
> by the maintainer session.

**Goal:** BugVoice suggests "Dani?" on a call speaker whose voice matches a voice the owner named
before, and saves voices only on the owner's confirmation.

**Architecture:** Pure matching and contribution bookkeeping in VoiceCore (`KnownVoices`), a
0600 file store (`KnownVoiceStore`), and app wiring in `AppModel+Speakers` after splits and
edits. Suggestions live on `MeetingSpeaker` in `meeting.json`; saved voices in `voices.json`.

**Tech Stack:** Swift 6.4, tools 6.0, macOS 15, Swift Testing, SwiftUI.

**Spec:** `docs/superpowers/specs/2026-10-17-meeting-speakers-design.md` section 8 (with the
2026-10-17 measurement in 8.4), copy in section 10. Mockup: `docs/design/proposal-meeting-speakers.html`
state "Part 2: Dani?" and the Known voices card.

## Global Constraints

- VoiceCore imports Foundation only. No new package.
- Threshold 0.2, margin 0.1 (cosine distance), constants in `KnownVoices`.
- `voices.json` in the Application Support folder: folder 0700, file 0600, written through a
  0600 temp file like `CredentialStore`.
- Nothing saved and nothing suggested while `meetings.suggestKnownVoices` is false. Default true.
- A suggestion is not a name: export, summary, Ask, search keep Other N until Yes.
- Only call-track `sN` speakers with a centroid take part; `you` and `pN` never.
- UI copy from spec section 10; plain English, no emoji.

## Review Focus

1. Split again in a meeting whose voice was deleted in Settings must not recreate the voice.
2. Renaming Dani to David moves the meeting's contribution; clearing removes it; an emptied
   voice disappears from Settings.
3. A meeting deleted by any path stops counting toward "N meetings" after the next list load.
4. Two speakers close to the same saved voice: only the closest gets the suggestion.
5. Turning the switch off hides existing suggestions and stops saving.

---

### Task 1: Data fields

**Files:** Modify `Sources/VoiceCore/Meeting.swift`, `Sources/VoiceCore/Settings.swift`;
Test `Tests/VoiceCoreTests/KnownVoicesTests.swift` (new).

**Produces:**
- `public struct SpeakerSuggestion: Codable, Equatable, Sendable { name: String; distance: Double }`
- `MeetingSpeaker.suggestion: SpeakerSuggestion?` (decodes missing as nil)
- `MeetingManifest.declinedVoices: [String]` (decodes missing as `[]`)
- `MeetingSettings.suggestKnownVoices = true` (decoder default true)

- [ ] Tests: older JSON decodes with `suggestion == nil`, `declinedVoices == []`,
      `suggestKnownVoices == true`; round trip keeps them.
- [ ] Implement; `swift test`; commit `feat(core): known voice fields`.

### Task 2: `KnownVoices` (pure)

**Files:** Create `Sources/VoiceCore/KnownVoices.swift`; Modify `Sources/VoiceCore/MeetingSpeakers.swift`;
Test `Tests/VoiceCoreTests/KnownVoicesTests.swift`.

**Produces:**
```swift
public struct KnownVoice: Codable, Equatable, Sendable, Identifiable {
    public struct Contribution: Codable, Equatable, Sendable { meetingID: MeetingID; centroid: [Float] }
    public var name: String; public var contributions: [Contribution]; public var updatedAt: Date
    public var id: String { name }
    public var voiceprint: [Float]   // element-wise mean of contributions
}
public struct KnownVoiceFile: Codable, Equatable, Sendable { public var voices: [KnownVoice] }
public enum KnownVoices {
    public static let threshold = 0.2
    public static let margin = 0.1
    public static func suggest(in meeting: MeetingManifest, voices: [KnownVoice]) -> MeetingManifest
    public enum Change: Equatable, Sendable { case edit(speakerID: String), split }
    public static func record(_ change: Change, before: MeetingManifest, after: MeetingManifest,
                              in file: KnownVoiceFile, now: Date) -> KnownVoiceFile
    public static func prune(_ file: KnownVoiceFile, keeping meetings: Set<MeetingID>) -> KnownVoiceFile
    public static func delete(name: String, from file: KnownVoiceFile) -> KnownVoiceFile
}
```
`MeetingSpeakers.Edit` gains `.accept(speakerID:)` and `.decline(speakerID:)`.

Rules:
- `suggest`: candidates are `sN` speakers with `name == nil` and a centroid; voices skip names
  (case-insensitive) already shown by a speaker in the meeting or in `declinedVoices`. For each
  candidate, distance to every voiceprint; a pair qualifies when `d <= threshold` and the
  candidate's second-closest voice is at least `margin` farther (or there is none). Assign
  qualifying pairs closest first, one voice per speaker, one speaker per voice. Clears stale
  suggestions on speakers that now have a name; leaves `speakerName` untouched.
- `record(.edit(id))`: confirmed name = speaker name when the speaker is `sN` with a centroid.
  Before and after differ: remove the meeting's contribution under the old name, set it under
  the new name (replace any contribution of that meeting under that name). Voices with no
  contributions are dropped. New voice names are matched case-insensitively to existing ones.
- `record(.split)`: for each confirmed speaker after the split, replace the centroid of an
  existing contribution of this meeting under that name; add nothing. Remove this meeting's
  contributions under names no longer confirmed.
- `.accept(id)`: name = suggestion name (duplicate check as rename), keep `suggestion`.
  `.decline(id)`: append suggestion name to `declinedVoices`, clear `suggestion`.
  `.rename(id, …)` clears `suggestion`.

- [ ] Tests (fail first): closest pair wins with two speakers near one voice; threshold 0.2
      inclusive, 0.21 refused; margin refused at 0.05 apart; named and declined names skipped;
      voiceprint mean; rename moves contribution; clear removes and drops empty voice;
      split replaces existing contribution and adds none; prune; accept keeps suggestion and
      sets name; decline records name and clears; rename clears suggestion; export after
      suggest still says Other 1.
- [ ] Implement; `swift test`; commit `feat(core): match and record known voices`.

### Task 3: `KnownVoiceStore`

**Files:** Create `Sources/VoiceCore/KnownVoiceStore.swift`; Test in `KnownVoicesTests.swift`.

**Produces:** `public actor KnownVoiceStore { init(url: URL); func load() throws -> KnownVoiceFile`
(missing file = empty) `; func update(_ change: @Sendable (KnownVoiceFile) -> KnownVoiceFile) throws -> KnownVoiceFile }`.

- [ ] Tests: missing file loads empty; after update file is 0600 and folder 0700; content
      round-trips.
- [ ] Implement with the `CredentialStore.save` pattern; commit `feat(core): voices.json store`.

### Task 4: App wiring

**Files:** Modify `Sources/BugVoice/AppModel.swift` (store, `knownVoices: [KnownVoice]`, prune
in `reloadMeetings`), `Sources/BugVoice/AppModel+Speakers.swift`, `Sources/BugVoice/AppPaths*`
(`voices` URL beside `credentials.json`).

- After `applySplit` in `performSpeakerSplit`, inside the same `updateMeetingSpeakers` change:
  `KnownVoices.suggest` when the switch is on. Then `record(.split, before:after:)` when on.
- `editMeetingSpeakers`: capture before/after through the change closure; for `.rename`,
  `.accept`, `.newPerson`, `.assign` call `record(.edit(id))` for the edited speaker when on
  (`assign`/`newPerson` change no `sN` names, so record is a no-op for them).
- `deleteKnownVoice(name:)`.
- Switch off: `suggest` not run; the row hides suggestions (Task 5).

- [ ] Build; `swift test`; commit `feat(app): suggest and save known voices`.

### Task 5: UI

**Files:** Modify `Sources/BugVoice/UI/MeetingSpeakersRow.swift`, `Sources/BugVoice/UI/MeetingsPage.swift`
(line label), `Sources/BugVoice/UI/Settings/MeetingsTab.swift`.

- Chip with a suggestion (switch on, `name == nil`): dashed accent border, "Dani?", [Yes]
  (prominent) [No]. Its lines show "Dani?" in the speaker colour.
- Settings › Meetings: card "Known voices": Toggle "Suggest names from known voices"; one row
  per voice: colour dot (index order), name, "N meetings" ("1 meeting"), Delete; caption from
  spec 8.3.

- [ ] Build with `Scripts/build-app.sh`; check states on an upload of a two-voice clip uploaded
      twice (name in the first, see "…?" in the second; Yes, No, Delete, switch off).
- [ ] Commit `feat(app): Dani? suggestions and Known voices settings`.

### Task 6: Docs

- [ ] Checklist rows in `docs/progress/meetings-log.md`, HANDOFF, ROADMAP; commit `docs: known voices`.
