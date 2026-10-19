# Backup and Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Back up the BugVoice library to one `.bugvoicebackup` zip (by hand or on a schedule) and restore from it, keeping a safety copy of the library a restore replaces.

**Architecture:** Every decision lives in `VoiceCore` (Foundation only, test first): what goes in, the manifest, file names, the schedule, staging a restore and applying it at launch with rollback. Zipping uses `/usr/bin/ditto` and reading one entry uses `/usr/bin/unzip`, both through the existing `ProcessRunner`. The app adds a `BackupController`, a Backup card in Settings › Storage, a restore sheet, and one call at the top of `applicationDidFinishLaunching` that applies a staged restore before anything loads.

**Tech Stack:** Swift 6 package (tools 6.0), macOS 15 floor, Swift Testing, SwiftUI, `/usr/bin/ditto`, `/usr/bin/unzip`.

**Spec:** `docs/superpowers/specs/2026-10-19-backup-restore-design.md` (approved 2026-10-19). Mockup: `docs/design/proposal-backup.html`. Read both before Task 1.

## Global Constraints

- `VoiceCore` imports Foundation only. No new package dependency (WhisperKit `exact: "1.1.1"` stays the only one).
- TDD for everything in `VoiceCore`: failing test first. `swift test` passes before every commit.
- One commit per task, message style `feat(core): …`, `feat(app): …`, `docs: …`, ending with the `Co-Authored-By` line the session uses. The pre-commit hook raises `CFBundleVersion` by one; do not edit it by hand, and never commit with `--no-verify`.
- Build the app with `Scripts/build-app.sh`; run it with `Scripts/run-dev-app.sh` (opens on the non-primary display). Never `open` the bundle bare.
- UI copy: plain English, no hedging words, no emoji. Use the mockup's strings verbatim.
- Never put `credentials.json` in a backup. Never delete a file in a user folder unless its name starts with `BugVoice Backup ` and ends with `.bugvoicebackup`.
- Log failures with `Log.app.error("…", privacy: .public)` (`Sources/BugVoiceMac/Log.swift`); never log note or transcript text.
- Library root is `AppPaths.root` (`~/Library/Application Support/BugVoice`). Tests use a temp directory, never the real one.

## Review Focus

1. **A note being typed when Back up now starts** — its latest text must be in the backup. `BackupController.backUpNow` calls `notesController.flushAll()` and `meetings.flushNotes()` before planning. Pinned by manual check B3 in Task 9.
2. **Destination inside the library folder** (user picks `~/Library/Application Support/BugVoice` in the save panel) — refuse with `BackupError.destinationInsideLibrary`. Pinned by `writerRefusesDestinationInsideLibrary` in Task 5.
3. **A file that is not a backup** (a renamed zip, a `.partial`, a text file) — the sheet says "This file is not a BugVoice backup." and nothing changes. Pinned by `readManifestRejectsZipWithoutManifest` and `readManifestRejectsNonZip` in Task 5.
4. **App quits or crashes after unzipping but before `ready`** — next launch deletes the pending folder and leaves the library alone. Pinned by `pendingWithoutReadyIsDeletedAndLibraryUntouched` in Task 6.
5. **Non-ASCII and spaced file names** (`Notes/ghi chú tuần 1.md`) — survive a backup and restore byte for byte. Pinned by `roundTripKeepsUnicodeNames` in Task 5.

---

### Task 1: Backup settings

