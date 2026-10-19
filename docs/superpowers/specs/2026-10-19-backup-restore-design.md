# Backup and restore

Date: 2026-10-19. Status: approved by owner 2026-10-19 (calls 1–4 below accepted).
Mockup: `docs/design/proposal-backup.html`.
Follows: the app review of 2026-10-19 (`docs/propose-new-features.md`, speed note
and review findings in `docs/progress/HANDOFF.md`).

## Why

Everything BugVoice keeps lives in one folder,
`~/Library/Application Support/BugVoice`: notes, meetings with their audio,
dictation history, Dictionary, folders and tags, insights, known voices and
settings. Nothing copies it anywhere. A disk failure, a new Mac, or a bad
build that damages a file loses work that cannot be recreated, such as a
meeting's audio.

The owner asked for this on 2026-10-19 and skipped the question round, so the
choices below marked **(my call)** are defaults the owner has not yet
confirmed.

## Goals

1. **Back up now.** One button writes the whole library to one file the user
   chooses.
2. **Restore.** Pick a backup file, see what it holds, confirm, and BugVoice
   replaces its library with the backup's and relaunches.
3. **Safety copy.** A restore never deletes the library it replaces: it keeps
   it aside as a safety copy until the user deletes it.
4. **Automatic backup (my call).** Off, Daily or Weekly, into a folder the user
   picks, keeping the newest 5 files.
5. **Plain file.** A backup is a standard zip, so the user can open it in
   Finder without BugVoice.

## Non-goals

- **API keys.** `credentials.json` is never in a backup (my call). A backup
  file may be copied to a USB drive or a cloud folder; keys should not travel
  with it. After a restore, Settings › Models asks for keys again, as it does
  on a new install.
- **Speech models** (`models/`, about 1.5 GB). They download again.
- **The search index** (`SearchIndex/`). It is rebuilt from notes and
  meetings after a restore.
- **Merging.** A restore replaces the library; it does not merge a backup into
  the current library.
- **Choosing parts.** No "notes only" backup or restore.
- **Encryption.** The zip is not password protected. The user picks where it
  goes.
- **Cloud upload.** BugVoice writes to a local folder only. If the user picks
  an iCloud Drive folder, macOS syncs it; BugVoice adds no account or network
  code.
- **Upload journals, `last.wav`, the MCP socket and agent upload list.** They
  are temporary.

## Anti-goals

- A restore that half applies: some files from the backup, others from the
  old library, with no way back.
- A backup that looks complete but is missing meetings or notes because a
  file was being written at the time.
- A backup file that holds an API key.
- An automatic backup that fills the disk.

## What goes in a backup

From `AppPaths`:

| Included | Path |
|---|---|
| Settings | `settings.json` |
| Dictionary | `dictionary.json` |
| Dictation history | `history.jsonl` |
| Insights | `insights.json` |
| Folders and tags | `library.json` |
| Known voices | `voices.json` |
| Meetings, with audio, transcripts and notes | `Meetings/<id>/` |
| Notes | `Notes/` |

| Left out | Why |
|---|---|
| `credentials.json` | API keys (non-goal) |
| `models/` | Downloads again |
| `SearchIndex/` | Rebuilt |
| `last.wav` | Temporary |
| `MCP/` | Socket and agent upload list are temporary |
| `vocabulary.migrated.txt`, `*.corrupt-*`, `.DS_Store`, hidden files | Leftovers |
| Meeting capture and upload journals inside a meeting folder | Temporary; a meeting that is not `ready` or `failed` is skipped (see below) |
| `Restore safety copy …/` | A backup of a backup |

A missing file is fine: a new install has no `history.jsonl` yet, and the
backup simply has none.

## The file

- Name: `BugVoice Backup 2026-10-19 0912.bugvoicebackup` (local time).
- Format: a zip, written with `/usr/bin/ditto -c -k` (my call: no new
  dependency, keeps file dates, ships with macOS). The extension is BugVoice's
  own so double-clicking does not unzip it by accident; Finder opens it after
  renaming to `.zip`.
- Inside:
  - `backup.json`: the manifest.
  - `data/`: the included files, with the same layout as the library folder.
- `backup.json` holds:
  - `format`: 1. A restore refuses a format it does not know.
  - `createdAt`, `appVersion`, `build` (from `Info.plist`).
  - Counts shown before restore: notes, meetings, dictations, Dictionary
    words, folders, tags.
  - `files`: each file's relative path and size. A restore checks every file
    is present with that size before it touches the library.

## Back up now

Settings › Storage gains a **Backup** card (mockup, screen 1).

1. **Back up now…** opens a save panel with the default name and the last
   folder used.
2. BugVoice copies the included files into a temporary folder on the same
   disk as the library, writes `backup.json`, zips the temporary folder to
   `<name>.partial` next to the destination, then renames it into place. A
   failed or cancelled backup leaves no file with the final name.
