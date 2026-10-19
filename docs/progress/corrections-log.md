# Learn from corrections execution log

Date: 2026-10-19. Branch: `feat/learn-from-corrections`, from `main`.
Implemented Tasks 1–6 directly: the named superpowers skills were unavailable.
Not merged or pushed. No new dependencies. Build versions changed only through
`Scripts/git-hooks/pre-commit`.

## Commits and automated evidence

Each task had a full passing `swift test` before its commit. Tasks 1–4 first
ran the listed new tests and observed missing-type compile failures, then
implemented the types. Test logs are local at `/private/tmp/bv-task*-*.log`.

| Task | Commit | Message | VoiceCore | MCPKit | BugVoiceMac |
|---|---|---|---:|---:|---:|
| 1 | `bbbca04` | `feat(core): correction region, diff and filter` | 1,115 | 30 | 109 |
| 2 | `62a1144` | `feat(core): dictionary suggestions` | 1,128 | 30 | 109 |
| 3 | `63300bb` | `feat(mac): field value read and real-word check` | 1,128 | 30 | 114 |
| 4 | `36f5ab8` | `feat(app): watch pasted fields for corrections` | 1,132 | 30 | 114 |
| 5 | `6b84006` | `feat(app): dictionary suggestions UI` | 1,132 | 30 | 114 |
| 6 | this commit | `docs: corrections log and handoff` | 1,132 | 30 | 114 |

Final total: **1,276 tests**. Task 4 and Task 5 `Scripts/build-app.sh`
succeeded, signed with **Bugler Local Dev**. Task 5 was tested and built again
after the badge width adjustment. No synthetic hotkey holds, paste-producing
clicks, secure-field inspection, or Return presses were used.

Covered by automated tests: anchored-region selection, tone/name fixes,
rewrite/insertion/punctuation exclusions, caps, pair counting and dismissal,
Dictionary acceptance, tolerant decode/corruption, stale revisions,
default-on settings, backup file inclusion, real-word recognition, and
preserving the latest correction when the field clears.

## Deviations

- Task 1: `CorrectionCandidate` carries internal changed-count metadata so `keep(_:pasted:)` can enforce the full LCS change fraction even when diff skips long runs or deletions. Public names and signatures are unchanged.
- Task 3: Spell-check lowercase text. On this Mac NSSpellChecker accepts capitalized “Kael” in every available English variant and Vietnamese, but reports lowercase “kael” as misspelled. Lowercasing preserves the required Kael replacement default and the listed tests without a name-specific exception.

- Task 4: Capture anchors at the existing `onWillPostPaste` callback and require the captured element to still be focused after successful delivery. The recording-start snapshot can be stale by paste time. Skip watching when AX cursor context is unavailable; treating unreadable context as two empty anchors would watch the whole field.

## Read-only app smoke checks

Passed with direct AX-tree and window-image evidence on the dev app,
PID 9185, window 10824, **screenIndex 1 (display 2)**, origin (2925, 153),
size 1830 × 1164. Window position was obtained before captures/clicks.

- Dictionary › Words: selected Words tab, “0 words”, “No words yet.”;
  Suggestions card and sidebar count absent. Screenshot:
  `build/corrections-smoke/dictionary.png` (local, ignored build artifact).
- Settings › Speech: “Learn from corrections”, AX toggle value 1, with the
  exact spec footnote visible and readable. Screenshot:
  `build/corrections-smoke/speech.png` (local, ignored build artifact).
- Nonempty suggestions, popover, light theme and narrow layouts were not
  exercised. Navigation alone does not establish the K checks below.

Launched with `Scripts/run-dev-app.sh`. The main window was shown with a reopen
AppleEvent; bundle resolution also started the installed copy, which was stopped.
All observed UI evidence above explicitly targeted the development PID/window.
The initial observation raced app startup; PID selection and a later reopen
resolved the missing window. No input was sent to another app.

Before launch, copied `~/Library/Application Support/BugVoice` to
`/private/tmp/bv-before-codex` with metadata preserved. The transient MCP socket
was not copied (sockets are runtime endpoints). After stopping BugVoice,
restored the original directory and verified all regular files/symlinks against
the backup. Deleted both `/private/tmp/bv-before-codex` and the temporary
modified-data copy `/private/tmp/bv-after-codex`. The restored owner directory
remains in place; the app is stopped.

## Device checks K1–K10

Only read-only checks were authorized. Every full K workflow requires an
interaction beyond that scope; none is reported as passed from unit tests.

| Check | Result | Evidence / reason |
|---|---|---|
| K1 Slack name fix and send within 5 s | **Not run** | Requires dictation/paste, editing and sending in Slack. No such input sent. Pure watch tests cover latest-region retention only. |
| K2 Notion Vietnamese tone fix | **Not run** | Requires dictation/paste and editing in Notion. `toneFixKept` passes, but no device correction was made. |
| K3 “good” to “great” ignored | **Not run** | Requires a paste and edit. `rewordIgnored` passes; no device edit performed. |
| K4 Two corrections counted once | **Not run** | Requires two dictations/pastes. `recordCountsSamePair` passes; no device dictations performed. |
| K5 Add with replacement and next dictation | **Not run** | Requires Dictionary mutation and a subsequent paste. Acceptance unit tests pass only. |
| K6 Both real words default off; Add hint only | **Not run** | Requires an observed correction and Dictionary mutation. RealWords and acceptance unit tests pass only. |
| K7 Dismiss and correct again | **Not run** | Requires dismissal and a later dictation/paste. `dismissedNeverReturns` passes only. |
| K8 Ghostty and password field excluded | **Not run** | Terminal dictation would paste; password fields deliberately never inspected. Terminal exclusion and SecureFocusPolicy guard reviewed in code only. |
| K9 Setting off; no new suggestions; counts update | **Not run** | Read-only Speech row/default-on and empty sidebar verified above. Did not toggle the setting, dictate, or create nonempty count transitions. Popover not inspected. |
| K10 Backup/restore retain pending and dismissed | **Not run** | Backup/restore is mutating. Backup inclusion and suggestion round-trip unit tests pass; no device restore of suggestions performed. |

## Implementation notes

Only changed words enter `suggestions.json`; watch text and anchors stay in
memory. Watch starts only after successful ordinary insertion, with readable
cursor context and the same focused element; excludes Terminal style, secure
fields, Notes, meeting notes and commands. It polls at 1 s for at most 60 s,
uses 0.25 s AX value reads and ends on focus change, invalid value/anchors,
new recording/command or disabling the setting. Ending records the latest
observed region. Accept keeps a suggestion available if Dictionary save fails.

Development errors resolved before commits: AppKit exposes `availableLanguages`
on the checker instance; Swift Testing assertions around mutating `observe`
calls need local result variables. An initial process-stop check matched its
own shell command; an exact process-name check was used before restoration.

## Review fixes (2026-10-19)

- Paste raw (⌃⌥R), Redo in the other language (⌃⌥L) and Retry cancel the
  watch without recording (`CorrectionWatcher.cancel()`). The field then holds
  BugVoice's own replacement, so diffing it against the cleaned paste would
  turn cleanup's edits into false suggestions.
- The field read just before the paste (anchors) runs only when Learn from
  corrections is on and the field is not secure, so a paste with the setting
  off does no extra Accessibility work.