**Files:**
- Modify: `Sources/VoiceCore/Settings.swift` (add types after `AgentSettings`, add `backup` to `AppSettings` and its decoder)
- Test: `Tests/VoiceCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces:
  - `public enum BackupFrequency: String, Codable, Sendable, CaseIterable { case off, daily, weekly }`
  - `public struct BackupSettings: Codable, Equatable, Sendable { var frequency: BackupFrequency = .off; var folderBookmark: Data? = nil; var keep = 5; init(frequency:folderBookmark:keep:) }` with a tolerant `init(from:)` using `c.value(_:default:)` like `AgentSettings`.
  - `AppSettings.backup: BackupSettings`

- [ ] **Step 1: Write the failing test** `backupSettingsDefaultsAndTolerantDecode` in `SettingsTests`:

```swift
#expect(AppSettings().backup == BackupSettings(frequency: .off, folderBookmark: nil, keep: 5))
let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"backup":{"frequency":"weekly"}}"#.utf8))
#expect(s.backup.frequency == .weekly && s.backup.keep == 5)
let bad = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"backup":{"frequency":"hourly","keep":3}}"#.utf8))
#expect(bad.backup == BackupSettings(frequency: .off, folderBookmark: nil, keep: 3))
let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode({ var a = AppSettings(); a.backup.folderBookmark = Data([1, 2]); return a }()))
#expect(round.backup.folderBookmark == Data([1, 2]))
```

- [ ] **Step 2:** `swift test --filter SettingsTests` — FAIL, `BackupSettings` not found.
- [ ] **Step 3:** Add the types and `backup = c.value(.backup, default: backup)` in `AppSettings.init(from:)`.
- [ ] **Step 4:** `swift test --filter SettingsTests` — PASS.
- [ ] **Step 5:** Commit `feat(core): backup settings`.

### Task 2: File names and schedule

**Files:**
- Create: `Sources/VoiceCore/BackupSchedule.swift`
- Test: `Tests/VoiceCoreTests/BackupScheduleTests.swift`

**Interfaces:**
- Produces:
  - `public enum BackupNaming` with
    - `static let fileExtension = "bugvoicebackup"`
    - `static func fileName(at date: Date, timeZone: TimeZone, taken: Set<String>) -> String` → `"BugVoice Backup 2026-10-19 0912.bugvoicebackup"`; if taken, `"… 0912 2.bugvoicebackup"`, then ` 3`, …
    - `static func date(fromFileName name: String, timeZone: TimeZone) -> Date?` — parses both forms; nil for any other name.
    - `static func safetyCopyName(at date: Date, timeZone: TimeZone) -> String` → `"Restore safety copy 2026-10-19 0915"`
    - `static let safetyCopyPrefix = "Restore safety copy "`
  - `public enum BackupSchedule` with
    - `static func isDue(_ frequency: BackupFrequency, newest: Date?, now: Date) -> Bool` — `.off` never; nil newest is due; daily when `now - newest >= 86_400`; weekly when `>= 604_800`.
    - `static func filesToDelete(_ names: [String], keep: Int, timeZone: TimeZone) -> [String]` — only names `date(fromFileName:)` parses; newest `keep` stay; returns the rest, oldest first.
    - `static func newest(_ names: [String], timeZone: TimeZone) -> Date?`

Use a `DateFormatter` with `en_US_POSIX`, format `yyyy-MM-dd HHmm`.

- [ ] **Step 1: Write the failing tests** (UTC time zone, date `2026-10-19T09:12:30Z`):
  - `fileNameUsesLocalMinute`: `== "BugVoice Backup 2026-10-19 0912.bugvoicebackup"`; with `TimeZone(identifier: "Asia/Ho_Chi_Minh")` → `"… 1612.bugvoicebackup"`.
  - `fileNameAvoidsTakenNames`: taken = `["BugVoice Backup 2026-10-19 0912.bugvoicebackup"]` → `"BugVoice Backup 2026-10-19 0912 2.bugvoicebackup"`; with ` 2` also taken → ` 3`.
  - `dateParsesBothFormsAndRejectsOthers`: both names above give `2026-10-19T09:12:00Z`; `"notes.zip"`, `"BugVoice Backup 2026-13-40 9999.bugvoicebackup"`, `"BugVoice Backup 2026-10-19 0912.zip"` give nil.
  - `dueRules`: `.off` with nil → false; `.daily` nil → true; daily 23 h 59 m → false; daily 24 h → true; weekly 6 days → false; weekly 7 days → true.
  - `pruneKeepsNewestAndIgnoresOtherFiles`: names for 1st…7th Oct plus `"My notes.bugvoicebackup"` and `"BugVoice Backup.txt"`, keep 5 → returns the 1st and 2nd Oct names, in that order.
  - `safetyCopyName`: `== "Restore safety copy 2026-10-19 0912"`.
- [ ] **Step 2:** `swift test --filter BackupScheduleTests` — FAIL.
- [ ] **Step 3:** Implement `BackupSchedule.swift`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat(core): backup file names and schedule`.

### Task 3: Manifest and errors

**Files:**
- Create: `Sources/VoiceCore/BackupManifest.swift`
- Test: `Tests/VoiceCoreTests/BackupManifestTests.swift`

