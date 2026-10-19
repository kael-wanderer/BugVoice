# Action Items Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. If neither skill is installed, execute the plan directly, task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One checkable list of every meeting's action items, with done state that survives Regenerate, shown on a new page, on each meeting's tab, and through MCP.

**Architecture:** VoiceCore parses `MeetingManifest.actionItems` Markdown into items with an owner and a stable key, stores only done keys in `action-items.json`, and builds filtered groups and the Copy Markdown (all test-first). The app adds the Action items page, turns the meeting tab into the same checklist, and wires a read-only MCP tool.

**Tech Stack:** Swift 6 package, macOS 15, SwiftUI, Swift Testing. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-19-action-items-design.md` (mockup `docs/design/proposal-action-items.html`).

## Global Constraints

- `VoiceCore` imports Foundation only. TDD for VoiceCore. `swift test` passes before every commit.
- No new dependency. Items are never added or edited by hand; the page reads the meeting's current text, only done state is stored.
- Key = meeting id + item text lowercased with whitespace collapsed (owner included).
- `action-items.json`: done entries only; entries of deleted meetings removed at load; at most 5,000 entries, oldest `doneAt` dropped; in `BackupPlan.rootFiles`.
- Checked row stays 2 s with Undo in the Open view.
- MCP `list_action_items`: `status` open (default) / done / all, `limit` default 50 max 200, optional `meeting`; read-only.
- UI copy: plain English, no hedging, no emoji; strings from the mockup and spec.
- Commit after each task; the pre-commit hook raises the build, never edit CFBundleVersion.

## Review Focus

1. Regenerate returns the same item with different bullet or checkbox markup (`* [ ] X` vs `- X`): still done (Task 1 test `keyIgnoresMarkup`).
2. Two meetings with the same item text: checking one does not check the other (Task 2 test `sameTextOtherMeetingIndependent`).
3. A sentence with a colon that is not an owner ("Note: update the docs", "Follow up: pricing") must not become owner "Note" (Task 1 test `colonPhraseNotOwner`).
4. A meeting with no action items text or only "No action items" produces no group and no crash (Task 3 test `meetingsWithoutItemsSkipped`).
5. Done items of a meeting whose items were regenerated with new wording stay stored but do not show (Task 3 test `staleDoneNotShown`).

---

### Task 1: Parser

**Files:**
- Create: `Sources/VoiceCore/ActionItems.swift`
- Test: `Tests/VoiceCoreTests/ActionItemParserTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct ActionItem: Equatable, Sendable, Identifiable {
      public var meetingID: MeetingID; public var text: String; public var owner: String?; public var key: String
      public var id: String { meetingID.rawValue + "|" + key }
  }
  public struct ParsedActionItems: Equatable, Sendable { public var items: [ActionItem]; public var otherLines: [String] }
  public enum ActionItemParser {
      public static func parse(_ markdown: String?, meetingID: MeetingID) -> ParsedActionItems
      public static func key(_ line: String) -> String     // markers, checkbox, ** removed; lowercased; whitespace collapsed
  }
  ```
  Item line: after leading spaces starts with `-`, `*`, `•` or `\d+[.)]` then a space. Remove the marker, a leading `[ ]`/`[x]`/`[X]`, all `**`, collapse whitespace. Owner rules, tried in order (name = 1–3 words, each starting with an uppercase letter, letters only incl. Vietnamese):
  1. `Name: rest` / `Name — rest` / `Name - rest` at the start, **and** the name is not one of `Note`, `Follow up`, `Next step`, `Next steps`, `Todo`, `TODO`, `Action`, `Decision`, `Owner`.
  2. `rest (owner: Name)` or `rest (Name)` at the end.
  3. `rest — Name` at the end.
  The shown `text` has the owner part and surrounding punctuation removed. `key` is computed from the cleaned full line **before** removing the owner (owner included), so "(Kael)" vs "Kael:" are different keys only when the text differs.
  Non-item, non-empty lines go to `otherLines` (trimmed), except lines equal (case-insensitive) to "No action items" or "None".

- [ ] **Step 1: Write the failing tests**
  - `bullets`: `"- Send the build\n* Check crash rate\n• Book review\n1. Share report\n2) Read notes"` → 5 items, texts as written after the marker.
  - `ownerShapes`: `"- Kael: send the build to QA"` → text `"send the build to QA"`, owner `"Kael"`; `"* **Tuấn** — check the crash rate"` → owner `"Tuấn"`; `"1. Share the report (owner: Linh)"` → `"Share the report"`, `"Linh"`; `"- [ ] Book a design review — Minh Anh"` → `"Book a design review"`, `"Minh Anh"`; `"- Ask (Kael)"` → `"Ask"`, `"Kael"`.
  - `colonPhraseNotOwner`: `"- Note: update the docs"` and `"- Follow up: pricing"` → owner nil, text unchanged.
  - `noOwner`: `"- Read the streaming notes"` → owner nil.
  - `keyIgnoresMarkup`: keys equal for `"- Send X (Kael)"`, `"* [ ] Send  X (Kael)"`, `"1. **Send** X (Kael)"`; different from `"- Send Y (Kael)"`.
  - `otherLinesKept`: `"## Next steps\n- A\nNo action items\n\nThanks"` → items `[A]`, otherLines `["## Next steps", "Thanks"]`.
  - `nilAndEmpty`: nil and `""` → no items, no other lines.
- [ ] **Step 2: Run** `swift test --filter ActionItemParserTests` — compile failure.
- [ ] **Step 3: Implement** in `Sources/VoiceCore/ActionItems.swift`.
- [ ] **Step 4: Run tests** — PASS; full `swift test`.
- [ ] **Step 5: Commit** `feat(core): action item parser`

### Task 2: Done store

**Files:**
- Modify: `Sources/VoiceCore/ActionItems.swift`, `Sources/VoiceCore/AppPaths.swift` (`actionItems` → `action-items.json`), `Sources/VoiceCore/BackupPlan.swift` (`rootFiles` gains `"action-items.json"`)
- Test: `Tests/VoiceCoreTests/ActionItemFileTests.swift`, the backup test covering `rootFiles`

**Interfaces:**
- Consumes: `ActionItem`.
- Produces:
  ```swift
  public struct DoneActionItem: Codable, Equatable, Sendable { public var meetingID: MeetingID; public var key: String; public var doneAt: Date }
  public struct ActionItemFile: Codable, Equatable, Sendable {
      public static let supportedSchemaVersion = 1; public static let maxEntries = 5_000
      public var schemaVersion: Int; public var done: [DoneActionItem]
      public func doneAt(_ item: ActionItem) -> Date?
      public mutating func setDone(_ item: ActionItem, _ done: Bool, at: Date)
      public mutating func prune(keeping meetings: Set<MeetingID>)
  }
  public actor ActionItemStore { public init(url: URL); public func load() -> ActionItemFile; public func save(_ file: ActionItemFile, revision: Int?) throws }
  ```
- [ ] **Step 1: Write the failing tests:** `setAndClear`, `sameTextOtherMeetingIndependent`, `doneTwiceKeepsFirstDate`, `pruneRemovesDeletedMeetings`, `capDropsOldest` (5,001 → 5,000, oldest `doneAt` gone), `roundTripAndTolerantDecode` (`{"done":[{"meetingID":"m","key":"k","doneAt":"2026-10-19T00:00:00Z"}]}` with ISO-8601 dates), `storeSurvivesCorruptFile` (moved to `action-items.corrupt-<unix>.json`), `olderRevisionIsIgnored`; backup includes `action-items.json`.
- [ ] **Step 2: Run** — failures. **Step 3: Implement** (store like `ProjectStore`: atomic write, revision check; encoder and decoder use `.iso8601` dates).
- [ ] **Step 4: Run tests** — PASS; full `swift test`.
- [ ] **Step 5: Commit** `feat(core): action item done store`

### Task 3: Board and Copy

**Files:**
- Modify: `Sources/VoiceCore/ActionItems.swift`
- Test: `Tests/VoiceCoreTests/ActionItemBoardTests.swift`

**Interfaces:**
- Consumes: Tasks 1–2, `MeetingManifest` (`id`, `title`, `startedAt`, `actionItems`).
- Produces:
  ```swift
  public enum ActionItemStatus: String, CaseIterable, Sendable { case open, done, all }
  public enum ActionItemOwnerFilter: Hashable, Sendable { case anyone, owner(String), none }
  public enum ActionItemRange: CaseIterable, Sendable { case week, month, all }   // Last 7 days / Last 30 days / All time, by meeting startedAt
  public struct ActionItemRow: Equatable, Sendable, Identifiable { public var item: ActionItem; public var doneAt: Date?; public var id: String { item.id } }
  public struct ActionItemGroup: Equatable, Sendable, Identifiable {
      public var meetingID: MeetingID; public var title: String; public var date: Date; public var rows: [ActionItemRow]
      public var openCount: Int; public var doneCount: Int; public var id: MeetingID { meetingID }
  }
  public struct ActionItemBoard: Equatable, Sendable {
      public var groups: [ActionItemGroup]; public var openTotal: Int; public var doneTotal: Int; public var owners: [String]
      public init(meetings: [MeetingManifest], done: ActionItemFile, status: ActionItemStatus, owner: ActionItemOwnerFilter,
                  range: ActionItemRange, query: String, now: Date, keepVisible: Set<String> = [])
      public func copyMarkdown() -> String
  }
  ```
  Totals and `owners` (sorted, unique) count every item regardless of filters. `query` matches item text or meeting title, case- and diacritic-insensitive. `keepVisible` holds row ids just checked, so they stay in the Open view for 2 s. Groups newest meeting first, rows in the meeting's order; empty groups dropped. `copyMarkdown` uses only open rows in the current groups: `## <title> — <d MMM>` then `- [ ] <text>` + ` (<owner>)` when present, groups separated by a blank line.
