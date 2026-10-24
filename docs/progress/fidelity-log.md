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

## Whole-word negation wording fix

Owner requested whole-word, lowercased negation tokens before Tasks 4–7.
The exact contraction, capitalized-word and HUD tests first failed with three
assertion failures, then passed. Full `swift test`: 1,400 passing (1,256
VoiceCore, 30 MCPKit, 114 BugVoiceMac).
Commit: `fix(core): negation token is the whole word, lowercased`.

## Task 4 — setting, result, history and pipeline

Added the specified FidelityAction setting with defensive decoding, detailChanged
reason, result/history issue fields and fallback flag. The pipeline compares
protected text against sanitized cleanup, retains the filled cleaned alternative,
and inserts the uncleaned version for raw action. Warn/off retain issues while
accepting cleanup. Secure recall clears issue tokens. Diagnostics record only
ordered distinct kinds.

TDD: planned tests (with full bodies) plus Notes and protected Dictionary/snippet
coverage failed on missing members before implementation. Full `swift test`:
**1,411 passing** (1,267 VoiceCore, 30 MCPKit, 114 BugVoiceMac).
Commit: `feat(core): run fidelity check before paste`.

Plan adaptation: added an initial detailChanged HUD switch case in Task 4 so the
new RawReason compiles exhaustively in the app target. Task 5 supplies its final
shortcut detail and warn-action handling. No planned interfaces/assertions changed.

## Task 5 — swapping, HUD and popover

The five specified swap tests first failed on missing PasteRawPlan/pasteRawPlan,
then passed. Raw fallback swaps to retained cleaned text and back, preserving
issues; ordinary Paste raw behavior stays the same. Terminal swaps use the
existing trim helper. Controller guards, replacementDecision and secure-field
checks remain on the insertion path. HUD uses configured shortcut letters and
four-second warning timing. The popover offers Cleaned after fallback.
Full `swift test`: **1,416 passing** (1,272 VoiceCore, 30 MCPKit, 114
BugVoiceMac). `swift build` succeeds.
Commit: `feat(app): paste raw swaps to cleaned after a fidelity fallback`.

Plan adaptations: AppModel.replaceLast copies fields individually, so added the
new issue/action fields there to prevent stale metadata after redo/replacement.
Also added the popover's warning tag and tooltip from mockup section 4 while
editing MenuSections (the task text only explicitly named its button label).
No app launch, synthetic events or pastes.

## Task 6 — History and Style UI

Added the global fidelity action card above the Style pills with the exact
picker options and footnote. History displays one warning tag, a tooltip headed
Cleanup changed, and the alternate-version button before Paste again. History
metadata uses a wider column when a fidelity tag is present so it fits beside
the app name. Its existing plain-raw tag whitelist already excluded detailChanged.

`swift build` and `Scripts/build-app.sh` both succeed. Release app assembled at
`build/BugVoice.app`, signed with **Bugler Local Dev**; no app launch or install.
Full `swift test`: **1,416 passing** (1,272 VoiceCore, 30 MCPKit,
114 BugVoiceMac).
Commit: `feat(app): fidelity tag in history and setting on the Style page`.

### Owner screenshots and visual checks — not performed

- [ ] Style page: screenshot the card above the style pills; compare label,
  options and footnote with mockup section 3, including light/dark and large text.
- [ ] History: screenshot fallback and warned/off entries; compare warning tags,
  hover descriptions and swap-button placement with mockup section 4.
- [ ] Popover: inspect Cleaned/Raw labels and shortcut help, plus warning tag,
  against mockup section 4.
- [ ] HUD: inspect wording, configured shortcut hint and four-second warning
  duration against mockup section 2.

Screenshots and device checks were deferred as explicitly required by the owner;
no run-dev-app.sh, bare open, synthetic events or pastes were used.