**Interfaces:**
- Produces:
  - `public struct BackupManifest: Codable, Equatable, Sendable`
    - `static let currentFormat = 1`
    - `struct Counts: Codable, Equatable, Sendable { notes, meetings, dictations, dictionaryWords, folders, tags: Int }` with memberwise public init.
    - `struct File: Codable, Equatable, Sendable { path: String; size: Int64 }` (`path` relative to `data/`, `/`-separated).
    - fields `format: Int, createdAt: Date, appVersion: String, build: String, counts: Counts, files: [File]`; public memberwise init.
    - `func encoded() throws -> Data` — ISO 8601 dates, `[.prettyPrinted, .sortedKeys]`.
    - `static func decode(_ data: Data) throws -> BackupManifest` — invalid JSON or missing fields → `BackupError.notABackup`; `format > currentFormat` → `BackupError.newerFormat`.
    - `func problems(in dataDirectory: URL) -> [String]` — paths missing or with a different size, in manifest order.
    - `var totalBytes: Int64` — sum of sizes.
  - `public enum BackupError: Error, Equatable, LocalizedError` with cases and exact `errorDescription`:
    - `notABackup` → "This file is not a BugVoice backup."
    - `newerFormat` → "This backup is from a newer BugVoice format. Update BugVoice first."
    - `damaged(count: Int)` → "The backup is damaged: \(count) files are missing or the wrong size. Nothing was changed." (`1 file is` when count is 1)
    - `meetingActive` → "A meeting is recording. Stop the meeting first."
    - `notEnoughSpace(bytes: Int64)` → "Not enough free space to restore. Free \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) and try again."
    - `destinationInsideLibrary` → "Choose a folder outside the BugVoice data folder."
    - `failed(String)` → the string.

- [ ] **Step 1: Write the failing tests**:
  - `roundTrips`: a manifest with all fields → `decode(encoded())` equals it.
  - `rejectsGarbageAndNewerFormat`: `Data("hello".utf8)` and `Data("{}".utf8)` throw `.notABackup`; a valid manifest with `format: 2` throws `.newerFormat`.
  - `problemsListsMissingAndWrongSize`: temp dir with `a.json` (3 bytes) and `Notes/b.md` (5 bytes); manifest lists `a.json` 3, `Notes/b.md` 4, `c.json` 1 → `["Notes/b.md", "c.json"]`.
  - `damagedMessageCountsInSingular`: `BackupError.damaged(count: 1).errorDescription == "The backup is damaged: 1 file is missing or the wrong size. Nothing was changed."`
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat(core): backup manifest`.

### Task 4: What goes in a backup

**Files:**
- Create: `Sources/VoiceCore/BackupPlan.swift`
- Test: `Tests/VoiceCoreTests/BackupPlanTests.swift`

**Interfaces:**
- Consumes: `MeetingState` (`Sources/VoiceCore/Meeting.swift`).
- Produces:
  - `public struct BackupPlan: Equatable, Sendable { var files: [String]; var skippedMeetings: [String]; var totalBytes: Int64 }`
  - `static let rootFiles = ["settings.json", "dictionary.json", "history.jsonl", "insights.json", "library.json", "voices.json"]`
  - `static let rootFolders = ["Meetings", "Notes"]`
  - `static func make(root: URL) throws -> BackupPlan` — `files` sorted, relative, `/`-separated.

Rules (from the spec's tables):
- Root files: only those in `rootFiles` that exist.
- `Notes/`: every regular file at any depth, skipping hidden names (starting with `.`) and anything inside a hidden folder.
- `Meetings/<id>/`: skip the folder if it has `.upload-cancelled`, has no `meeting.json`, or its `meeting.json` `state` is not `ready` or `failed` (decode only `{ "state": MeetingState }`; undecodable → skip). Skipped folder names go in `skippedMeetings`, sorted. From an included folder take regular files at any depth except hidden names, `checkpoint.json` and `*.pcm`.
- Everything else under root is left out (credentials, models, SearchIndex, MCP, last.wav, safety copies, `*.corrupt-*`).

- [ ] **Step 1: Write the failing tests** (build a temp root with helper `write(_ path: String, _ text: String)`):
  - `includesLibraryFilesAndLeavesOutTheRest`: root has every `rootFiles` entry except `voices.json`, plus `credentials.json`, `last.wav`, `vocabulary.migrated.txt`, `settings.json.corrupt-1`, `models/m.bin`, `SearchIndex/i`, `MCP/agent-uploads.json`, `Restore safety copy 2026-10-19 0915/settings.json` → `files == ["dictionary.json", "history.jsonl", "insights.json", "library.json", "settings.json"]`.
  - `notesSkipHiddenFiles`: `Notes/a.md`, `Notes/.DS_Store`, `Notes/.trash/x.md` → only `Notes/a.md`.
  - `meetingsKeepReadyAndFailedOnly`: folders `r` (state ready, `meeting.json`, `audio.m4a`, `mic.pcm`, `checkpoint.json`, `.meeting.json.x.tmp`), `f` (failed, `meeting.json`), `t` (transcribing), `c` (ready + `.upload-cancelled`), `n` (no manifest) → files contain `Meetings/r/audio.m4a`, `Meetings/r/meeting.json`, `Meetings/f/meeting.json` and no other `Meetings/` path; `skippedMeetings == ["c", "n", "t"]`.
  - `totalBytesSumsIncludedFiles`: two files of 3 and 4 bytes → 7.
  - `emptyRootGivesEmptyPlan`: missing root → `files == []`, no throw.
- [ ] **Step 2:** FAIL. **Step 3:** implement with `FileManager.enumerator(at:includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])`. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat(core): backup plan`.

