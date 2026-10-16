# Meetings v2 (5a): meeting detection and the meeting window — design

Date: 2026-10-16. Roadmap item 5, first sub-project. Follows Meetings (sub-project 2) and the
system-audio fix `acca0b2` (Others track now records; spike passed on device 2026-10-16).
Mockup: `docs/design/proposal-meeting-window-final.html` (states: My notes, Transcript,
Summary, Collapsed, What did I miss? answer, Meeting detected and Meeting ended popups, meeting
detail page; light and dark). The comparison that chose the layout:
`docs/design/proposal-meeting-window.html` (option A, one window).

## 1. Goal

Never forget to record a meeting, take your own notes beside the live transcript, and read a
running summary while the meeting goes on.

What the owner said and confirmed:

- Must have: a popup when a meeting starts (A), and personal notes during the meeting that the
  summary uses (C). As in Wispr Flow and Granola: one floating window with three tabs, live
  transcript, my notes, summary, and an Ask anything box at the bottom.
- The window is docked to the right third of the screen, full height, so the meeting keeps the
  other two thirds. It replaces today's recorder panel and can collapse to its top bar.
- The summary refreshes during the meeting (live) and is rewritten when the meeting stops.
- Ask anything answers from this meeting only. Asking across past meetings and notes is roadmap
  item 6.
- The popup only offers; it never starts recording by itself.
- Notes live with the meeting, not as a Scratchpad note.

Not in scope (later sub-projects):

- Ask AI across meetings, notes and dictations, and the Scratchpad AI source picker
  (This note / This folder / All folders): roadmap item 6.
- Live English translation in the Transcript tab (5b), for the monthly Spanish and English
  meeting.
- Attendee names: needs the calendar (roadmap item 7). Speaker names (diarization) stay deferred.

## 2. Meeting detection

### 2.1 Signal

BugVoice watches which processes use audio input. Core Audio lists processes
(`kAudioHardwarePropertyProcessObjectList`); each process object reports its PID, bundle ID
and whether it is running input (`kAudioProcessPropertyIsRunningInput`). BugVoice listens for
changes to the list and to each process's input flag; it does not poll.

A process counts as a meeting when it starts input and:

- its bundle ID is a meeting app: Zoom `us.zoom.xos`, Microsoft Teams `com.microsoft.teams2`
  and `com.microsoft.teams`, Slack `com.tinyspeck.slackmacgap`, FaceTime `com.apple.FaceTime`,
  Webex `Cisco-Systems.Spark`, Discord `com.hnc.Discord`; or
- its bundle ID is a browser (Chrome `com.google.Chrome`, Safari `com.apple.Safari`, Arc
  `company.thebrowser.Browser`, Edge `com.microsoft.edgemac`, Firefox `org.mozilla.firefox`,
  Brave `com.brave.Browser`) and one of its window titles matches a web meeting: contains
  `Meet -` or `Meet –` or starts with `Meet:` (Google Meet), contains `Microsoft Teams`, or
  contains `Zoom` with `Meeting`. Window titles are read with the Accessibility permission
  BugVoice already has (`kAXWindowsAttribute`, `kAXTitleAttribute`).

Browser helper processes (for example `com.google.Chrome.helper`) map to their browser by
bundle ID prefix. BugVoice's own process never counts. Input from a process whose app is in
the muted list (2.3) never counts.

### 2.2 Popup

- **Meeting detected** appears at the top right of the screen with the frontmost window,
  above other windows, without taking focus: app name and the meeting title (from the window
  title with the `Meet - ` / `Meet: ` prefix and browser suffix removed; otherwise the app
  name).
- Buttons: close (×), **Start recording**, and an arrow menu with **Don't ask for this app**.
- It hides after 15 seconds. It does not appear again for the same process until that process
  stops input and starts it again.
- No popup while a meeting is recording, paused or transcribing.
- Two meeting apps at once: one popup, for the first.
- **Meeting ended** appears when the process that triggered the recording stops input for
  10 seconds while BugVoice is recording: "Google Meet stopped using the mic · 42:10",
  **Stop recording**, close. It never stops the recording by itself. It hides after 30 seconds.
- Without Accessibility permission, browsers are skipped and only meeting apps are detected.

### 2.3 Settings › Meetings

- **Detect meetings** switch, on by default.
- **Muted apps** list with Remove buttons, filled by Don't ask for this app.
- Stored in `settings.json` under `meetings`: `detectMeetings: Bool` (default true) and
  `mutedMeetingApps: [String]` (bundle IDs, default empty). Older settings decode with the
  defaults.

## 3. Meeting window

### 3.1 Placement and focus

- One window replaces `MeetingRecorderPanel`. It opens when a meeting starts from the popup,
  the menu, ⌃⌥M or the Meetings page, and when a recovered meeting is transcribing.
