# Cancel a dictation while it is processing — design (2026-10-28)

Source: Codex review `docs/research/2026-10-27-app-review-and-improvement-plan.md`,
Phase 1D (“retain the processing task and propagate cancellation”).
Mockup: `docs/design/proposal-cancel-processing.html`.

## Problem

Once the hotkey is released, a dictation cannot be stopped. A slow cleanup model
or a wrong recording still ends in a paste. Hotkey presses are ignored while a
run is busy.

There is also a hidden gap in `DictationPipeline`: if the run's task were
cancelled during cleanup, the model's cancellation error is treated like any
model error, so the raw text would still be pasted. Nothing cancels the task
today, so the gap has never shown, but it blocks any cancel feature.

## Behavior

- While the HUD shows **Transcribing** or **Cleaning**, pressing Esc cancels the
  run. Nothing is pasted, copied, added to a note, or saved to history or
  Insights. A failed-recording entry is not created.
- The HUD shows `Cancelled` right away (1.2 s), with one detail:
  - ordinary dictation or Retry last: “nothing was pasted · Retry last runs it again”
    (`last.wav` still holds the clip);
  - started in a secure field, or Retry on a kept failed recording: “nothing was pasted”;
  - into a note or meeting notes: “nothing was added”;
  - Redo in the other language: “nothing was replaced”.
- Both processing pills end with “Esc to cancel”, matching the command-mode
  Rewriting pill. Command mode also shows Transcribing, and Esc already cancels
  it there, so the hint is right for both.
- Retrying a kept failed recording and cancelling it keeps the entry.
- Once the Inserting stage begins, Esc does nothing: the paste goes ahead.

Same as command mode: the hotkey tap is listen-only, so Esc also reaches the
app in front. Esc marked with `FixLast.syntheticEventMarker` (BugVoice's own
events) is ignored.

## Design

`VoiceCore` (TDD):

- `DictationPipeline.run` checks `Task.isCancelled` twice: after a usable
  transcript (skips cleanup when the engine finished despite a cancel) and just
  before Insert (covers a cancel during cleanup, whose error became raw text).
  Both set outcome `.cancelled` and return. `.cancelled` already has no history
  entry and no Insights count.

App (`DictationController`, `HUDView`):

- `processingTask` keeps the pipeline task of `process()` and of the redo run.
- `keyDownObserved`: key code 53, not synthetic, and `stagedRun != nil` →
  `cancelProcessing(run:)`: remember `cancelledRun`, clear `stagedRun`, cancel
  the task, show the Cancelled message. `stagedRun` becomes nil when the
  Inserting stage starts, so a late Esc does nothing.
- When the run returns `.cancelled` and it is the cancelled run, the HUD is left
  showing Cancelled; any other `.cancelled` hides it as before. If the run
  returns something else (Esc raced the paste), its usual HUD state shows.

## Not in scope

Esc to cancel a hands-free recording; a clickable HUD; cancel from the menu
popover; cancelling meeting or upload jobs.

## Tests

- `cancelDuringCleanupPastesNothing`: model sleeping 5 s, cancel once it has the
  request: `.cancelled`, model saw the cancel, nothing inserted or copied, no
  history entry.
- `cancelBeforeCleanupSkipsTheModel`: task cancelled up front, transcriber
  ignores it: `.cancelled`, no model request, nothing inserted or copied.
- `cancelledNotesRunAddsNothing`: same in notes mode.

Owner device check: dictate a long sentence into Notion with a slow model, press Esc during
Cleaning: Cancelled shows, no text, nothing new in History; Retry last pastes it.
