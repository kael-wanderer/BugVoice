# Backup and restore execution log

## Task 1 — Backup settings (2026-10-19)

- Added `BackupFrequency`, `BackupSettings`, and `AppSettings.backup` with
  per-field tolerant decoding. Defaults are off, no folder bookmark, and five
  retained backups.
- Test-first evidence: added `backupSettingsDefaultsAndTolerantDecode`, then
  `swift test --filter SettingsTests` failed (exit 1) because `BackupSettings`
  and `AppSettings.backup` did not exist. Implemented only after observing that
  expected missing-API failure.
- Focused check: `swift test --filter SettingsTests` passed, 50 tests / 6 suites.
  The filter also matches other settings suites.
- Full check: `swift test` passed, 944 VoiceCore tests / 104 suites,
  30 MCPKit tests / 2 suites, and 94 BugVoiceMac tests / 16 suites
  (1,068 tests total).
- Fixtures are inline JSON and synthetic bookmark bytes; no owner data was read.

## Deviations

- Task 8 adds the observed `BackupController.relaunchError` interface so a quit
  veto can unlock the restore sheet and show its dedicated handoff failure. This
  minimal app-layer coordination is required because staging can succeed before
  quitting is subsequently cancelled. No VoiceCore contract changes.

- `AppSettings` already uses synthesized `CodingKeys`; adding its stored
  `backup` property supplies the coding key automatically, rather than adding
  an explicit coding-key enum. The public API and encoded key remain as planned.

## Task 2 — File names and schedule (2026-10-19)

- Added minute-resolution, time-zone-aware backup and restore safety-copy names,
  collision suffixes, strict filename/date parsing, elapsed-time scheduling,
  newest-backup discovery, and retention restricted to recognized backup names.
- Test-first evidence: wrote all six planned tests, then
  `swift test --filter BackupScheduleTests` failed (exit 1, zero tests executed)
  because `BackupNaming` and `BackupSchedule` did not exist. The expected
  missing-API diagnostics are in `/tmp/bugvoice-task2-red.log`.
- Focused check: `swift test --filter BackupScheduleTests` passed, 6 tests /
  1 suite (`/tmp/bugvoice-task2-green.log`).
- Full check: `swift test` passed, 950 VoiceCore tests / 105 suites,
  30 MCPKit tests / 2 suites, and 94 BugVoiceMac tests / 16 suites
  (1,074 tests total; `/tmp/bugvoice-task2-full.log`).
- Self-review checked public interfaces, strict full-name/date matching,
  collision numbering, explicit time zones, deterministic same-minute retention,
  and Foundation-only imports. `git diff --check` passed. All dates and filenames
  are synthetic; no owner data was read.
- No interface or scope deviations. Added assertions for `newest`, zero retention,
  invalid calendar dates/times, noncanonical suffixes, and trailing newlines.
  Negative retention counts are treated as zero; equal-minute names sort by name.

## Task 3 — Manifest and errors (2026-10-19)

- Added the public versioned manifest, counts and file entries, ISO 8601 JSON
  encoding with sorted keys and indentation, decode error mapping, byte totals,
  ordered missing/wrong-size file checks, and all backup error messages.
- Test-first evidence: wrote four tests, then
  `swift test --filter BackupManifestTests` failed (exit 1, zero tests executed)
  because `BackupManifest` and `BackupError` did not exist
  (`/tmp/bugvoice-task3-red.log`).
- Focused check passed: 4 tests / 1 suite
  (`/tmp/bugvoice-task3-green.log`). Full `swift test` passed: 954 VoiceCore
  tests / 106 suites, 30 MCPKit tests / 2 suites, and 94 BugVoiceMac tests /
  16 suites (1,078 total; `/tmp/bugvoice-task3-full.log`).
- Tests cover complete round-trip equality, total bytes, JSON date formatting,
  malformed/missing-field/newer-format rejection, ordered size/missing failures,
  and every error description, including singular/plural damage counts.
- `git diff --check` passed. Foundation-only implementation; synthetic temporary
  fixtures only, with cleanup. No owner data accessed and no scope deviations.

## Task 4 — Backup file plan (2026-10-19)

- Added the public backup plan and allowlists, sorted relative file paths,
  included byte totals, recursive Notes selection, and ready/failed Meeting
  selection with sorted skipped IDs. Hidden descendants, meeting PCM files,
  checkpoints, cancelled/incomplete/invalid meetings, and other root entries
  are excluded.
- Test-first evidence: wrote five tests, then
  `swift test --filter BackupPlanTests` failed before implementation because
  `BackupPlan` did not exist (`/tmp/bugvoice-task4-red.log`).
- Focused check passed: 5 tests / 1 suite
  (`/tmp/bugvoice-task4-green.log`). Full `swift test` passed: 959 VoiceCore
  tests / 107 suites, 30 MCPKit tests / 2 suites, and 94 BugVoiceMac tests /
  16 suites (1,083 total; `/tmp/bugvoice-task4-full.log`).