### Task 5: Writing and reading backup files

**Files:**
- Create: `Sources/VoiceCore/BackupWriter.swift`
- Test: `Tests/VoiceCoreTests/BackupWriterTests.swift`

**Interfaces:**
- Consumes: `BackupPlan`, `BackupManifest`, `BackupError`, `ProcessRunner`/`FoundationProcessRunner` (`Sources/VoiceCore/ProcessRunner.swift`).
- Produces: `public struct BackupWriter: Sendable` with
  - `init(runner: any ProcessRunner = FoundationProcessRunner())`
  - `func write(plan: BackupPlan, root: URL, to destination: URL, createdAt: Date, appVersion: String, build: String, counts: BackupManifest.Counts, progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> Int64` — returns the archive's size in bytes.
  - `func readManifest(_ archive: URL) async throws -> BackupManifest`
  - `func extract(_ archive: URL, into directory: URL) async throws`

Behaviour:
- `write`: throw `.destinationInsideLibrary` when `destination.standardizedFileURL.path` starts with `root.standardizedFileURL.path + "/"`. Stage in `FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: root, create: true)`: copy each plan file to `staging/data/<path>` (creating folders), calling `progress(done, total)` after each; check `Task.isCancelled` between files and throw `CancellationError`. Write `staging/backup.json` with `format: 1` and the file list with sizes as copied. Run `/usr/bin/ditto -c -k --sequesterRsrc <staging> <destination>.partial` (timeout 3600); non-zero exit → `.failed("Could not write the backup: <stderr first line>")`. Remove an existing destination, then move `.partial` into place. Always remove the staging folder and any `.partial` on failure or cancel.
- `readManifest`: `/usr/bin/unzip -p <archive> backup.json` (timeout 60); non-zero exit or empty stdout → `.notABackup`; else `BackupManifest.decode`.
- `extract`: `/usr/bin/ditto -x -k <archive> <directory>`; non-zero → `.failed("Could not open the backup.")`.

