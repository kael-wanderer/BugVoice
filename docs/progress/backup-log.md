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