- Focused tests caught relative path slicing differences between temporary
  `/var` URLs and enumerator `/private/var` URLs. Resolving both URLs and using
  path components fixes the paths; the same tests now pass.
- Public memberwise initializer supports the following writer task. Minimal
  state-only decoding accepts existing meeting manifests without requiring
  unrelated fields. `git diff --check` passed. Foundation only; fixtures use
  temporary synthetic files with cleanup, and no owner data was accessed.
- No scope deviations.

## Task 5 — Write and read backup files (2026-10-19)

- Added `BackupWriter`: stages copied files and their actual sizes with a
  format-1 manifest, writes a ditto ZIP through a `.partial` file, reads the
  manifest with unzip, and extracts with ditto. Refuses destinations inside
  the library, reports each copied file, checks cancellation between files
  and before publication, and removes staging/partial files on exit.
- Test-first evidence: six tests were written before implementation;
  `swift test --filter BackupWriterTests` failed because `BackupWriter` did
  not exist (`/tmp/bugvoice-task5-red.log`). Focused green passed 6 tests /
  1 suite (`/tmp/bugvoice-task5-green.log`).
- Tests use real system archive tools and synthetic temporary files: Unicode
  round trip and byte validation, destination rejection, failed archive
  cleanup (fake runner leaves partial output), missing manifest, invalid ZIP,
  and per-file progress. No owner data was accessed.
- Full `swift test` passed: 965 VoiceCore tests / 108 suites, 30 MCPKit tests /
  2 suites, 94 BugVoiceMac tests / 16 suites (1,089 total;
  `/tmp/bugvoice-task5-full.log`). `git diff --check` passed.
- Foundation only, no new dependencies, and no scope deviations.

### Task 5 review correction and Deviations

- The plan's literal descendant-prefix guard did not reject a destination
  equal to the library root. Such a destination could replace the library
  directory with its archive. Deviations: corrected that guard to reject
  equality as well as descendants, preserving the plan's protective intent.
- Added `writerRefusesDestinationEqualToLibrary` first. It failed before the
  fix: no error was thrown and the synthetic library's settings file was no
  longer readable (`/tmp/bugvoice-task5-equality-red.log`). The fixed test
  verifies the original settings bytes remain intact.
- Focused green: 7 tests / 1 suite
  (`/tmp/bugvoice-task5-equality-green.log`). Full `swift test` passed:
  966 VoiceCore / 108 suites, 30 MCPKit / 2, 94 BugVoiceMac / 16 (1,090 total;
  `/tmp/bugvoice-task5-equality-full.log`). `git diff --check` passed.

## Task 6 — Stage a restore and apply it at launch (2026-10-19)

- Added Foundation-only `RestoreApplier`, `FileMoving`, and `SystemFileMoving`.
  Staging refuses active meetings and insufficient space, validates extracted
  bytes, and writes the empty `ready` marker last. Launch application replaces
  only the library allowlist, keeps the previous library as a safety copy,
  preserves credentials/models, removes SearchIndex, and retains one safety copy.
- TDD: nine planned tests first failed on missing APIs (`/tmp/task6-red.log`).
  Focused green now passes 11 tests / 1 suite (`/tmp/task6-green.log`). Tests
  use real archive tools with synthetic temporary parent/BugVoice directories;
  no owner library was accessed.
- Deviations: reverse-move failure keeps both recovery directories and writes
  `rollback-failed`; subsequent launch and staging attempts refuse with a
  recovery message instead of deleting the remaining data. Added regression
  first: launch initially deleted pending (`/tmp/task6-regression-red.log`),
  then staging initially deleted it (`/tmp/task6-stage-recovery-red.log`).
  Normal successful rollback still removes empty safety/pending directories.
- Deviations: same-minute restores choose an unused numeric suffix instead of
  colliding with the existing safety folder; regression verifies the second
  original library survives. Safety retention compares names to handle macOS
  `/var` versus `/private/var` URL representations of the same directory.
- Review correction: consume `ready` inside the move transaction before any
  fallible cleanup. A real SearchIndex permission failure initially left it
  replayable; the second launch emptied the restored library (RED:
  `/tmp/task6-cleanup-red.log`). The twelfth test pins successful restored
  content across a cleanup failure and another launch. Focused final green:
  12 tests / 1 suite (`/tmp/task6-green.log`).
- Final full `swift test`: 978 VoiceCore / 109 suites, 30 MCPKit / 2 suites,
  94 BugVoiceMac / 16 suites, all pass (1,102 total;
  `/tmp/task6-full.log`). `git diff --check` passed. No app launch or device
  checks were performed; no dependency was added.

## Task 7 — Backup controller and launch-time restore (2026-10-19)