- [ ] **Step 1: Write the failing tests** (real tools, temp dirs):
  - `roundTripKeepsUnicodeNames`: root with `settings.json` `{}` and `Notes/ghi chú tuần 1.md` "xin chào"; `make` plan, `write` to `out/BugVoice Backup x.bugvoicebackup`; `readManifest` has `format == 1`, both paths, counts as passed; `extract` into a fresh dir; `data/Notes/ghi chú tuần 1.md` reads "xin chào"; `manifest.problems(in: extracted/data) == []`.
  - `writerRefusesDestinationInsideLibrary`: destination `root/backups/x.bugvoicebackup` throws `.destinationInsideLibrary`; no file created.
  - `failedZipLeavesNoFile`: a fake `ProcessRunner` returning exit 1 for `ditto` → throws `.failed`, and neither `x.bugvoicebackup` nor `x.bugvoicebackup.partial` exists.
  - `readManifestRejectsZipWithoutManifest`: zip a folder holding only `a.txt` with `ditto -c -k` → `readManifest` throws `.notABackup`.
  - `readManifestRejectsNonZip`: a text file → throws `.notABackup`.
  - `progressReportsEveryFile`: plan of 3 files → progress calls end with `(3, 3)`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat(core): write and read backup files`.

### Task 6: Staging a restore and applying it at launch

**Files:**
- Create: `Sources/VoiceCore/RestoreApplier.swift`
- Test: `Tests/VoiceCoreTests/RestoreApplierTests.swift`

**Interfaces:**
- Consumes: `BackupWriter`, `BackupManifest`, `BackupPlan.rootFiles`, `BackupPlan.rootFolders`, `BackupNaming`.
- Produces:
  - `public protocol FileMoving: Sendable { func moveItem(at: URL, to: URL) throws }` and `public struct SystemFileMoving: FileMoving` (calls `FileManager.default.moveItem`).
  - `public enum RestoreApplier` with
    - `static func pendingDirectory(for root: URL) -> URL` → `root.deletingLastPathComponent()/"BugVoice Restore Pending"`
    - `static func stage(archive: URL, root: URL, writer: BackupWriter, meetingActive: Bool, availableBytes: Int64) async throws -> BackupManifest`
    - `struct Outcome: Equatable, Sendable { var backupCreatedAt: Date; var safetyCopy: URL }`
    - `static func applyPending(root: URL, now: Date, timeZone: TimeZone, mover: any FileMoving = SystemFileMoving()) throws -> Outcome?`
    - `static func safetyCopies(in root: URL) -> [URL]` — folders whose name starts with `BackupNaming.safetyCopyPrefix`, oldest first.

Behaviour:
- `stage`: `meetingActive` → `.meetingActive`. `readManifest`. Needed = `totalBytes + totalBytes / 10`; `availableBytes < needed` → `.notEnoughSpace(bytes: needed - availableBytes)`. Delete any old pending folder, `extract` into it, `problems(in: pending/data)` non-empty → delete pending, throw `.damaged(count:)`. The extracted `backup.json` stays in the pending folder; write an empty `ready` file last.
- `applyPending`: no pending folder → nil. No `ready` → delete pending, return nil. Read `pending/backup.json`. Create `root/<safetyCopyName(now)>`. For each name in `rootFiles + rootFolders` present in root, move it into the safety copy; then for each present in `pending/data`, move it into root. Record every move; on any thrown error undo the recorded moves in reverse, remove the empty safety copy, delete pending, rethrow as `.failed("Restore did not finish: <error>")`. On success: remove `root/SearchIndex`, delete every older safety copy (keep only the new one), delete pending, return the outcome.

- [ ] **Step 1: Write the failing tests** (temp parent holding `BugVoice/` root):
  - `stageRefusesActiveMeeting`, `stageRefusesWhenSpaceIsShort` (archive of 1,000 bytes of data, `availableBytes: 1_000` → `.notEnoughSpace(bytes: 100)`), and `stageRefusesDamagedBackup` (archive whose manifest lists a file with the wrong size → `.damaged(count: 1)`, pending folder gone).
  - `stageWritesReadyLast`: valid archive → pending has `data/`, `backup.json`, `ready`.
  - `applyReplacesLibraryAndKeepsSafetyCopy`: root has `settings.json` "old", `Notes/a.md`, `credentials.json`, `models/m`, `SearchIndex/i`; pending (staged from a backup holding `settings.json` "new", `Notes/b.md`) → root `settings.json` reads "new", `Notes/b.md` exists, `Notes/a.md` does not, `credentials.json` and `models/m` untouched, `SearchIndex` gone, safety copy holds `settings.json` "old" and `Notes/a.md`, pending gone.
  - `pendingWithoutReadyIsDeletedAndLibraryUntouched`: pending with `data/settings.json` but no `ready` → returns nil, root unchanged, pending gone.
  - `failedMoveRollsBack`: a `FileMoving` that throws on its third call → throws `.failed`, root contents equal what they were before, no safety copy folder left.
  - `secondRestoreKeepsOnlyNewestSafetyCopy`: two applies at different `now` → exactly one safety copy, named for the second.
  - `nothingPendingReturnsNil`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat(core): stage a restore and apply it at launch`.

### Task 7: Backup controller and launch hook

**Files:**
- Create: `Sources/BugVoice/BackupController.swift`
- Modify: `Sources/BugVoice/AppModel.swift` (own `let backup: BackupController`, start its schedule in `bootstrap()` after data loads; hold a `restoreMessage: String?` set at launch)
- Modify: `Sources/BugVoice/BugVoiceApp.swift` (`applicationDidFinishLaunching`: first line after `Log.app.notice`)

