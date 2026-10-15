# Insights — Design

Date: 2026-10-15. Roadmap item 1 (`docs/ROADMAP.md`).
Mockups: `docs/design/proposal-insights-page.html` (page),
`docs/design/proposal-insights-storage.html` (storage decision).

## 1. Goal

A new **Insights** page that shows how the user speaks with BugVoice over time:
words, speed, dictations, streak, notes, meetings, cleanup fixes, a 52-week
activity heatmap, and where dictation goes (apps and styles). Numbers are
calculated and stored on this Mac only.

Success: open Insights and see true numbers at a glance, in light and dark, for
All time / 30 days / 7 days; the numbers survive history retention and Clear
history.

### Out of scope

- Details tab content (peak time, top topics, most used words). The tab bar is
  built for it; the tab itself is shown disabled with a "Later" label.
- Leaderboard, sharing, mobile, sync. The storage badge reads **Local**; a
  future sync feature changes it to **Cloud**.
- "Time saved" (needs a guessed typing speed).

## 2. Page

Layout follows `docs/design/proposal-insights-page.html`.

### 2.1 Window chrome (all pages)

- The title bar is transparent and shows no title text. The sidebar runs the
  full window height; the traffic-light buttons sit on the sidebar.
- The detail column keeps a toolbar row with the page name (e.g. "Insights").
- The sidebar header with the app icon, "BugVoice" and the "Local" chip is
  removed; the storage badge moves into pages that need it.

### 2.2 Sidebar

New `Page.insights`, title "Insights", SF Symbol `chart.bar`, placed between
Dictation and Meetings.

### 2.3 Header row

- `PillTabs`: **Usage** (selected) and **Details** (disabled, "Later" label).
  `PillTabs` is a reusable rounded segmented control: capsule track, selected
  pill raised on a card-coloured background.
- Period pills (same component, small size): **All time** / **30 days** /
  **7 days**. Default All time. The choice is remembered for the session only.
- Right side: storage badge — desktop icon + "Local".

### 2.4 Cards

Row 1 (four cards):

| Card | Value | Subtitle |
|---|---|---|
| Words spoken | words in period | "All time · N today" / "Last 30 days · N today" |
| Words per minute | words ÷ minutes spoken, in period | "Words ÷ time speaking" |
| Dictations | dictations in period | period label |
| Current streak | "N days" (always all-time, not affected by period) | "Longest: N days" |

Row 2 (three cards):

| Card | Value | Subtitle |
|---|---|---|
| Notes | notes dictated into, in period | "N words spoken into notes" |
| Meetings | meetings recorded, in period | "N.N hours recorded" |
| Cleanup fixes | words changed by the text model, in period | "Words changed by the text model" |

Zero values show `0`; WPM shows `0` when no seconds were recorded.

### 2.5 Speaking activity

- 52 weeks ending today, one column per week starting Sunday, rows Sun–Sat;
  month labels above, Mon / Wed / Fri labels on the left.
- Cell colour by words that day, fixed thresholds:
  0 → level 0, 1–149 → 1, 150–299 → 2, 300–479 → 3, 480+ → 4.
- When the period is 30 or 7 days, cells outside the period are dimmed.
- Hover shows "Oct 15: 412 words · 23 dictations" or "Oct 15: no dictation".
- The heatmap is always 52 weeks regardless of period.

### 2.6 Breakdown

Two panels side by side:

- **Where you dictate**: top 5 apps by words in period, plus "Other" when more
  apps exist; bar length relative to the top app; words on the right; header
  shows "N apps".
- **By style**: terminal / other / document (every `Style` case with words),
  bar + percentage of words in period.

Empty period: both panels show "No dictation in this period."

### 2.7 Footer

None.

## 3. Data

### 3.1 File

`~/Library/Application Support/BugVoice/insights.json` (`AppPaths.insights`).
Numbers and app names only — never dictated text.

```json
{
  "schemaVersion": 1,
  "backfilledFromHistory": true,
  "days": {
    "2026-10-15": {
      "words": 412, "dictations": 23, "secondsSpoken": 291.4,
      "notes": 1, "noteIDs": ["9F2C…"], "noteWords": 140,
      "meetings": 0, "meetingSeconds": 0,
      "wordsByApp": { "Ghostty": 210, "Code": 120, "Notion": 82 },
      "wordsByStyle": { "terminal": 210, "other": 120, "document": 82 },
      "cleanupFixes": 37
    }
  }
}
```

Day keys use the Mac's current calendar and time zone at the moment the event
is recorded (`yyyy-MM-dd`). An app with no name is stored as "Unknown".

### 3.2 What counts

| Event | Adds |
|---|---|
| Dictation with outcome `inserted` or `copiedNotConsumed` | words (of the inserted text), 1 dictation, recording seconds, words to its app and style, cleanup fixes |
| Dictation with outcome `insertedInNote` | noteWords; `notes` +1 the first time that note is dictated into that day; recording seconds and 1 dictation also count |
| Dictation with outcome `copiedSecureField` | nothing (no words of a secret are measured) |
| Any other outcome (too short, nothing heard, failed, cancelled, note deleted, note save failed) | nothing |
| Meeting stop (success or transcript failure, audio saved) | 1 meeting, its recorded duration in seconds |

Words = whitespace-separated tokens of the inserted text (same rule as
`HistoryEntry.wordCount`). Vietnamese syllables each count as a word.