- Added the observable app controller for manual and scheduled backups, flush-before-
  planning consistency, detached planning/copy/archive work, main-actor progress,
  cancellation, result copy/counts, bookmark folder selection/refresh, hourly and
  immediate settings checks, filename-based due dates and automatic retention.
  Automatic failures report once per launch; missing folders only update the card.
- Added detached manifest inspection and restore staging with the library parent's
  important-usage free capacity, active meeting/upload guards, safety-copy details
  and deletion. AppModel starts the controller only after data loads and shows
  launch restore messages using its existing notice capsule, opening Settings ›
  Storage so the result and safety-copy row are visible after the menu-bar launch.
- Deviations: `backup` is a lazy property, matching other self-owning app services,
  because constructing the controller needs the fully initialized AppModel.
  The existing Task 1 settings API calls its schedule property `frequency`; the
  controller consumes that API rather than introducing a second property.
- Review correction and approved deviation: Workspace launches the new instance
  before its completion terminates the old one. The new instance receives the old
  PID and asynchronously waits for its exit before applying pending restore or
  loading stores; activation/reopen callbacks are gated during that wait. This
  prevents the old instance's final saves from overwriting restored data. The
  OpenConfiguration/new-instance/completion-termination mechanism remains the
  PermissionsView mechanism. Failed launches remove pending data and return an
  error. Notes/meeting notes are flushed and active operations rechecked both
  before staging and immediately before relaunch.
- Quality-review correction: a quit veto cancels the handoff by removing the ready
  marker/pending directory and showing a failure. The waiting instance watches the
  marker and exits without applying or loading files when cancellation occurs.
  Every quit-cancel/reply-false path disarms the handoff, including a late note-save
  failure or cancelling a meeting quit prompt. This coordination requires device
  checking; no app launch or owner data access was performed in this task.
  Device launch/handoff verification remains unverified because CUA access was
  blocked in the parent session. Relaunch preserves BUGVOICE_DEV_SCREEN when set.
- Checks: `swift build` passed with no new warnings (`/tmp/task7-build.log`), and
  full `swift test` passed: 978 VoiceCore / 109 suites, 30 MCPKit / 2 suites,
  94 BugVoiceMac / 16 suites (1,102 total; `/tmp/task7-full.log`).
  `git diff --check` passed. No dependencies were added.

## Task 8 — Backup card and restore sheet (2026-10-19)

- Added the Backup card above Diagnostics in Settings › Storage, using existing
  settings cards, rows, fonts and wrapping action layouts. Save/open panels use
  the backup extension, generated filename and last-used folder; automatic
  backup folder selection creates the proposed Documents folder first and
  commits its bookmark before enabling the schedule. Cancelling first selection
  returns the frequency to Off; cancelling Change preserves the existing folder.
- Added backup progress/cancellation, success/error result, automatic schedule
  dates and sizes, missing-folder message, and safety-copy reveal/delete controls.
  Restore asynchronously inspects the manifest, displays its counts and the two
  replacement/credentials callouts, and disables dismissal/actions while preparing.
  Errors preserve known facts and offer OK; damaged/failed staging uses the
  "Restore did not finish" title.
- Quality-review correction / interface deviation: the controller now exposes a
  dedicated observed relaunchError. A quit veto reports through that signal so a
  restore sheet can leave Preparing and show the failure with OK, rather than
  remaining disabled after an unsuccessful handoff. Unrelated save errors cannot
  trigger this transition. Primary backup/restore actions use prominent buttons.
- `swift build` passed on final sources (`/tmp/bugvoice-task8-build.log`).
- Step 3 light/dark window checks: **not run**. Parent CUA app access was explicitly
  denied; no Task 8 GUI launch, click, screenshot or owner-library access occurred.
  Build/unit-test results do not establish panel, layout or relaunch device passes.
- Final `swift test` passed: 978 VoiceCore / 109 suites, 30 MCPKit / 2 suites,
  94 BugVoiceMac / 16 suites (1,102 total; `/tmp/bugvoice-task8-test.log`).
  `Scripts/build-app.sh` exited 0 and reported `Signed with: Bugler Local Dev`
  (`/tmp/bugvoice-task8-app.log`). `git diff --check` passed. No dependencies added.
- Spec and quality reviews approved the final sources, including the dedicated
  quit-veto signal and prominent primary actions.
- Parent process smoke passed with a protective library copy: stopped the old
  instances, copied the library to `/private/tmp/bv-before`, ran
  `Scripts/run-dev-app.sh` (exit 0), and confirmed the dev process remained running
  after five seconds. Stopped the dev app and restored the original library;
  all 286 inventory entries matched original hashes, modes and symlink targets.
  Evidence: `/private/tmp/bv-device-process-smoke.json` and matching `.log`;
  test-run copy retained at `/private/tmp/bv-device-run-after`. No GUI layout,
  light/dark or backup/restore device behavior is inferred from this process check.
