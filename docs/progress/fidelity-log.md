# Cleanup fidelity execution log

Completed scope: Tasks 1–3 and the review fixes for Tasks 1–2. Tasks 4–7 remain pending.
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

Task 3 is complete. Tasks 4–7 have not started. History replay counts, flags and false-alarm rates
per kind are **not measured** (Task 7). Task 6 screenshots and owner checks F1–F8
remain pending; the feature is not yet wired into the pipeline or UI.

## Departures

- The plan header's required Superpowers skill is waived by the owner; direct
  execution authorized. Tasks 3–7 deferred at the owner's request.
- No code-location discrepancies encountered in Tasks 1–2 (new files).

- Added this partial execution log during Tasks 1–2 so TDD and timing evidence
  survives the requested stopping point; Task 7 will complete it.
- No test assertions or planned interfaces changed.

## Review fixes before Task 3

Owner-requested corrections, committed separately as
`d901bcd` — `fix(core): fidelity check false alarms from review`:

- Digit tokens accept trailing letters (units and clock suffixes), while a
  letter immediately before a digit still excludes it as a number.
- Stripped cleaned list-marker values preserve raw digits in the lost check;
  markers never become invented-number issues.
- Back-to-back repeats of the same negation (case-insensitive, separated by
  whitespace or commas) collapse on both sides before counting.
- Straight and curly possessive suffixes are stripped before path/identifier
  classification and comparison.
- Timing test now warms up once and asserts the median of 20 checks, as directed.

TDD: added all eight requested corpus cases before code changes. The six false
alarms failed; both must-still-flag guards already passed. Eight additional
boundary cases brought the corpus to 76 pairs; the expanded red run reported
11 failures. All passed after implementation. An initial build failed on a
missing generated constant-extraction file; `swift package clean` repaired the
stale build cache before obtaining the behavioral failures.

Full `swift test`: **1,395 passing** (1,251 VoiceCore, 30 MCPKit, 114
BugVoiceMac). Updated standalone timing: **1.091 ms** median of 20 unoptimized
200-word checks after one warm-up call.

### Known miss — intentionally not fixed

"1.5 million" cleaned to "1,500" is not flagged (1,500 also reads as 1.5).

The review changes override the original plan's token and cold-timing rules;
no other test assertions changed.

## Task 3 — pill and tooltip wording

Implemented the exact planned public interfaces: `FidelityCheck.describe`,
`hudTitle` and `hudDetail`. Lost/invented numbers pair in order into one detail;
unpaired numbers, negations, paths and identifiers retain explicit descriptions.
HUD counts description lines, names a single issue by kind and uses the supplied
Paste raw shortcut letter. Actual negation tokens are retained in quoted tooltip
and HUD wording, including Vietnamese.

TDD: the three specified tests plus an extra multi-number/unpaired-detail test
first failed compilation because the functions were missing, then all passed.
The added test covers multiple pairs, an unpaired invented number, an unpaired
lost number, mixed kinds and an empty tooltip list. No assertions were changed.
Final full `swift test`: **1,399 passing** (1,255 VoiceCore, 30 MCPKit,
114 BugVoiceMac); the 76-pair corpus also passes.
Commit: `feat(core): fidelity check wording` (see branch history).
No Task 3 departures. No UI or pipeline wiring performed; that begins in Task 4.
