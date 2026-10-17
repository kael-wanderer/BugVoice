# Meetings: speaker names — design

Date: 2026-10-17. Mockup: `docs/design/proposal-meeting-speakers.html` (states: after Stop, finding
speakers, renaming, fixing one line, names set, people changed, Part 2 suggestion, older meeting;
meeting window after Stop; Part 2 Settings card; light and dark).

## 1. Why

A recorded meeting today labels every line You (microphone) or Others (call audio). In a call
with more than one other person (the owner's monthly meeting with Dani and Mariel) the
transcript, export, summary and answers cannot say who said what. The owner wants, after the
meeting:

- the other voices told apart as Other 1, Other 2, …;
- to rename a speaker once for every line ("Other 1" → Dani);
- to fix single lines when the app put two people under one label (two similar voices both
  "Other 1": some lines are Dani, some David);
- the same for uploaded recordings;
- later (Part 2): BugVoice recognises a voice it has heard before and shows "Dani?" for the owner
  to confirm. The owner chose confirm over filling the name in silently.

Success: after a call with two or more guests, the owner opens the meeting, sets the number of
people if it is wrong, types each name once, fixes a few lines, and the transcript, export,
summary (after Regenerate) and Ask all use the names.

## 2. Scope

Two parts, built and shipped separately. Part 2 starts only after Part 1 is merged and the
matching check in section 8.4 passes.

- **Part 1 — speakers and names**: split after Stop and after uploads, People in this meeting,
  rename, fix a line, names everywhere, Find speakers for older meetings.
- **Part 2 — known voices**: save voiceprints of named speakers on this Mac, suggest "Name?" in
  later meetings, Settings › Meetings › Known voices.

Not in scope:

- Speakers during recording. The meeting window keeps You and Others while recording; the split
  runs after Stop.
- Telling voices apart by gender or pitch. (Rejected: unreliable, and not what the owner asked.)
- Splitting one line between two speakers. A line belongs to one speaker; a line that holds two
  voices is fixed by hand. Word-level splitting may come later.
- Rewriting the summary or action items on their own when names change.
- Speakers on the microphone track. Microphone lines are always the owner.

Anti-goals: a guess presented as fact (Part 2 never names a voice without the owner's Yes); any
audio, voiceprint or name leaving this Mac.

## 3. How voices are told apart

- Engine: SpeakerKit (Pyannote v4 "community-1", Core ML), a library product of the package we
  already pin (`argmaxinc/WhisperKit` 1.1.1 is the same commit as `argmax-oss-swift` v1.1.1).
  Add `.product(name: "SpeakerKit", package: "WhisperKit")` to the target that already links
  WhisperKit. No new package. It runs on device.
- Models: `argmaxinc/speakerkit-coreml` on Hugging Face, about 11 MB, CC-BY-4.0, not gated.
  Downloaded on first use into BugVoice's models folder, next to the Whisper models. Add a
  `THIRD_PARTY_NOTICES.md` entry (licence, source, "downloaded at runtime, not redistributed").
- Input audio:
  - Recorded meeting: the call track only (`system.m4a`). Microphone lines stay the owner.
  - Upload, and recorded meetings without `system.m4a` (older meetings): the whole recording
    (`audio.m4a`). The owner is one of the speakers there.
- Speed measured 2026-10-17 on the owner's Mac: 0.4 s for 4 minutes of audio, after the model
  loads.
- Count: SpeakerKit can count voices itself, but in the 4-minute test it found 5 for 2 people,
  and with "2" given it got the clear turns right. So:
  - The first split counts automatically.
  - People in this meeting (section 5.1) is the fix: the split runs again with that number.
  - Recorded meeting: People counts the owner, so the call-track split asks for People − 1.
    Upload: People is passed as is.
  - Test recordings (owner's choice, 2026-10-17): YouTube clips the owner plays while BugVoice
    records, as in the 2026-10-17 tests, with a known number of people (for example 2, 3 and 4)
    and who speaks first noted. If they cannot be had, Part 1 ships with SpeakerKit's defaults
    and the People fix.
  - Before building, tune the automatic count once (SpeakerKit's cluster threshold or minimum
    cluster size) on the owner's recordings; keep whatever gives the closest count. Record the
    chosen values and results in the plan.

## 4. When the split runs

- After Stop: final transcript → speaker split → final summary. The summary is written with the
  Other N labels. If the split fails, the summary still runs with Others.
- After an upload's transcript is done, before its summary.
- After a recovered meeting is finished on next launch, the same as after Stop.
- On demand: Find speakers (older meeting or a failed split) and People in this meeting (−/+).
- While it runs the Transcript tab shows "Finding speakers…" in place of the Speakers row.
- Failure (model download fails, model fails, no call audio): the lines keep You/Others, the
  Speakers row is replaced by "Speakers could not be found." with Try again. No dialog.
- Lines from the meeting's call track that the split could not place (no overlapping voice) keep
  the label Others.

## 5. Meeting detail page, Transcript tab (layout A, chosen by the owner)

### 5.1 Speakers row

Above the transcript, one row (see mockup):

- **People in this meeting**: − N +. Shows the number of speakers that own at least one line
  (You counts in a recorded meeting); a voice the split found but that got no line is dropped and
  not counted. After Split again for N, it shows what the split produced, which can be less than
  N. Range: 1 to 10; in a recorded meeting with call lines the minimum is 2 (You and at least one
  other). Each change asks first:
  "Split again for N people? Your changes to single lines are cleared. Names stay on the voices
  that keep them." [Split again] [Cancel]. "Keep them" means: after the new split, a new speaker
  whose voice is closest (smallest centroid distance, section 8) to an old named speaker takes
  that name, one name per speaker.
- **Speaker chips**, one per speaker in order of first line: You first in recorded meetings, then
  Other 1, Other 2, … Each chip has a colour dot; that speaker's lines use the same colour.
  - Click a chip: it becomes a text field. Return or click away saves; Escape cancels; an empty
    name restores the default label. The name applies to every line of that speaker.
  - The You chip can be renamed too (for example to the owner's name).
  - Two speakers may not share a name: typing a name that another speaker has merges nothing and
    shows "Dani is already a speaker." under the row.

### 5.2 Fix one line

- Click the speaker label on a line: a menu lists every speaker of the meeting (dot and name),
  then "New person…".
- Picking a speaker moves only that line.
- "New person…" asks for a name in a small field and creates a speaker with that name; the line
  moves to it and a new chip appears.
- A speaker left with no lines disappears from the chips.
- In a recorded meeting, microphone lines can be moved too (the owner may know a mic line was
  really a guest heard through the speakers).

### 5.3 Names changed notice

After any rename or line fix, when the meeting has a summary or action items, a notice shows above
the transcript: "Names changed. The summary still uses the old names." [Regenerate summary]
[Not now]. Regenerate runs the existing summary and action items generation. Not now hides the
notice until the next change. The notice is not saved; it is shown again on the next visit only
if the names changed since the last summary (compare a saved `speakerNamesAtSummary` with the
current names).

### 5.4 Older meetings

A recorded meeting or upload with no split shows "This meeting was recorded before speakers were
split." [Find speakers] in place of the Speakers row.

## 6. Everywhere else

- Meeting window after Stop: lines show speaker names and colours, read only. No chips, no
  menus. Open in Meetings leads to the detail page.
- Meeting window while recording: You and Others, as today.
- Markdown export, SubRip captions, Send to Scratchpad, meeting search: the speaker name.
- Summary, action items, Ask, What did I miss, live summary prompts: the speaker name in each
  transcript line (today `segment.speaker`).
- Translation (5b): unchanged; the English line follows its line.
- Upload page: unchanged.

## 7. Data

- `MeetingSegment.speakerID: String?` — nil: the track's default label (You / Others /
  Speaker). Older files decode with nil.
- `MeetingManifest.speakers: [MeetingSpeaker]` — default `[]`; older files decode with `[]`.
  - `MeetingSpeaker { id: String, name: String?, colorIndex: Int, centroid: [Float]? }`
  - `id`: `"you"` for the owner in recorded meetings; `"s1"`, `"s2"`, … for split voices;
    `"p1"`, `"p2"`, … for people made with New person.
  - `name`: nil shows the default label: "You" for `you`, "Other N" for `sN`, the typed name for
    `pN` (always set).
  - `centroid`: SpeakerKit's speaker embedding (`DiarizationResult.speakerCentroidEmbeddings`);
    nil for `you` (no split on the microphone) and `pN`.
- `MeetingManifest.speakerSplit: SpeakerSplitState` — `.none` (default, older files), `.running`,
  `.done`, `.failed(message)`. People is not stored; it is the count of speakers with lines.
  `speakers` holds only speakers with at least one line.
- `MeetingManifest.speakerNamesAtSummary: [String: String]?` — speaker id to display name when the
  summary was last written; for the notice in 5.3.
- Display name for a line: the speaker with `segment.speakerID`, else the track default. One
  function in VoiceCore owns this; every place in section 6 calls it.
- Placing lines (VoiceCore, pure): each line on the split track gets the speaker whose turns
  overlap it the most; a line with no overlap takes the nearest turn within 1 second; otherwise
  nil. Ties go to the earlier turn.
- When the session rebuilds `segments` (transcript merger, final pass), `speakerID` carries over
  the same way translations do (`MeetingTranslation.carryOver`: same track, equal text, start
  within 1 s). The split itself runs after the final pass, so this matters only for a re-run.
- Session/store: setters for speaker names, a line's speaker, new person, and the split result,
  through the meeting window's session while it owns the meeting, otherwise straight to the
  store, the same way as notes and Show English.

## 8. Part 2 — known voices

### 8.1 What is saved

- File `voices.json` in BugVoice's Application Support folder, written like `credentials.json`
  (folder 0700, file 0600). Entries: `{ id, name, centroid: [Float], meetings: Int, updatedAt }`.
- Saved voices are keyed by name: names are unique in `voices.json`, and a name typed on a chip
  that matches a saved voice means that person.
- Each saved voice keeps its contributions, one per meeting: `{ meetingID, centroid }`. Its
  voiceprint is the mean of its contributions, and "N meetings" is their count. So the file is
  `{ name, contributions: [{ meetingID, centroid }], updatedAt }` per voice.
- When the owner sets the name of a split speaker (`sN` with a centroid), by renaming its chip or
  by Yes on a suggestion, that meeting's contribution is set for that name, replacing any earlier
  contribution from the same meeting and speaker. Renaming the chip again (Dani, then David) moves
  the contribution from Dani to David; clearing the name removes it. A voice left with no
  contributions is deleted. Split again carries names over without adding contributions twice.
- Contributions follow the meeting: deleting a meeting removes its contributions.
- `you` and `pN` speakers save nothing (no centroid). Lines fixed one by one do not change any
  voiceprint.
- Nothing is saved while Settings › Meetings › Known voices › "Suggest names from known voices" is
  off. Default on.

### 8.2 Suggestions

- After a split, each `sN` centroid is compared with every saved voice by cosine distance. A pair
  under the threshold (section 8.4) is a match; each saved voice matches at most one speaker,
  closest pairs first.
- A matched chip shows "Dani?" dashed with [Yes] [No]; its lines show "Dani?".
- Yes: the name is set and the voice updated (8.1). No: the chip goes back to Other N and the
  same voice is not suggested again in this meeting.
- A suggestion is not a name: export, summary and Ask use Other N until Yes.

### 8.3 Settings › Meetings › Known voices

- Switch "Suggest names from known voices".
- One row per saved voice: dot, name, "N meetings", Delete. Delete removes it from
  `voices.json`; meetings keep their names.
- Caption: "A voice is saved when you name a speaker and confirm it. Saved voices stay on this
  Mac. Delete one to stop suggesting it."

### 8.4 Before Part 2 is built

SpeakerKit's authors state there is no fixed "same speaker" distance between separate runs.
Measure it first: take two recordings with the same people (owner's choice: two episodes of the
same podcast played from YouTube; the monthly meeting with Dani and Mariel confirms later), split both, compute distances
between same-person and different-person centroids, and pick a threshold that separates them.
If no threshold separates them, Part 2 stops and the owner is told; Part 1 stands on its own.

## 9. Errors and edge cases

- One voice on the call track: one speaker, Other 1. People 2 in a recorded meeting.
- Meeting with no call audio (microphone only): no split; People is 1; the row shows You only.
- Model download needs the internet once; without it the split fails as in section 4.
- A meeting opened in the meeting window while the split runs: the window shows Others until it
  finishes, then the names.
- Deleting a meeting deletes its speakers with it; known voices stay.
- Renaming during a running split: chips are disabled until it finishes.

## 10. Copy

Plain English, no hedging, no emoji. Strings: "People in this meeting", "Speakers",
"Other 1", "You", "New person…", "Finding speakers…", "Speakers could not be found.",
"Try again", "Split again for N people? Your changes to single lines are cleared. Names stay on
the voices that keep them.", "Split again", "Cancel", "Names changed. The summary still uses the
old names.", "Regenerate summary", "Not now", "This meeting was recorded before speakers were
split.", "Find speakers", "Dani is already a speaker.", Part 2: "Known voices", "Suggest names
from known voices", "N meetings", "Delete", the caption in 8.3.

## 11. Tests (VoiceCore, TDD)

- Line placement: most overlap wins; no overlap within 1 s takes the nearest turn; beyond 1 s
  stays nil; ties go to the earlier turn; microphone lines are never placed.
- Display names: default labels, renamed, `pN`, unknown id falls back to the track default.
- Older JSON decodes with `speakerID == nil`, `speakers == []`, `speakerSplit == .none`.
- Rename: applies to all lines of the speaker; empty restores the default; duplicate refused.
- Fix a line, new person, empty speakers removed.
- Split again: names carried to the closest new centroids, one name each; line fixes cleared.
- Export, search and prompts use display names.
- Names changed notice: shown when names differ from `speakerNamesAtSummary`.
- Part 2: matching picks closest pairs, one speaker per voice, threshold respected; running mean
  update; nothing saved when the switch is off; `voices.json` permissions 0600.

## 12. Left to the plan

- Where the SpeakerKit wrapper lives (next to `WhisperKitTranscriber` in `Sources/WhisperEngine`
  is the obvious place) and how it loads and unloads its models.
- Colour palette for speakers (the mockup's six colours, cycling).
- The exact automatic-count tuning values (section 3).