**Interfaces:**
- Consumes: Tasks 1–6; `AppModel` (`notesController.flushAll()`, `meetings?.flushNotes()`, `meetings?.isActive`, `uploads?.isBusy`, `history.count`, `dictionary.words.count`, `library.folders.count`, `tagRows.count`, `notesController.notes.count`, `saveError`, `settings.backup`); `CFBundleShortVersionString` and `CFBundleVersion` from `Bundle.main.infoDictionary` for the manifest's `appVersion` and `build`.
- Produces (`@MainActor @Observable final class BackupController`):
  - `enum Activity: Equatable { case idle, backingUp(done: Int, total: Int), done(String, file: URL, note: String?), failed(String) }` and `var activity: Activity`
  - `func backUpNow(to destination: URL) async` — manual; flushes, plans, writes, sets `activity`.
  - `func cancel()`
  - `func inspect(_ archive: URL) async -> Result<BackupManifest, BackupError>`
  - `func restoreAndRelaunch(_ archive: URL) async -> BackupError?` — `RestoreApplier.stage`, then relaunch exactly as `PermissionsView.relaunch()` does (`NSWorkspace.OpenConfiguration` with `createsNewApplicationInstance = true`, then `NSApp.terminate`).
  - `var backupFolder: URL?` (resolves `settings.backup.folderBookmark` with `.withoutUI`; refreshes a stale bookmark) and `func setBackupFolder(_ url: URL)`.
  - `var lastBackup: (date: Date, bytes: Int64)?`, `var nextBackup: Date?`, `var folderMissing: Bool`
  - `var safetyCopy: (url: URL, date: Date, bytes: Int64)?` and `func deleteSafetyCopy()`
  - `func startSchedule()` — checks now and then every 3,600 s with a `Task` loop.
  - `static func applyPendingRestore(root: URL) -> String?` — calls `RestoreApplier.applyPending(root:now:timeZone:)`; returns "Restored the backup from <date, medium date and short time>." or the error text, and logs either.

Rules:
- Manual and automatic share one write path; only one runs at a time (a second request while busy is ignored).
- Automatic run: skip when `meetings?.isActive == true` or `uploads?.isBusy == true`; due by `BackupSchedule.isDue` on `BackupSchedule.newest` of the folder's file names; write `BackupNaming.fileName(at: .now, timeZone: .current, taken:)` into the folder; on success delete `BackupSchedule.filesToDelete(names, keep: settings.backup.keep, …)`; on failure set `saveError` once per launch. Missing folder → `folderMissing = true`, no `saveError`.
- Counts: notes = `notesController.notes.count`, meetings = number of distinct `Meetings/<id>` folders in the plan, dictations = `history.count`, dictionaryWords = `dictionary.words.count`, folders = `library.folders.count`, tags = `tagRows.count`.
- Free space: `URLResourceValues.volumeAvailableCapacityForImportantUsage` of the library's parent.
- Write runs off the main actor (`Task.detached`; automatic runs use `priority: .utility`), progress hops back to the main actor.
- `done` text: "Backed up \(size) to \(folder name)."; `note` = "1 meeting was still recording and was left out." / "\(n) meetings were still recording and were left out." / nil.

- [ ] **Step 1:** Implement `BackupController` and the launch hook; `AppModel.bootstrap()` shows `restoreMessage` through `notice` if the app has one, else `saveError` (reuse whichever banner `AppModel` already shows for one-off messages).
- [ ] **Step 2:** `swift build` — no errors or new warnings. `swift test` — all pass.
- [ ] **Step 3:** Commit `feat(app): backup controller and launch-time restore`.

### Task 8: Backup card and restore sheet

**Files:**
- Create: `Sources/BugVoice/UI/Settings/BackupCard.swift`, `Sources/BugVoice/UI/Settings/RestoreSheet.swift`
- Modify: `Sources/BugVoice/UI/Settings/StorageTab.swift` (insert `BackupCard(model: model)` above the Diagnostics card)

**Interfaces:**
- Consumes: `BackupController` (Task 7), `SettingsCard`, `SettingsRow`, `.bvFont`, `.bvSecondary` (as `StorageTab` uses them).

