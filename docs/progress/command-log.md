# Command mode execution log

Implemented 2026-10-19 on `feat/command-mode`, branched from `main` at
`d19f313`. Not merged or pushed. Spec:
`docs/superpowers/specs/2026-10-19-command-mode-design.md`; plan:
`docs/superpowers/plans/2026-10-19-command-mode.md`; mockup:
`docs/design/proposal-command.html`.

## Task evidence

Tasks were executed in order, with one commit per task. For Tasks 1–4 all
listed tests were written before implementation, and the listed filtered
command was observed failing to compile on the missing interfaces. Full
`swift test` passed before every commit. Counts below are passing test cases,
not suite counts.

| Task | Commit | Work and failing-test evidence | VoiceCore | MCPKit | BugVoiceMac |
|---|---|---|---:|---:|---:|
| 1 | `09fdf19` | CommandKey, tolerant default/decode, conflict rule and round trip. `swift test --filter SettingsTests` failed on missing CommandKey / AppSettings.commandKey. | 1,031 | 30 | 95 |
| 2 | `f9789aa` | Rewrite/write prompts, model parameters, shared reasoning removal, preamble/quotes/tags and output limits. `swift test --filter CommandPromptTests` failed on missing CommandPrompt / CommandOutput. Existing OutputSanitizer coverage remains passing. | 1,040 | 30 | 95 |
| 3 | `04081f2` | CommandPipeline, language and vocabulary hints, timeout, paste decision, select-back and command history. `swift test --filter 'CommandPipelineTests\|FixLastTests\|HistoryTests'` failed on the missing pipeline, select-back and history interfaces. | 1,059 | 30 | 95 |
| 4 | `6352723` | AX selection first, marked copy fallback, polling, clipboard snapshot restore and batched Shift+Left. `swift test --filter BugVoiceMacTests` failed on missing SelectionCapture. Tests use unique named pasteboards and injected copy closures; no live copy/paste events were posted. | 1,059 | 30 | 100 |
| 5 | `d7b5178` | Hold-only controller, cancellation, language switching, focus/selection guard, command HUD, Original, settings and menu card. Added test-first Insights/backfill exclusion: the filtered test failed with two expectations before implementing the exclusions. Full suite and signed app build passed. Read-only Settings smoke check passed; details below. | 1,060 | 30 | 100 |
| 6 | `9860664` | History Command tag, quoted secondary italic instruction and instruction search. Full suite and signed app build passed. | 1,060 | 30 | 100 |
| 7 | This documentation commit | Log, guide links, handoff, roadmap, proposal status and plan checklist. Full suite passed. | 1,060 | 30 | 100 |

Final suite: **1,190 tests** — VoiceCore 1,060 / 114 suites, MCPKit 30 / 2
suites, BugVoiceMac 100 / 18 suites. `Scripts/build-app.sh` succeeded for
Tasks 5 and 6 and reported `Signed with: Bugler Local Dev`. No dependencies
were added. The pre-commit hook raised the build on each commit; the builder
never edited CFBundleVersion.

Raw red/green transcripts are under `/private/tmp/bv-command-task{1…7}-*.log`
(for example `bv-command-task3-red.log`, `bv-command-task6-green.log`);
build transcripts are `bv-command-task5-build.log` and
`bv-command-task6-build.log` in the same directory.

## Deviations and supporting changes

1. The required superpowers execution skills were not installed. The owner
   explicitly authorized executing the plan without either skill. No
   subagents were used.
2. `CommandOutput.Rejection` also conforms to `Error`, required by Swift's
   `Result<String, Rejection>` constraint. Its cases and the planned function
   signature are unchanged.
3. `DictationResult.outcome` is nonoptional in the existing code. A ready
   command uses `.nothingHeard` as an internal placeholder until the app
   assigns the actual insertion/copy outcome; no ready result is recorded
   before that assignment.
4. Task 5 also updates `InsightsDelta.dictation` and `InsightsDelta.history`
   to exclude commands. Skipping the live recordInsights call alone would
   still count commands when Insights is rebuilt from history. The added
   `commandsExcludedFromInsightsAndBackfill` test was seen failing first.
   Secure-field recall now also clears the original text and command field.
5. Task 5 updates `HotkeyMonitor` to skip mapping events carrying
   `FixLast.syntheticEventMarker`, after notifying its key observer. Without
   this, the command's own fallback ⌘C could cancel its hold. Existing typing
   observation still filters marked events through FixLast.
6. The app constructs the Dictation model plan with a 30-second transport
   timeout for commands, as well as using the pipeline's 30-second timeout.
   It shares the existing speech-readiness helper and insertion-record helpers
   with DictationController. Original rechecks its guard after asynchronous
   select-back, before pasting. These preserve the planned behavior with the
   existing provider/controller APIs.

