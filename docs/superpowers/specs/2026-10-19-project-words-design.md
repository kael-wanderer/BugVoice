# Project words

Date: 2026-10-19. Status: draft for owner review.
Mockup: `docs/design/proposal-project-words.html`.
Follows: `docs/propose-new-features.md` item 7, picked by the owner on
2026-10-19. The owner asked for the spec and mockup without a question round,
so every choice below is **my call** unless it restates an existing BugVoice
rule.

## Why

The owner dictates most often into coding agents (Orca, Ghostty, Claude
Code in a terminal, VS Code). Their prompts are full of code names:
`AppModel`, `DictationController`, `HistoryEntry.replacedBy`,
`build-app.sh`. Whisper hears these as plain words ("app model",
"dictation controller") and the cleanup model has no way to know they are
names. Today the owner would have to type each one into the Dictionary.
Project words reads the owner's repos and gives those names to speech-to-text
and cleanup automatically.

## Goals

1. **Code names come out right in coding apps.** Say "open app model plus
   models and check replace last" in Ghostty; get "open `AppModel+Models`
   and check `replaceLast`" (without the backticks unless the style adds
   them).
2. **No upkeep.** Add a folder once. Words refresh by themselves as the code
   changes.
3. **The right project.** When the window title shows which repo is open, its
   words go first.
4. **Never worse than today.** Outside coding apps nothing changes. A noisy
   word can be hidden with one click.

## Non-goals

- Reading code for meaning (comments, docs, call graphs). Only names.
- A code index or search. BugVoice does not answer questions about the repo.
- Automatic "heard as" replacements (for example always turning "app model"
  into `AppModel`). Too many false hits ("user name", "file path"); the
  cleanup model decides from context instead.
- Watching folders live (FSEvents). A daily rescan plus a Rescan button is
  enough.
- Remote repos, Git URLs, branches. Local folders only.

## Anti-goals

- A Facebook post that says `userName` because a repo has it. Project words
  stay in coding apps unless the owner turns on "All apps".
- A slow dictation. Scanning never runs on the dictation path, and the prompt
  gets a capped list.
- Reading secrets. Files that look like secrets are skipped, and only
  identifiers are kept, never file contents.

## Where the words are used

- **Coding apps:** every app with the Terminal style (Ghostty, Terminal,
  iTerm2, Warp, plus any app the owner routed to Terminal), the VS Code
  family, Cursor, Xcode (`com.apple.dt.Xcode`), Zed (`dev.zed.Zed`), Orca
  (`com.stablyai.orca`). Fixed list in VoiceCore.
- Setting **Use project words in**: Coding apps (default) / All apps / Off.
- Dictation, command mode instructions and command mode rewrites all use
  them. Meetings, Upload and the note editor do not.

## Which project

1. BugVoice reads the title of the focused window through Accessibility
   (VS Code: "AppModel.swift — BugVoice"; Ghostty and Terminal usually show
   the working folder; Orca shows the worktree).
2. A project **matches** when its name appears in the title as a whole word,
   case-insensitive, or its folder path appears in the title. A project's
   name is its folder name; the owner can rename it (Orca worktree names
   differ from the folder).
3. Several matches: the longest name wins.
4. No match: all enabled projects share the budget, interleaved by rank
   (best word of each project, then the second best, and so on).

## Extracting words

On add, on Rescan, and at launch when the last scan is older than 24 hours
(in the background, low priority):

1. **Files:** `git ls-files` in the folder when it is a Git repo (respects
   .gitignore); otherwise a walk that skips hidden folders and `node_modules`,
   `.build`, `build`, `dist`, `DerivedData`, `Pods`, `vendor`, `target`,
   `venv`, `.venv`. At most 5,000 files; files over 256 KB and binary files
   (a NUL byte in the first 8 KB) are skipped. Skipped by name: `.env*`,
   `*.pem`, `*.key`, `*credentials*`, `*secret*`.
2. **File names** of every listed file: the name without extension, split on
   `+` (`AppModel+Models.swift` gives `AppModel` and `Models`), plus script
   names with their extension when they contain `-` or `.` in the stem
   (`build-app.sh`).
3. **Identifiers** from source files (`swift m h c cc cpp rs go py rb js jsx
   ts tsx java kt cs php scala sh sql`): every token
   `[A-Za-z_][A-Za-z0-9_]{3,39}` that is **code-shaped**:
   - camelCase or PascalCase with at least two parts (`replaceLast`,
     `AppModel`), or
   - snake_case or SCREAMING_SNAKE with at least two parts (`max_tokens`,
     `API_KEY` is kept, `API` alone is not).
   Plain words (`model`, `Model`, `test`) are not kept: Whisper already
   writes them. Tokens that look like hashes or IDs (8+ hex characters only,
   or more digits than letters) are dropped.
