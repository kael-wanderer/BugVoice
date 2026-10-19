# Action items execution log

Branch: `feat/action-items`, based on `main`. No merge or push.
Plan: `docs/superpowers/plans/2026-10-19-action-items.md`.
Spec and mockup read before implementation. Superpowers skills unavailable;
executed the plan directly, task by task.

## Tasks and automated evidence

| Task | Commit | VoiceCore | MCPKit | BugVoiceMac | Evidence |
|---|---|---:|---:|---:|---|
| 1 Parser | `e46df52` | 1,139 | 30 | 114 | Seven listed tests first failed to compile: ActionItemParser absent. Full suite passed after implementation. |
| 2 Done store | `5ccaa41` | 1,147 | 30 | 114 | Eight listed tests and backup allowlist updated first; compile failed: ActionItemFile absent. Full suite passed after implementation. |
| 3 Board and Copy | `4d12d99` | 1,157 | 30 | 114 | Ten listed tests first failed to compile: ActionItemBoard absent. Full suite passed after implementation. |
| 4 MCP tool | `14f935a` | 1,161 | 30 | 114 | Four listed tests first failed to compile: MCPCall.listActionItems absent. Updated both tool-count assertions from 12 to 13. Full suite passed. |
| 5 App | `66b0b52` | 1,162 | 30 | 114 | Shared state, sidebar, local search, filters, copy feedback, Undo and meeting routing. |
| 6 Docs | This log's commit | 1,162 | 30 | 114 | Final full suite and device evidence below. |

Every commit follows a full passing `swift test`. The pre-commit hook alone
raises the build. No new dependencies. VoiceCore imports Foundation only.

## Deviations and integration details

- Task 4 says 201 is rejected “like listMeetings”, but the existing list tools
  clamp high limits. The new tool follows the explicit 0/201 rejection tests;
  existing tools retain their behavior.
- `SearchHit` has an internal initializer. Extracted the existing meeting
  search-hit routing into a private shared helper in AppModel and called it
  from `openMeetingActionItems`, without changing the VoiceCore interface.
- During Task 5 review, added a failing repeated-bullets regression test and
  removed deduplication from the board: totals must count every current item.
  The UI uses row offsets so repeated keys do not collide in SwiftUI.
- Added the title-bar totals in `UI/Shell/TitleBar.swift` (not in the plan's
  file list) to keep the mockup's title, counts and search together.

## Device checks

Only read-only checks are authorized. No synthetic hotkey holds, paste-producing
clicks, Return key, checkbox changes, generation, deletion, backup/restore UI,
or external text transmission are used.

| Check | Result | Evidence / reason |
|---|---|---|
| A1 Several real meetings, newest first, owners | Not run | Inspected 13 real meeting manifests: none has action-items text. Generating data is outside the read-only scope. |
| A2 Check, two-second Undo, Done date | Not run | Changes done state; read-only checks only. Unit tests cover filtering and retained rows, not elapsed UI behavior. |
| A3 Shared meeting/page checkmarks | Not run | Requires changing a checkbox; read-only checks only. |
| A4 Regenerate retains checkmarks | Not run | Regenerate writes meeting text and invokes a model; read-only checks only. Parser tests cover markup-stable keys. |
| A5 Owner/range filters and Vietnamese search | Not run | No real items or owners available to validate filtered results. Board tests cover owners/ranges and diacritic-insensitive item/title search. |
| A6 Paste Markdown in Notion/Obsidian | Not run | Requires clipboard write and paste into another app; prohibited during this run. Exact Markdown is unit-tested. |
| A7 Title opens Action items tab | Not run | No populated group/title in the real library. Meeting-tab smoke evidence recorded separately. |
| A8 Delete/relaunch preserves other checkmarks | Not run | Requires deleting a real meeting and changing done state; read-only checks only. Pruning and persistence are unit-tested. |
| A9 Claude Code list_action_items | Not run | MCP is disabled in the owner’s settings. A real bundled bridge call with default arguments returned “MCP is off. Turn it on in BugVoice Settings › Agents.” It remains disabled; no Claude Code integration pass claimed. |
| A10 Light/dark and backup/restore | Not run | Full check requires settings writes and backup/restore. Backup inclusion is unit-tested; no device pass inferred. |

## Read-only app smoke evidence

`Scripts/build-app.sh` completed with `Signed with: Bugler Local Dev`.
Launched through `Scripts/run-dev-app.sh`; reopened the existing process with an
Apple event to show the main window. No bare `open` command was used.

Before capture/click, enumerated displays and the app window: screen 0 is
x=0…2560; screen 1 is x=2560…5120. BugVoice window 10925 was on screen 1,
at x=2925, y=153, size 1830 × 1164. Captured the app window itself through
computer-use, not a screen region.

Observed in the dark theme:

- Sidebar entry immediately after Meetings; Action items header, `0 open · 0
  done`, `Search action items`, Open/Done/All pills, both filter menus, disabled
  Copy open items, and the exact no-items title and message.
- Selected a real meeting without playing audio; opened its Action items tab.
  Observed “No action items”, the existing Generate action items button
  (disabled for that meeting's empty transcript), and the full shared-checkmarks
  footnote. No checkbox, generation, recording, Copy or paste action was used.

This verifies Task 5's empty page/tab rendering only, not A1's populated rows,
A7's group-title routing, or A10's two themes and restore behavior. Temporary
screenshots are removed after inspection to avoid keeping private library text.

## Data protection and cleanup

Before launch, copied the owner's complete Application Support/BugVoice folder
to `/private/tmp/bv-before-codex` and recorded SHA-256 hashes for 190 files.
After smoke checks, the Quit Apple event did not exit within ten seconds;
SIGTERM stopped the dev process. Removed the modified run directory and
restored the backup. Verified the complete relative-file set and SHA-256 hashes:
all 190 files match. Deleted the temporary backup after verification. No dev app
remains running. Temporary test/build logs and inspection screenshots are
removed at completion.

## Review fixes (2026-10-19)

- The parser keeps the first of items with the same key (the same text with
  different markup, `**Send** X` and `Send X`). Two rows with one key shared an
  id and a checkmark. Test `duplicateKeysDropped`; Codex's
  `repeatedBulletsCountEveryItem` became `repeatedBulletsShowOnce`.
- Launch pruning is skipped when no meetings loaded, so a failed meeting load
  cannot erase every checkmark.
- Rows are identified by item id instead of position, so a checked row
  leaving the Open view does not shift the state of the rows after it.
