# Failed dictations — design (2026-10-27)

Mockup: `docs/design/proposal-failed-dictations.html`.
Source: review item P2 "Retry audio is a single `last.wav`" in
`docs/research/2026-10-27-app-review-and-improvement-plan.md` (Phase 2, reduced scope).

## Problem

When transcription fails, the only copy of the audio is `last.wav`. The next
dictation overwrites it, so a failure followed by any other dictation loses the
recording. A failed run also leaves no trace in the app.

## Behavior

- An ordinary dictation whose outcome is `transcriptionFailed` keeps its audio in
  `Application Support/BugVoice/Failed/<id>.wav` with a `<id>.json` record (time,
  app name, bundle ID, length, reason).
- Never kept: runs that started in a secure field, Notes and meeting-notes runs,
  and any run while *Keep dictation history* is Off. Turning history Off deletes
  every kept recording.
- Limits: at most 5 recordings, each kept 24 hours. Oldest goes first. Expired and
  orphaned files are removed on load and on every save.
- Folder 0700, files 0600, written atomically. Not included in backups.
- The Dictation page shows a *Needs attention* section above the stat tiles while
  any recording is kept: time, app, length, reason, Retry, Delete.
- Retry runs the normal pipeline with the original app's style and language
  routing, but the result is only copied to the clipboard, never pasted (the user
  is in BugVoice when they press it). The run is recorded in history as usual.
  HUD: "Copied — press ⌘V / text from the retried recording".
- After a retry that produced text or found nothing to say, the kept recording is
  deleted. A retry that fails again keeps it and updates the reason.
- *Retry last* in the menu and `last.wav` are unchanged.
- Settings › Storage lists *Failed recordings* with a count and Clear.

## Out of scope

Crash recovery of runs still processing at quit, opt-in retention of successful
recordings, retry language picker.

## Tests

VoiceCore `FailedDictationStore`: round trip, owner-only modes, newest first,
cap of 5 removes oldest, 24-hour expiry, corrupt record skipped, record without
audio skipped, orphan audio removed, remove and removeAll.