4. **Rank:** number of files the word appears in, plus 5 when the word is
   also a file name or follows a declaration keyword (`class struct enum
   protocol actor extension func def fn type interface trait function`).
   Ties break alphabetically.
5. **Keep** the top 1,000 per project. Hidden words are never kept.

A scan of BugVoice itself (about 400 files) should take well under a second;
the 5,000-file cap bounds the worst case.

## What the models get

- **Whisper prompt** (600 characters, unchanged): the Dictionary words first,
  as today, then the active project's top words until the budget is full.
  The Vietnamese mixed example keeps its place.
- **Cleanup and command prompts:** after the existing "Spell these terms
  exactly" line, one more line:
  "Code names from the current project. When the speaker says one as plain
  words, write the name exactly (for example "app model" is AppModel): …"
  with the active project's top **150** words.
- Dictionary words always win: a Dictionary word is not repeated in the
  project list.
- No text model (provider None): only the Whisper prompt helps.

## Settings and UI

**Dictionary › Projects** (a third tab after Words and Snippets; mockup
screen 1):

- One card per project: name (editable), path, "412 words · 386 files ·
  scanned 2 h ago", an on/off switch, **Rescan**, **Remove**.
- Expanding a card lists the top words as chips with their rank; × on a chip
  hides the word (moves it to a "Hidden" row where it can be shown again);
  **Add to Dictionary** on a chip copies it into Words.
- **Add folder…** opens a folder picker. Adding the same folder twice
  selects the existing card.
- While scanning: "Scanning… 1,240 files" with a bar; errors on the card
  ("Folder not found", "No code files found").
- Footer line: "Last match: BugVoice in Ghostty, 2 min ago" so the owner can
  see the window-title match work.
- Empty state: "Add a repo folder. Its file and code names help dictation
  spell them right in Terminal, VS Code, Cursor and Orca."

**Settings › Speech:** **Use project words in** Coding apps / All apps / Off.

## Storage

`projects.json` in the BugVoice folder, tolerant decode:

```json
{ "schemaVersion": 1,
  "projects": [ { "id": "…", "path": "/Users/…/BugVoice", "name": "BugVoice",
    "enabled": true, "hidden": ["TODO_ITEM"], "scannedAt": "…",
    "fileCount": 386, "words": [ { "word": "AppModel", "rank": 61 } ] } ] }
```

- Added to `BackupPlan.rootFiles`, so a restore keeps the folder list and
  hidden words (the words themselves are rebuilt on the next scan anyway).
- A missing folder keeps its card and words, marked "Folder not found — words
  kept from the last scan", with **Locate…** (pick the moved folder) and
  **Remove**; the daily rescan skips it.
- Nothing leaves the Mac except through the cleanup model the owner
  configured, the same as Dictionary words today.

## Where the logic lives

VoiceCore (test first):

- `ProjectWordExtractor`: file list + file contents in, ranked words out.
  Pure functions: `isCodeShaped`, `fileNameWords`, `identifiers(in:)`,
  `rank`.
- `ProjectFile` / `ProjectStore`: the JSON model, tolerant decode, hide/show,
  rename.
- `ProjectMatcher`: window title + projects → active project or interleaved
  list, and the budgeted word list.
- `CodingApps`: the fixed bundle-ID list plus the Terminal-style rule.
- `Vocabulary.whisperPrompt` and `PromptBuilder` / `CommandPrompt` take the
  project words.

App: the file lister (`git ls-files` via `Process`, no shell, with a 5 s
timeout; walk fallback), background scans, the focused-window title read in
`FocusInspector`, the Projects tab, the Speech setting.

## Limits

- 20 projects. 5,000 files and 1,000 words per project. 150 words in a
  cleanup prompt.
- A scan stops after 30 seconds and keeps what it found ("Stopped after 30 s
  — 3,100 files read").

## UI copy

Plain English, no hedging, no emoji. Strings are in the mockup.

## Left to the builder

- Scan concurrency and how the 24-hour check is scheduled.
- Chip layout and how many words show before "Show all".
- Whether the walk fallback uses `FileManager.enumerator` or
  `contentsOfDirectory`.

## Open for the owner

My calls; say if any is wrong:

1. Coding apps only by default, with an All apps switch.
2. The active project comes from the window title; no match means all
   projects share the list.
3. No automatic "heard as" replacements; the cleanup model decides.
4. Daily rescan plus a Rescan button, no live folder watching.
5. Only code-shaped names (two or more parts); plain words are left to
   Whisper.
6. The Projects tab lives in Dictionary, not Settings.
