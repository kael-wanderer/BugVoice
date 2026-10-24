# Incremental transcription — Phase 1 execution log

## Built

- Task 1: streaming pause chunker, 8 specified tests passing. Full suite:
  1,281 VoiceCore, 30 MCPKit, 114 BugVoiceMac (1,425 total).
- Task 2: virtual-clock simulation, silent-part skipping, transcript cleanup,
  previous-part prompts and exact audio boundaries. 7 specified simulation tests
  passing; 15 chunker/simulation tests combined. Full suite: 1,288 VoiceCore,
  30 MCPKit, 114 BugVoiceMac (1,432 total).
- Both tasks first failed to compile because their implementation types were
  absent, then passed targeted tests and the full suite before commit.
- Task 3: medians, least-squares fit, clip grouping and deterministic gate
  failures. All 8 specified tests passed after the expected missing-type compile
  failure. Full suite: 1,296 VoiceCore, 30 MCPKit, 114 BugVoiceMac
  (1,440 total), all passed on the full rerun.
- Initial Task 3 full run: VoiceCore and MCPKit passed; existing macOS test
  `recoveryDropsUncheckpointedJournalTail` failed its 4-byte journal assertion.
  It passed in isolation and the unchanged full suite then passed. No change
  made to the journal test or implementation.

- Time-threshold review fix: the two supplied boundary tests failed first, then
  all 10 gate tests passed with the same 1e-9 tolerance as WER. Full suite:
  1,298 VoiceCore, 30 MCPKit, 114 BugVoiceMac (1,442 total), all passed.

- Task 4: default-on VAD chunking option. Supplied test failed to compile
  before implementation. Full suite: 1,299 VoiceCore, 30 MCPKit,
  114 BugVoiceMac (1,443 total), all passed. `swift build` succeeded.

## Decisions

- Task 4: WhisperKit 1.1.1 declares `chunkingStrategy` optional; no chunking
  uses `nil`, per the plan. The app retains the default `vadChunking: true`.

- Owner correction to Task 3: buckets overlap deliberately. Every clip at least
  30 s is also in the 15 s+ bucket. The corrected `savingThresholds` fixture sets
  both English long-clip savings to 0.4 s, so both savings thresholds fail while
  Vietnamese remains passing. Updated the test and plan together; the gate
  rule and all other Task 3 test values are unchanged.
- WER and time comparisons use the owner-approved 1e-9 tolerance at limits.
- Least-squares fit returns (0, 0) for empty input and (mean y, 0) when all x
  values match; mismatched input lengths are a programmer precondition failure.

- Owner correction: pause midpoint uses integer division of pause frames;
  0.5 s gives 25 frames, half 12 frames, offset 3,840 samples. Task 1's plan
  and test updated together.
- Pause detection uses complete frames. Pause frames are
  `Int(pause * 16_000) / 320`, as directed by the owner.
- Forced-cut windows are scored by the sum of their ten frame RMS values;
  equal scores choose the earliest window. This gives deterministic streaming
  and batch results.
- Simulation keeps the last pass duration separate when calculating latency:
  `max(0, (start - release) + seconds)`. This is algebraically end minus release,
  while preserving the specified exact 1.2 s value for a tail starting at release.

## Smoke run

Not run; Tasks 4–6 remain behind owner review.

## Owner run

Pending.

## Gate result

Pending.

## Decision

Pending Phase 1 results and owner review.