- [ ] **Step 1: Write the failing tests:** `groupsNewestFirst`, `openDoneAllFilters`, `ownerFilter` (owner and `.none`), `rangeFilter` (meeting 10 days ago hidden for `.week`, shown for `.month`), `queryMatchesTitleAndText` ("tuan" finds "Tuấn"), `keepVisibleStaysInOpen`, `meetingsWithoutItemsSkipped` (nil, `""`, "No action items"), `staleDoneNotShown` (done key absent from current text → no row, `doneTotal` excludes it), `totalsIgnoreFilters`, `copyMarkdownFormat` (exact string with the mockup's example, date "13 Oct" with locale `en_US_POSIX`).
- [ ] **Step 2: Run** — failures. **Step 3: Implement.** **Step 4: Run tests** — PASS; full `swift test`.
- [ ] **Step 5: Commit** `feat(core): action item board`

### Task 4: MCP tool

**Files:**
- Modify: `Sources/VoiceCore/MCP/MCPTools.swift` (`case listActionItems = "list_action_items"`; `MCPCall.listActionItems(status: ActionItemStatus, meeting: String?, limit: Int)`; descriptor "List action items from meetings, newest meeting first." with `status` "open, done or all. Default open.", `meeting` "Meeting id.", `limit` "Most items to return, 1 to 200. Default 50."), `Sources/VoiceCore/MCP/MCPReplyLimit.swift` (same class as `listMeetings`), `Sources/VoiceCore/MCP/MCPFormat.swift` (item JSON), `Sources/BugVoice/MCPService.swift`
- Test: `Tests/VoiceCoreTests/MCPToolsTests.swift`

- [ ] **Step 1: Write the failing tests:** `listActionItemsDefaults` (no arguments → `.open`, nil, 50), `listActionItemsRejectsBadStatus` ("later" → argument error), `listActionItemsLimitBounds` (0 and 201 rejected like `listMeetings`), `actionItemFormat` (keys `meeting_id`, `meeting_title`, `meeting_date` YYYY-MM-DD, `text`, `owner` null when nil, `done`, `done_at` null or ISO-8601).
- [ ] **Step 2: Run** — failures. **Step 3: Implement**; `MCPService` builds an `ActionItemBoard` with `owner: .anyone`, `range: .all`, `query: ""`, filters by meeting id when given, flattens rows up to `limit`. **Step 4:** full `swift test`.
- [ ] **Step 5: Commit** `feat(core): list_action_items MCP tool`

### Task 5: App

**Files:**
- Create: `Sources/BugVoice/UI/ActionItemsPage.swift`, `Sources/BugVoice/UI/ActionItemRowView.swift`
- Modify: `Sources/BugVoice/AppModel.swift` (`Page.actions` title "Action items", symbol `checklist`, placed after `.meetings` in the sidebar; `actionItemsDone: ActionItemFile` loaded at bootstrap and pruned with the current meeting ids; `setActionItemDone(_:_:)` saving with a revision; `openMeetingActionItems(_ id: MeetingID)` reusing the search-hit routing to the meeting with `meetingDetailTab = .actionItems`), `Sources/BugVoice/UI/MainWindow.swift`, `Sources/BugVoice/UI/Shell/SearchField.swift` / `PageActions.swift` (prompt "Search action items"; the field filters the page, it does not open global search), `Sources/BugVoice/UI/MeetingsPage.swift` (Action items tab)

- [ ] **Step 1: Page** per mockup screen 1–3: header "Action items" with "12 open · 30 done"; pills Open / Done / All; menus "Owner: Anyone" (Anyone, owners, No owner) and "Meetings from: All time" (Last 7 days, Last 30 days, All time); **Copy open items** (writes `copyMarkdown()` to the general pasteboard; HUD-free, button label shows "Copied" for 1.5 s); groups with clickable title → `openMeetingActionItems`, "Mon 13 Oct · 3 open"; rows with checkbox, text, owner chip; done rows struck through with "Done 14 Oct" in Done and All; a row checked in Open shows "Done · Undo" for 2 s (`keepVisible`), Undo unchecks; empty states "No action items yet" / "Generate them on a meeting's Action items tab.", "Nothing open" / "Good work.", "No items match.".
- [ ] **Step 2: Meeting tab:** replace the plain `Text` of action items with `ActionItemRowView` rows from `ActionItemParser.parse` sharing `setActionItemDone`; `otherLines` below as plain text; footnote "Checkmarks are shared with the Action items page and kept after Regenerate when an item's text is the same."; Generate / Regenerate / Send to Scratchpad unchanged.
- [ ] **Step 3:** `swift test`, `Scripts/build-app.sh`; read-only smoke on the second display: the Action items page and one meeting's Action items tab render (no checkbox clicked unless the library is restored afterwards).
- [ ] **Step 4: Commit** `feat(app): action items page`

### Task 6: Docs and device checks

**Files:**
- Create: `docs/progress/action-items-log.md`
- Modify: `AGENTS.md` (plan and log lines), `docs/progress/HANDOFF.md`, `docs/propose-new-features.md` (item 5 status)

- [ ] **Step 1:** Log: commits, test counts per target, deviations, then device checks with Result / Evidence:
  - A1 Page lists items from several real meetings, newest first, with owners.
  - A2 Check an item: 2 s with Undo, then gone from Open; shown in Done with today's date.
  - A3 Meeting tab shows the same checkmark; checking there updates the page.
  - A4 Regenerate a meeting's items: unchanged items stay checked.
  - A5 Owner and range filters, and search by Vietnamese name without accents.
  - A6 Copy open items pastes the Markdown in Notion or Obsidian.
  - A7 Meeting title opens the meeting on its Action items tab.
  - A8 Delete a meeting: its items leave the page; relaunch keeps other checkmarks.
  - A9 `list_action_items` from Claude Code returns open items.
  - A10 Light and dark match the mockup; backup and restore keep checkmarks.
- [ ] **Step 2:** `swift test`; commit `docs: action items log and handoff`.
