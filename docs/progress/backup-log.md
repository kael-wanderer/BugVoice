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
