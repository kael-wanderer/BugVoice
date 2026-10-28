# Readiness card — design (2026-10-28)

Mockup: `docs/design/proposal-readiness.html`.
Source: Phase 5 of `docs/research/2026-10-27-app-review-and-improvement-plan.md`
("compact readiness card … specific repair links").

## Problem

The menu popover shows only the single most important problem. Nothing shows
the whole picture in one place, and nothing says whether the cleanup model's
server can be reached until a dictation falls back to raw text.

## Behavior

First card in Settings › General. Title: "Ready to dictate", "Getting ready"
(only things still loading), or "N item(s) need attention" (counts problems).
Four rows, each a colored dot (with a VoiceOver label), a title, a one-line
state, and at most one button:

| Row | States (dot) | Button |
|---|---|---|
| Permissions | all on (green); "X and Y are off" (amber) | Open permissions → Permissions window |
| Hotkey | "Hold <key> to speak" (green); "<key> is not being watched" (amber) | Try again → retry the hotkey tap |
| Speech model | on device: ready (green), downloading N% / loading (grey), failed (amber); server engine: "Speech server at <url>" (green, not checked) | Retry (failed only) |
| Cleanup model | None: "Off, raw text is pasted" (faint, counts as ready); connection: not checked yet (grey) / server reachable (green) / "<name>: <error>" (amber); Apple Intelligence or CLI: name (green); unavailable: reason (amber) | Choose a model / Check / Check again / Open Models |

- When the card first shows and the dictation connection has not been checked
  this session, it runs the existing connection check (lists models; sends no
  text). "Server reachable" means only that; Models › Send test sentence remains
  the full generation test.
- Pure state logic lives in VoiceCore (`Readiness`), tested; the app maps its
  live state into it.
- Settings search: "Ready to dictate" (setup, status, permissions, readiness).

## Out of scope

Microphone device choice and signal level, a live speech-server check, a
readiness card in the menu popover (its status line already covers the top
problem), large-text and VoiceOver audit of the rest of Settings.