3. While it runs, the card shows a progress line ("Backing up… 41 of 120
   files") and **Cancel**. Dictation keeps working.
4. When done: "Backed up 12.4 MB to BugVoice Backups" with **Show in Finder**.

**Consistency.** Before copying, BugVoice waits for pending saves (notes,
Dictionary, settings) to finish, then copies. A meeting that is recording,
transcribing or uploading (state other than `ready` or `failed`) is left out
and named in the result ("1 meeting was still recording and was left out").
**Back up now** stays available while a meeting records; it does not stop it.

**Errors.** Not enough disk space, a folder that cannot be written, or a
missing source file each show one sentence in the card and in the log
(`Log.app`). The temporary folder is removed.

## Restore

1. **Restore…** opens a file panel for `.bugvoicebackup` files.
2. BugVoice reads `backup.json` without unzipping the rest and shows a
   confirmation sheet (mockup, screen 2):
   - When the backup was made, and from which version and build.
   - The counts.
   - "This replaces all notes, meetings, dictation history, Dictionary,
     folders and tags, and settings in BugVoice. Your current library is kept
     as a safety copy."
   - "API keys are not in backups. Enter them again in Settings › Models."
   - **Restore and relaunch** and **Cancel**.
3. Restore is refused, with the reason in the sheet, when:
   - the file is not a BugVoice backup, or `format` is unknown;
   - a meeting is recording, transcribing or uploading ("Stop the meeting
     first");
   - there is not enough free disk space for the unzipped backup plus a
     margin of 10%.
4. On **Restore and relaunch**:
   1. Unzip into `BugVoice Restore Pending/` next to the library folder (same
      disk, so later moves are renames).
   2. Check every file in `files` is present with its size. On a mismatch,
      stop, delete the pending folder, change nothing, and say the backup
      is damaged.
   3. Write a `ready` marker into the pending folder, last.
   4. Relaunch BugVoice.
5. At the start of the next launch, before anything is loaded (added
   2026-10-19 while planning: swapping files under the running app would let
   its in-memory notes, settings or insights save over the restored ones):
   1. A pending folder without `ready` is deleted (a restore interrupted
      before it was checked).
   2. Create `Restore safety copy 2026-10-19 0915/` inside the library folder
      and move every included item of the current library into it.
   3. Move the restored items into the library folder.
   4. Leave `credentials.json`, `models/` and `MCP/` where they are. Delete
      `SearchIndex/` so it rebuilds.
   5. Delete the pending folder and show "Restored the backup from 17 Oct
      2026, 18:40."
6. If step 5.2 or 5.3 fails part way, move everything back before reporting
   the error. The library is either the old one or the new one, never a
   mix.
7. A backup from a newer build restores. The stores already open files with a
   newer version read-only (Insights, folders and tags), and the app says so
   as it does today.

## Safety copy

- After a restore, the Backup card shows "Safety copy from before the restore
  on 19 Oct, 9:15 · 14 MB" with **Show in Finder** and **Delete…**.
- Only the newest safety copy is kept: a second restore deletes the older one
  first, after the new restore succeeds.
- Nothing deletes a safety copy automatically.

## Automatic backup (my call)

- **Back up automatically**: Off (default), Daily, Weekly.
- Turning it on asks for a folder; the panel starts at
  `~/Documents/BugVoice Backups` (created if missing).
- BugVoice checks at launch and then every hour. A backup is due when the
  newest `*.bugvoicebackup` in the folder is older than a day (Daily) or 7
  days (Weekly), judged by the date in its file name (changed 2026-10-19 while
  planning: reading each zip's `backup.json` is slow on a network drive), or
  the folder has none.
- It runs at low priority, skips the run while a meeting records or
  transcribes, and tries again at the next hourly check.
- After a successful automatic backup, BugVoice deletes the oldest backup
  files in that folder beyond the newest 5. It deletes only files whose names
  start with `BugVoice Backup ` and end in `.bugvoicebackup`; manual backups
  saved elsewhere are never touched.
- The card shows "Last backup: today, 9:12 · 12.4 MB · Next: tomorrow".
- A failed automatic backup sets `saveError` (so the existing banner shows it)
  and logs it. If the folder is missing (an unplugged drive), the card says
  so and the next check tries again; no banner every hour, only once per
  launch.
- Settings stores `backup.schedule`, `backup.folderBookmark` (the folder as a
  bookmark, so a renamed or moved folder still resolves) and
  `backup.keep` (5, not shown in the UI).

## Where the logic lives

Following the project rule that every decision testable without a window
goes in `VoiceCore` (Foundation only, test first):

- `BackupPlan`: given a library folder listing, returns included and left out
  items, including the meeting state rule.
- `BackupManifest`: the `backup.json` model, encode and decode, and the
  "every file present with its size" check.
- `BackupSchedule`: whether a backup is due, and which files to delete beyond
  the newest N.
- `RestorePlan`: the ordered moves for a restore and the moves that undo it.
- File naming, from a date and time zone.

The macOS side (in `BugVoiceMac` or the app) runs `ditto` through the existing
`ProcessRunner`, moves files, shows panels and relaunches.

## UI copy

Plain English, no hedging, no emoji (project rule). Strings are in the mockup.

## Left to the builder

- Exact progress granularity, and whether the zip step shows its own
  progress.
- How relaunch is done (for example `open -n` on the bundle after exit).
- The disk space margin for backup (restore uses 10%).
- Whether `Back up now` runs the copy on a detached task or an actor.

## Open for the owner

These are my calls; say if any is wrong:

1. API keys stay out of backups.
2. Automatic backup exists, is off by default, keeps 5 files.
3. Restore replaces everything; no merge, no partial restore.
4. Speech models and the search index stay out.