## Read-only device evidence and data restoration

- Backed up `~/Library/Application Support/BugVoice` to
  `/private/tmp/bv-before-codex` before launching. A pre-existing backup at
  that location was preserved with a `-prior-…` suffix. The transient
  `MCP/bugvoice.sock` Unix socket cannot be copied as a regular file and was
  excluded; every regular file was copied and its SHA-256 verified.
- Launched with `Scripts/run-dev-app.sh`. The app initially had no visible
  window; an application `reopen` event displayed its existing main window.
  No bare `open` command, synthetic hotkey hold, Return key, recording or
  paste-producing click was used.
- The computer-use provider located window 10617 on **screen index 1** at
  approximately `(2924, 153)`, size `1832 × 1164`, before any screenshot or
  click. Captures were of that BugVoice window using ScreenCaptureKit.
- Settings › General was inspected through the accessibility tree and window
  screenshot: **Command key**, value **Right ⌥**, and the exact planned
  footnote were present. Settings › Shortcuts exposed **Command** and
  **Hold Right Option**. This passes Task 5's read-only smoke check.
- Local screenshots: `/private/tmp/bv-command-evidence/general-dark.png` and
  `/private/tmp/bv-command-evidence/shortcuts-dark.png`. They show the owner's
  current dark theme. No theme or hotkey setting was changed.
- Stopped the dev process after inspection, preserved the post-run directory
  separately under `/private/tmp/bv-after-codex-…`, then restored the backup.
  Every restored regular-file hash matched the pre-run manifest at
  `/private/tmp/bv-command-data-manifest.json`. The dev app is stopped.

## C1–C12 device checks

No full device check is marked passed from unit tests, builds or partial UI
inspection. Checks requiring speech, hotkeys, pastes or settings changes are
left for the owner, as instructed.

| Check | Result | Evidence / reason |
|---|---|---|
| C1 Rewrite in Notion; ⌘Z restores | **Not run** | Requires speech and a live replacement/undo. No paste-producing actions while the owner may be using the Mac. |
| C2 Vietnamese translation instruction | **Not run** | Requires speech and a live command result. |
| C3 Write new in Slack / TextEdit | **Not run** | Requires speech and a live paste. |
| C4 Ghostty copies with terminal reason | **Not run** | Requires a live command and clipboard mutation. Paste-decision unit tests pass but do not prove device behavior. |
| C5 Selection changes during Rewriting | **Not run** | Requires a live command with changing focus/selection; unit coverage is not device evidence. |
| C6 Escape during Rewriting | **Not run** | Requires a running spoken command. No synthetic command was started. |
| C7 Original and ⌃⌥R after multiline rewrite | **Not run** | Requires selection-changing and paste-producing input. Select-back tests pass separately. |
| C8 Clipboard after live fallback capture | **Not run** | Requires a live command in Ghostty and a paste. Isolated clipboard restoration tests pass separately. |
| C9 Secure field refuses command | **Not run** | Requires starting command input in a secure field; excluded from read-only checks. No secure field was targeted. |
| C10 History Command tag; Insights unchanged | **Not run** | No real command was generated. History round trip and Insights/backfill exclusion pass in tests; device behavior remains unverified. |
| C11 Off key and hotkey conflict | **Not run** | Requires changing settings and exercising a hotkey. Default Right Option was observed in Settings, but Off/conflict were not exercised. |
| C12 Light and dark match mockup | **Not run — partial read-only inspection** | Current dark General and Shortcuts layouts were inspected, with the Command key and row present and readable. Light theme, command HUD, command menu card and command history were not inspected. Completing both themes would require settings changes and live command states. |

## Review fixes (2026-10-19)

- Selection capture trusts an Accessibility read that shows nothing selected
  and skips the ⌘C fallback. VS Code, Cursor and JetBrains copy the whole
  line on ⌘C with no selection, which would have rewritten that line and
  pasted it at the cursor. Test `emptyReadableSelectionSkipsCopy`.
- An announcing line ending in ":" is kept when the selection contains it
  (a real heading such as "Agenda:"). Test `keepsHeadingFromSelection`.
- Original after a write-new command selects the written text and deletes it
  (HUD "Written text removed") instead of pasting an empty string; a second
  Original shows "Nothing to fix".

## Owner device checks (2026-10-19)

The owner ran the device checks on the build with the review fixes (Notion /
TextEdit rewrite and ⌘Z, write new in Slack, Vietnamese translation, Ghostty
copy with clipboard restored, Original after a multi-line rewrite, Escape
while rewriting, VS Code with no selection, history tag and Insights): all
pass. Merged to `main`.
