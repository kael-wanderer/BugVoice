# Meeting prompt quality — 2026-11-02

Device checks on build 376 found two model-quality problems with Qwen3.8-27B
(oMLX): action items listed the topics of a demo as tasks, and the Interview
template judged a product demo as if it were a candidate.

## Change

- Action items: the prompt now defines an action item (a task someone agreed,
  offered, was asked or said they will do after the meeting) and excludes topics
  discussed, features shown and work already done. With none, the model replies
  "No action items"; the parser ignores that line with or without a full stop and
  the meeting tab says "No action items in this meeting."
- Interview: strengths and concerns describe the candidate's answers. With no
  candidate, the summary says "Not an interview." and leaves them out.
- Stand-up: next lists only what a person said they will do.

## Eval

Same prompt shape as the app (system prompt, "Part 1 of 1:" plus the
timestamped transcript, thinking off, temperature 0.2), sent to oMLX on this Mac.
Four transcripts: the 22-minute people-bot demo, and three short written ones
(planning meeting with three assigned tasks, a Swift job interview, a three-person
stand-up). New prompts ran twice.

| Case | Before | After |
|---|---|---|
| Action items, people-bot demo | 8 items, 7 are demo topics | 1 item: share the slide and diagram (both runs) |
| Action items, planning | 3 correct | 3 correct; "dark mode, not now" and "analytics already works" left out |
| Action items, stand-up | 3 | 3, once 2 (An's "I'm writing the refund endpoint" read as in progress) |
| Action items, interview | not run | 1–2: send the take-home, get back after review |
| Interview, people-bot demo | "no candidate" but strengths and concerns about the product | "Not an interview."; strengths and concerns empty or omitted |
| Interview, real interview | not run | candidate, strengths and concerns from her answers |
| Stand-up, both | next mostly stated | next only stated plans |

Owner check: regenerate action items and an Interview summary on a real meeting
and confirm nothing real is missing.
