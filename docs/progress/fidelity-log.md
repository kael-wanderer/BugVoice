# Cleanup fidelity execution log

Implementation: Tasks 1–7 and both requested review fixes complete on `feat/cleanup-fidelity`.
Owner screenshots and device checks remain open.
No app launch, synthetic input, push or merge. History replay was local and read-only.

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

Tasks 1–7 are implemented and verified as recorded below. Task 6 screenshots
and owner checks F1–F8 remain pending. The pipeline and UI are wired.

## Departures

- The plan header's required Superpowers skill is waived by the owner; direct
  execution authorized. The initial turn stopped after Task 2 as requested; later
  turns authorized the remaining tasks.
- No code-location discrepancies encountered in Tasks 1–2 (new files).

- Added this partial execution log during Tasks 1–2 so TDD and timing evidence
  survived the requested stopping point; Task 7 completed it.
- At the original Task 1–2 stopping point, no test assertions or planned interfaces changed.

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
No Task 3 departures. At the Task 3 commit, UI and pipeline wiring remained for Task 4 onward.

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

## Task 7 — history replay and final verification

Added `bugvoice-bench --fidelity-history <path>` before clip discovery/model
loading. It reads through HistoryLog and prints decoded/checked/flagged counts,
percent flagged, distinct flagged-entry counts by kind, and each flagged pair to
stdout only. No replay text is saved. Synthetic CLI verification checked both
counts/pair output and missing-path usage; its synthetic temporary file was
removed. Added the plan/log pointers to AGENTS.md and a status entry to HANDOFF.md.
Commit: `docs: fidelity check log and history replay` (this Task 7 commit).

### Local history results — 2026-10-24

AppPaths.standard().history resolves to
`~/Library/Application Support/BugVoice/history.jsonl` on this Mac. All 17 JSONL
entries decoded; 14 have cleaned text and were checked, 3 do not. There are no
Command entries. Replay was run again after the final checker change with the
same result. **0 flagged / 14 checked (0.00%)**; no flagged pairs to review.

Counts below are distinct entries per kind. False-alarm rate uses all 14 checked
entries as its denominator; the kinds can overlap in other replays.

| Kind | Flagged | True alarms | False alarms | False alarms / checked |
|---|---:|---:|---:|---:|
| Number | 0 | 0 | 0 | 0 / 14 (0.00%) |
| Negation | 0 | 0 | 0 | 0 / 14 (0.00%) |
| Path | 0 | 0 | 0 | 0 / 14 (0.00%) |
| Identifier | 0 | 0 | 0 | 0 / 14 (0.00%) |

No threshold tuning or default change was needed: **fidelityAction remains raw**.
This is a 14-entry sample, not a population estimate or proof of detection recall.
No dictated text was added to the corpus, Diagnostics or documentation.

### Additional final-review correction

Whole-word expansion can make two regex negation matches overlap in an
apostrophe-linked word. Added an isolated regression test first: it reproduced
a fatal range-bounds failure. Then skipped already-consumed whole-word ranges;
the test and full suite pass. This robustness fix was found in code review,
not in the history replay, and is the only Task 7 checker change. The previously
recorded decimal/million ambiguity remains intentionally unchanged.

### Final automated evidence

- `swift test`: **1,417 passing** — 1,273 VoiceCore, 30 MCPKit, 114 BugVoiceMac.
  Fidelity corpus: 76 pairs, plus focused checker, wording, pipeline and swap tests.
- `swift build` and the bench product build succeed.
- `Scripts/build-app.sh`: Task 6 release packaging and the final rebuild after
  the robustness guard both succeeded, signed with **Bugler Local Dev**.
  No app launch or installation was performed.
- 200 words, standalone unoptimized build: **1.052 ms median of 20** checks after
  one warm-up, using the plan's input with numbers, negations, paths and names.
  The updated median timing assertion also passes in the full test suite.

### Commit index

| Task | Commit | Subject |
|---|---|---|
| 1 | `26f0655` | feat(core): fidelity check for numbers |
| 2 | `86cb189` | feat(core): fidelity check for negations, paths and identifiers |
| Review fix | `d901bcd` | fix(core): fidelity check false alarms from review |
| 3 | `19398de` | feat(core): fidelity check wording |
| Wording fix | `4a3fdd6` | fix(core): negation token is the whole word, lowercased |
| 4 | `f511deb` | feat(core): run fidelity check before paste |
| 5 | `a3c3145` | feat(app): paste raw swaps to cleaned after a fidelity fallback |
| 6 | `078f52e` | feat(app): fidelity tag in history and setting on the Style page |
| 7 | This commit | docs: fidelity check log and history replay |

## Plan departures and owner-directed changes — final register

1. Direct execution replaces the plan header's Superpowers requirement, as
   explicitly authorized. The owner staged work at Tasks 2 and 3 before authorizing
   Tasks 4–7; tasks themselves were not merged or reordered.
2. The execution log started in Task 1 rather than Task 7 to preserve TDD evidence.
3. Review instructions changed number suffixes, kept list-marker values, repeated
   negations, possessives and the timing assertion. A subsequent owner instruction
   changed negation tokens to whole lowercased words. Both have separate commits.
4. Task 4 added the exhaustive HUD case needed to compile the new RawReason;
   Task 5 then supplied final warning/shortcut behavior.
5. Task 5 also copies fidelity fields in AppModel.replaceLast because the current
   code copies fields individually; it added the popover tag required by mockup
   section 4 but omitted from the plan's explicit button-label step.
6. Task 6 uses the wider existing History metadata width when a fidelity tag is
   present. No launch/screenshots were performed, per the owner's hard limit;
   screenshots and F1–F8 are pending, not claimed as completed.
7. Task 7 includes the TDD overlap crash guard described above, found during final
   review. No false-alarm tuning or fallback to warn was necessary.

The plan's decided spec differences were followed: no language parameter, no
Global search entry, and the sentence-start capitalization exception. No planned
test was found to contradict the spec; none was silently weakened. Location
numbers moved, but existing helper names and intended behavior were preserved.

## Owner device checks — not performed

- [ ] **F1.** Say "the timeout is fifteen seconds" in Notion; pasted with 15, no warning.
- [ ] **F2.** Cleanup forced to drop "not" (custom Work tone: "remove the word not"); raw pastes, HUD names "not".
- [ ] **F3.** ⌃⌥R after F2 swaps in the cleaned text; again swaps back.
- [ ] **F4.** Setting on *Paste cleaned and warn*: F2 pastes cleaned with "Check" pill.
- [ ] **F5.** Setting Off: no warning, history still shows the tag.
- [ ] **F6.** "At three, no, I mean four" in Work style; pastes "at 4", no warning.
- [ ] **F7.** Vietnamese with a number: "họp lúc ba giờ" → "họp lúc 3 giờ", no warning.
- [ ] **F8.** History row tag hover lists the issue; swap button pastes the other version.