Layout and copy follow mockup screens 1–4 exactly:
- Card title "Backup"; line "Back up notes, meetings, history, Dictionary, folders and tags, and settings to one file."; buttons **Back up now…** (`NSSavePanel`, default name from `BackupNaming.fileName`, `allowedContentTypes` from the extension, starts in the last folder used) and **Restore…** (`NSOpenPanel`, `.bugvoicebackup` only).
- While backing up: "Backing up… \(done) of \(total) files", **Cancel**, a `ProgressView(value:)`, both buttons disabled.
- Result line from `activity` (green for done with **Show in Finder**, red for failed).
- Divider; "Back up automatically" picker Off / Daily / Weekly. Choosing Daily or Weekly with no folder opens `NSOpenPanel` (directories, can create) starting at `~/Documents/BugVoice Backups` (create it first); cancelling the panel sets the picker back to Off. With a folder: path row with **Change…** and **Show in Finder**, then "Last backup: \(relative date) · \(size) · Next: \(relative date). Keeps the newest 5." or "The backup folder is missing. Connect the drive or choose another folder." when `folderMissing`.
- Footnote "API keys and speech models are not included."
- Safety copy row only when `safetyCopy != nil`: "Safety copy from before the restore on \(date) · \(size)", **Show in Finder**, **Delete…** (confirmation dialog "Delete the safety copy?" with destructive **Delete**).
- `RestoreSheet`: title "Restore this backup?", facts grid (Made, From "BugVoice \(appVersion) (\(build))", Notes, Meetings, Dictations, Dictionary "\(n) words", Folders, tags "\(f) folder(s), \(t) tag(s)"), the two callouts from the mockup, **Cancel** and **Restore and relaunch**. When `inspect` or `restoreAndRelaunch` returns an error: show the facts that are known, the error in a red-bordered callout, and only **OK**. While staging, disable both buttons and show "Preparing…".

- [ ] **Step 1:** Implement the two views and insert the card.
- [ ] **Step 2:** `swift build` and `swift test` pass. `Scripts/build-app.sh` exits 0.
- [ ] **Step 3:** Run `Scripts/run-dev-app.sh`, open Settings › Storage on the non-primary display, capture the BugVoice window: the card matches mockup screen 1 (left) in light and dark themes.
- [ ] **Step 4:** Commit `feat(app): backup card and restore sheet`.

### Task 9: Device checks, log and docs

**Files:**
- Create: `docs/progress/backup-log.md`
- Modify: `CLAUDE.md` (key documents: plan and log lines), `docs/progress/HANDOFF.md`, `docs/ROADMAP.md` (current-state row "Backup and restore")

- [ ] **Step 1:** Run these on the dev build and record pass/fail with evidence in `backup-log.md`. Use a copy of the data, never the owner's real library: quit BugVoice, `cp -R ~/Library/Application\ Support/BugVoice /private/tmp/bv-before`, and restore that copy at the end.
  - B1 Back up now to `~/Desktop`; file named `BugVoice Backup <date> <time>.bugvoicebackup`; renamed to `.zip`, Finder opens it and shows `backup.json` and `data/`; no `credentials.json` inside (`unzip -l`).
  - B2 Save panel pointed inside the data folder → "Choose a folder outside the BugVoice data folder."
  - B3 Type a word into an open note, immediately Back up now → `unzip -p <file> 'data/Notes/<note>.md'` contains the word.
  - B4 Cancel during a backup → no file and no `.partial` left.
  - B5 Restore… a text file renamed `.bugvoicebackup` → "This file is not a BugVoice backup."
  - B6 Restore the B1 file after adding a note → app relaunches; the new note is gone; "Restored the backup from …" shows; Storage shows the safety copy row; the safety copy holds the added note.
  - B7 Automatic Daily into a fresh folder → a backup appears within a minute of choosing the folder; card shows Last backup and Next.
  - B8 Put 7 named backup files plus `keep-me.bugvoicebackup` in the folder, force a run (set Weekly, delete newest) → 5 named files remain and `keep-me.bugvoicebackup` stays.
  - B9 Automatic folder on a disconnected volume or renamed away → card shows the missing-folder line; no banner after the first.
  - B10 Restore while a meeting records → "A meeting is recording. Stop the meeting first."
- [ ] **Step 2:** Update `CLAUDE.md`, `HANDOFF.md`, `ROADMAP.md`.
- [ ] **Step 3:** Commit `docs: backup and restore log and handoff`.