Cleanup fixes = word-level edit distance between `raw` and `cleaned` when
`cleaned` exists; 0 otherwise. `WordErrorRate` gains a public
`editDistance(reference:hypothesis:) -> Int` that `compute` reuses.

Insights records **before** the history retention check, so it counts when
retention is "Don't save".

To count `notes` once per note per day, `InsightsDay` stores `noteIDs: [String]`
for that day (note identifiers only, no titles or text); `notes` is its count.

### 3.3 Backfill

On launch, if `backfilledFromHistory` is false (or the file is missing), every
entry in `history.jsonl` is added by the same rules, then the flag is set. It
runs once; Reset insights sets the flag to true so a reset is not undone by a
backfill. Meetings are not backfilled.

### 3.4 Reset and clear

- Settings → Storage: **Reset insights** button with confirmation "Reset
  insights? Words, streak and activity go back to zero. Dictation history is
  not affected." Buttons: Reset / Cancel.
- Clear history, deleting one history entry and retention pruning do not change
  Insights.

### 3.5 Errors

- Unreadable or undecodable file: rename to `insights.corrupt-<timestamp>.json`,
  start empty with `backfilledFromHistory = false` (so history refills it), and
  show the existing "Could not save" alert once with "Insights file was damaged
  and has been rebuilt from history."
- `schemaVersion` newer than supported: do not overwrite; the page shows
  "Insights were saved by a newer BugVoice." and recording is skipped.
- Write failure: `saveError` "Could not save insights: …". The dictation itself
  is never affected.

## 4. Components

### 4.1 VoiceCore (Foundation only, TDD)

| Unit | Responsibility |
|---|---|
| `InsightsDay` | Codable day record (§3.1), `merge(_:)` adds another day's counts. |
| `InsightsDelta` | What one event adds. `InsightsDelta.dictation(_ result: DictationResult, noteID:)` and `.meeting(seconds:)` apply the §3.2 rules; returns nil when nothing counts. |
| `InsightsFile` | Codable root: `schemaVersion`, `backfilledFromHistory`, `days`. |
| `InsightsStore` (actor) | `load()`, `add(_ delta:, at: Date)`, `backfill(from: [HistoryEntry])`, `reset()`. Atomic write (temp file + rename). Corrupt/newer-version handling per §3.5. |
| `InsightsPeriod` | `.all`, `.days30`, `.days7`. |
| `InsightsSummary` | `compute(file:, period:, today:, calendar:)` → card values, current and longest streak, 52-week heatmap cells (date, words, dictations, level, inPeriod), top apps (5 + Other), style shares. Pure. |
| `HeatLevel` | `level(forWords:)` with the §2.5 thresholds. |

Streak: count consecutive days with any activity (words > 0, notes > 0 or
meetings > 0) ending today; if today has none, end at yesterday. Longest is the
longest such run in the file.

### 4.2 App

| Change | Where |
|---|---|
| `AppPaths.insights` | `Sources/VoiceCore/AppPaths.swift` |
| `AppModel.insightsStore`, `insights: InsightsFile` (observable), `recordInsights(_:)`, `resetInsights()`, backfill at launch | `Sources/BugVoice/AppModel.swift` |
| `record(_:)` calls insights before the retention guard; Notes path passes the note id | `AppModel.swift`, `DictationController.swift` |
| `MeetingController.stop()` records the meeting | `Sources/BugVoice/MeetingController.swift` |
| `Page.insights` | `AppModel.swift`, `MainWindow.swift` |
| Window chrome (§2.1) | `MainWindow.swift` |
| `InsightsPage`, `PillTabs`, `StatCard`, `ActivityHeatmap` (Canvas + hover), `BreakdownBars` | `Sources/BugVoice/UI/Insights/` |
| Reset insights | `Sources/BugVoice/UI/Settings/StorageTab.swift` |

## 5. Testing

VoiceCore tests (written first):

- `InsightsDelta`: each outcome row of §3.2; secure field adds nothing; cleanup
  fixes from raw vs cleaned; nil app → "Unknown"; note counted once per day.
- `InsightsStore`: add to new and existing day; day key in a given time zone;
  reset; backfill once; reset blocks backfill; corrupt file renamed and
  rebuilt; newer schema not overwritten; round-trip encode/decode.
- `InsightsSummary`: each period; WPM with zero seconds; streak with gaps, with
  today empty, with only a meeting; longest streak; 52-week grid starts on
  Sunday and ends today; inPeriod flags; top 5 + Other; style shares sum to 100.
- `HeatLevel`: boundaries 0, 1, 149, 150, 299, 300, 479, 480.
- `WordErrorRate.editDistance`: identical, insert, delete, substitute.

Manual checklist (append to `docs/testing/manual-checklist.md`):

| # | Check |
|---|---|
| 73 | Insights opens from the sidebar; cards, heatmap, breakdown render in light and dark |
| 74 | Period switch changes cards and breakdown; heatmap dims outside the period; streak unchanged |
| 75 | Dictate in two apps; numbers, today's heatmap cell and app bars update without reopening |
| 76 | Dictate into a note; Notes card counts it once; history unchanged |
| 77 | Record a short meeting; Meetings card and hours update |
| 78 | Clear history; Insights unchanged |
| 79 | Reset insights; everything zero; relaunch does not refill from history |
| 80 | Window chrome: no title text, sidebar full height on every page |