- First open: right third of the visible frame of the screen the meeting started on, full
  height, 12 pt inset. The owner can move and resize it; frame saved in settings
  (`meetings.windowFrame`) and restored next time if it fits a screen.
- Floats above other windows on all Spaces, like the Scratchpad window (`ScratchpadPanel`
  pattern: `NSPanel`, `.nonactivatingPanel`, `canBecomeKey` true, `hidesOnDeactivate` false).
- Clicking Mark, Pause, Resume, Stop, the tabs, the language chip or Collapse does not take
  keyboard focus from the meeting app. Clicking into My notes or the Ask box makes the window
  key; clicking back into the meeting app returns focus.
- **Collapse** (chevron, top right) leaves only the top bar: red dot, Recording / Paused /
  Transcribing N%, timer, expand chevron. Collapsed state is saved.

### 3.2 Layout (top to bottom)

1. **Top bar:** state dot and label, timer, Collapse.
2. **Header:** meeting title (editable, saved on Return or focus loss), start time chip, Add
   folder chip (existing folder picker), language chip (existing `toggleLanguage`).
3. **Meters row:** You and Others level bars, then Mark and Pause/Resume on the right.
   Mark shows "Marked at 12:47" in the mark colour for 2 seconds.
4. **Tabs:** My notes (default), Transcript, Summary.
5. **Answer card** (only after Ask; see 5).
6. **Dock:** "Recording stays on this Mac. Tell people you are recording.", then **Stop** and
   the **Ask anything about this meeting** box with **What did I miss?** inside it.

### 3.3 My notes tab

- Markdown editor using the Notes editor view (`NotesTextView`, ⌘Z/⌘⇧Z on its own undo
  manager, Tab indent on list lines). Placeholder: "Write your notes. The summary follows your
  headings."
- Holding Right Option while the notes editor has focus dictates into it at the cursor, the
  same routing the Scratchpad window uses (`NSApp.keyWindow` identifier check in
  `AppModel.captureNotesDictation`), with a new window identifier `AppWindow.meeting`.
- Saved to the meeting 1 second after typing stops, on tab switch, and at Stop.

### 3.4 Transcript tab

- Live lines from the existing interim results (30-second pieces): time, You / Others, text.
- Marks show as a line "Mark · 11:52" at their offset.
- Auto-scrolls to the newest line unless scrolled up; a "Newest" button returns.
- Bar at the top: elapsed time, Search (filters lines), Copy (copies the transcript as
  `[mm:ss] You: text` lines).
- "Listening…" under the last line while recording.

### 3.5 Summary tab

- Live summary (4) with "So far · updated N min ago · next in N min" above it.
- Before the first refresh: "The first summary comes after 3 minutes of talk."
- Errors: see 9.

### 3.6 After Stop

- The window stays open, top bar shows "Transcribing N%", tabs stay usable.
- When transcription finishes, the final summary is generated (4.3), then the window shows the
  finished meeting: tabs keep working, the dock shows **Open in Meetings** and **Close**
  instead of Stop and Ask.

## 4. Live summary

### 4.1 When

- The first refresh runs when the meeting has at least 3 minutes of active (unpaused) time
  and at least one transcript line. Then every 3 minutes of active time, only when there are
  transcript lines newer than the last refresh or the notes changed.
- A refresh never runs while another refresh for this meeting is running.
- Refreshes use the Meeting notes model (models per feature). They wait behind dictation
  cleanup on the same model; dictation always goes first.

### 4.2 Request

`LiveSummaryPlanner` (VoiceCore) builds a `CleanupRequest`:

- System prompt: update a running meeting summary; keep the user's note headings and order
  when the notes have headings; short bullets; decisions and open questions; no invented facts;
  same language as the transcript.
- User text: previous summary (or "None yet"), the notes, then only transcript lines with
  `end` after the last refresh's cutoff, as `[mm:ss] You: text` / `[mm:ss] Others: text`.
- New lines are capped to fit `meetings.generationContextTokens` minus the output budget;
  when they do not fit, the oldest new lines are dropped and the cutoff moves past them.
- Output limit: `meetings.generationOutputTokens`.

The result replaces `liveSummary` on the meeting with `liveSummaryUpdatedAt` and the new
cutoff `liveSummaryCutoff` (seconds of meeting time).

### 4.3 Final summary at Stop

