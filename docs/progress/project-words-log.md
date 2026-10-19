# Project words implementation log

Date: 2026-10-19  
Branch: `feat/project-words` (not merged or pushed)

## Commits

| Task | Commit | Message |
|---|---|---|
| 1 | `b3b7f8b` | `feat(core): project word extractor` |
| 2 | `27c0856` | `feat(core): project store and setting` |
| 3 | `5c00a25` | `feat(core): project matching and prompt words` |
| 4 | `aa9dad9` | `feat(mac): project scanner and window title` |
| 5 | `9dc35aa` | `feat(app): project words` |
| 6 | This commit | `docs: project words log and handoff` |

## Automated verification

Final `swift test` result: **1,095 VoiceCore tests, 30 MCPKit tests, and 109
BugVoiceMac tests passed**. `Scripts/build-app.sh` succeeded and signed the app
with `Bugler Local Dev`.

Test-first evidence:

- Task 1 `swift test --filter ProjectWordExtractorTests` failed to compile
  because `ProjectWordExtractor` was missing; all 9 extractor tests passed
  after implementation.
- Task 2 `swift test --filter 'ProjectStoreTests|SettingsTests|Backup'` failed
  to compile because project models were missing; the 95 filtered tests passed
  after implementation.
- Task 3 `swift test --filter 'ProjectMatcherTests|PromptTests|CommandPromptTests|VocabularyTests|DictationPipelineTests'`
  failed to compile because matcher and focus-title interfaces were missing;
  all 101 filtered tests passed after implementation.
- Task 4 `swift test --filter ProjectScannerTests` failed to compile because
  `ProjectScanner` was missing; all 8 scanner tests passed after implementation.

## Deviations

- The plan's `fileNames` fixture requires `AppModel+Models.swift` to yield both
  `AppModel` and `Models`. `Models` alone does not meet the two-part
  code-shaped-token rule, so `fileNameWords` keeps title-case components of a
  `+`-separated source filename. Other plain single-part file stems such as
  `README` and `HANDOFF` remain excluded.
- The Task 5 read-only UI smoke could not be observed: after launch,
  `orca computer` returned `app_not_found` for the app name, and the CUA app
  selector returned `Computer Use was not approved to use BugVoice`. No access
  restriction was bypassed.

## Device checks

| Check | Result | Evidence |
|---|---|---|
| P1 Add BugVoice folder and verify scan duration and words | Not run | Adds a project and scans the repository; this changes the app library. |
| P2 Dictate the BugVoice sentence in Ghostty | Not run | Requires synthetic dictation and pastes into the focused app. |
| P3 Dictate the sentence in Notes or Facebook | Not run | Requires synthetic dictation; Facebook would receive pasted text. |
| P4 Hide, rescan, and restore a word | Not run | Changes project settings and triggers a rescan. |
| P5 Rename an Orca worktree and dictate | Not run | Changes project settings and requires synthetic dictation. |
| P6 Move a folder and use Locate | Not run | Moves a folder and changes its saved project path. |
| P7 Command mode in VS Code | Not run | Requires command-mode dictation and may paste into the focused app. |
| P8 Back up and restore the project list | Not run | Restore changes app data; the check is not read-only. |

Task 5 smoke checks for Dictionary › Projects empty state and Settings › Speech
row: **Not run**. The dev app process launched successfully, but computer-use
access to BugVoice was denied before either view could be inspected. The
Application Support data was restored from `/private/tmp/bv-before-codex`
after launch; temporary backup copies were removed.
