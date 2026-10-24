# Cleanup fidelity execution log

Scope authorized for this session: Tasks 1 and 2 only. Tasks 3–7 remain pending.
No app launch, synthetic input, history replay, push or merge.

## Task 1 — numbers

Implemented the planned interfaces, number-word candidates, digit normalization,
placeholder/list-marker exclusion and per-sentence correction markers.
TDD: the 12 specified tests first failed to compile because FidelityCheck did
not exist, then all passed. Full `swift test`: 1,232 VoiceCore + 30 MCPKit +
114 BugVoiceMac = 1,376 passing tests.
Commit: `26f0655` — `feat(core): fidelity check for numbers`.

## Task 2 — negations, paths, identifiers and corpus

Implemented all three kinds, deterministic kind/token ordering, punctuation and
Markdown trimming, exact case with the planned sentence-start exception, and
correction-marker reuse. Path tokens are classified as paths rather than also
reporting their internal capitals as identifiers.

TDD: the specified tests plus the 60-pair corpus (30 passing, 30 flagging,
including all twelve mockup rows verbatim) first failed with 31 expectation
failures. They then passed. Added passing boundary checks for sentence-scoped
corrections, identifier case, negation boundaries/counts and multilingual number
composition. The isolated timing test exposed a cold-call failure (5.72 ms);
optimized repeated token classification, sentence-context scanning and the
no-correction path without changing the assertion. The isolated test now passes.

Final `swift test`: 1,251 VoiceCore + 30 MCPKit + 114 BugVoiceMac = **1,395**
passing tests. The fidelity suites contain 31 test functions, with 60 corpus
arguments and nine additional number-composition arguments.
Commit: `feat(core): fidelity check for negations, paths and identifiers`
(see branch history).

### Timing

Standalone unoptimized Swift build, the plan's exact 200-word input, comparing
identical raw and cleaned strings: **4.571 ms cold**, **1.029 ms median** and
**1.379 ms maximum** over 100 warm runs. The temporary measurement harness first
had an incorrect word-count precondition; corrected it to 200 before measuring.
No app was launched. These are pure-check timings, not end-to-end dictation.

### Deferred work

Tasks 3–7 have not started. History replay counts, flags and false-alarm rates
per kind are **not measured** (Task 7). Task 6 screenshots and owner checks F1–F8
remain pending; the feature is not yet wired into the pipeline or UI.

## Departures

- The plan header's required Superpowers skill is waived by the owner; direct
  execution authorized. Tasks 3–7 deferred at the owner's request.
- No code-location discrepancies encountered in Tasks 1–2 (new files).

- Added this partial execution log during Tasks 1–2 so TDD and timing evidence
  survives the requested stopping point; Task 7 will complete it.
- No test assertions or planned interfaces changed.