- After final transcription, BugVoice generates the summary with the existing
  `MeetingTextGenerator` (parts and merge), with the notes added to the request ("Follow the
  user's notes: keep their headings and order; fill in details from the transcript").
- The result is saved to `summary` as today; `liveSummary` stays for reference but the
  Summary tab and the detail page show `summary` once it exists.
- Action items are not generated automatically (unchanged).
- If no Meeting notes model is set, no summary is generated; the detail page shows the
  existing Generate button.

## 5. Ask anything (this meeting)

- The box sends a question with this meeting's transcript so far and the notes, through the
  Meeting notes model. Request built by `MeetingQuestion` (VoiceCore): system prompt answers
  only from the transcript and notes, says so when the answer is not there, cites times as
  `[mm:ss]`; transcript capped like 4.2, keeping the newest lines.
- **What did I miss?** asks "What was said in the last 5 minutes?" over lines with `end`
  in the last 5 minutes of active time.
- The answer appears in a card above the dock: the question (small, grey), the answer, and
  **Add to notes** (appends `**Q:** question` and the answer to My notes), **Copy**, **Close**.
  One card at a time; a new question replaces it. Return sends; ⎋ closes the card.
- Answers are not saved with the meeting.

## 6. Marks

- Mark gives feedback (3.2) and shows in the Transcript tab (3.4).
- Meeting detail page: marks show as ticks on the playback timeline and as mark lines in the
  Transcript tab; clicking either plays from the mark.

## 7. Meeting detail page

- New **My notes** tab after Action items, showing the notes as Markdown (read and edit, same
  editor, saved like 3.3). Empty: "No notes for this meeting."
- Markdown export adds a `## My notes` section after the summary when notes exist.
- Send to Scratchpad gains **My notes** as a choice next to Summary and Action items.

## 8. Data

`MeetingManifest` gains, all optional on decode for older meetings:

- `notes: String` (Markdown, default "").
- `liveSummary: String?`, `liveSummaryUpdatedAt: Date?`, `liveSummaryCutoff: TimeInterval`
  (default 0).
- `detectedApp: String?` (bundle ID of the app that triggered the popup, for Meeting ended).

`MeetingSession` gains `setNotes(_:)` and `setLiveSummary(_:updatedAt:cutoff:)`, both allowed
while recording, paused, transcribing or ready, and saved through the store like `rename`.
Crash recovery keeps notes because they are saved within a second of typing.

## 9. Errors

- No Meeting notes model, or the model is unreachable: the Summary tab says "Summary needs a
  Meeting notes model." with **Open Settings**; Ask shows the same in the answer card.
  Recording and transcription continue.
- A refresh fails after one or more good ones: the last summary stays with "Not updated:
  model unavailable"; the next refresh retries.
- Accessibility not granted: Settings › Meetings shows "Browser meetings need Accessibility
  access." with **Open Settings**; meeting apps are still detected.
- Core Audio process listing fails: detection is off for this run; Settings shows "Meeting
  detection is not available." Recording by hand still works.
- Notes save fails: the notes stay in the editor and the tab shows "Could not save notes";
  the next save retries.

## 10. Copy rules

Plain English, no hedging, no emoji. Strings as written in this spec and the mockup.

## 11. Tests (VoiceCore, TDD)

- `MeetingDetector`: meeting app input starts a meeting event; browser input counts only with
  a matching title (Meet, Teams, Zoom web) and not with others; helper bundle IDs map to
  their browser; own PID ignored; muted apps ignored; no event while recording; one event for
  two apps; input stop for 10 s gives an ended event only for the triggering app; restarting
  input after a dismiss gives a new event; title cleanup (`Meet - Helpdesk bot sync - Google
  Chrome` gives `Helpdesk bot sync`).
- `LiveSummaryPlanner`: no refresh before 3 active minutes; refresh at 3 and 6 minutes with
  new lines; none without new lines or note changes; paused time does not count; request holds
  previous summary, notes and only lines after the cutoff; oversize new lines drop oldest and
  move the cutoff.
- `MeetingQuestion`: request holds the notes and capped transcript; What did I miss? keeps
  only the last 5 active minutes; empty transcript gives a request that says no lines yet.
- Manifest: notes, live summary fields and detectedApp round-trip; a manifest without them
  decodes with defaults.
- Session: `setNotes` and `setLiveSummary` save while recording and after ready; rejected
  after cancel.
- Settings: `detectMeetings`, `mutedMeetingApps`, `windowFrame` decode defaults from older
  settings.
- Export: Markdown includes `## My notes` only when notes exist.

Device checks (manual checklist): popup for Meet in Chrome, Zoom, Teams; no popup for a
browser tab using the mic without a meeting title; Don't ask for this app; Meeting ended
offer; window docks right third and restores a moved frame; Mark and tab clicks keep focus in
Meet; typing in My notes and dictating with Right Option; live summary appears after
3 minutes and updates; Ask and What did I miss?; final summary follows note headings; notes
and marks on the detail page; crash during a meeting keeps notes.
