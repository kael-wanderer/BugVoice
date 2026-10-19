# Action items across meetings

Date: 2026-10-19. Status: draft for owner review.
Mockup: `docs/design/proposal-action-items.html`.
Follows: `docs/propose-new-features.md` item 5, picked by the owner on
2026-10-19. The owner asked for the spec and mockup without a question round,
so every choice below is **my call** unless it restates an existing BugVoice
rule.

## Why

Each meeting can generate its action items, but they stay inside that
meeting's Action items tab as plain Markdown. To know what is still open the
owner has to open meeting after meeting, and nothing records what is done.
One list across all meetings, with a checkbox per item, turns the generated
bullets into a to-do list the owner can actually work from.

## Goals

1. **One list.** Every meeting's action items on one page, grouped by
   meeting, newest meeting first.
2. **Check them off.** Each item has a checkbox; done items move out of the
   Open view and keep the date they were done.
3. **Back to the source.** The meeting header opens that meeting on its
   Action items tab.
4. **Survives Regenerate.** Regenerating a meeting's action items keeps the
   done state of every item whose text did not change.
5. **Agents can read it.** The MCP server lists open items.

## Non-goals

- Adding, editing or deleting items by hand. Items come from meetings; the
  owner can edit the meeting's text by regenerating.
- Due dates, reminders, priorities, Apple Reminders or Things export.
- Assigning owners. The owner shown is whatever the model wrote.
- Action items from Scratchpad notes or dictations.

## Anti-goals

- Losing checkmarks when a meeting's items are regenerated with the same
  text.
- A second copy of the item text that drifts from the meeting. The page
  always reads the meeting's current text; only done state is stored.

## Reading items from a meeting

`meeting.actionItems` is Markdown produced by the model ("Extract action
items as concise Markdown bullets. Include an owner only when stated.").
Parsing, per line:

- A line is an item when it starts with `-`, `*`, `•` or `1.`-style
  numbering (after leading spaces). Other lines (headings, blank lines,
  "No action items") are ignored.
- The marker and a checkbox (`[ ]`, `[x]`, `[X]`) are removed; `**bold**`
  markers are removed; whitespace is collapsed.
- **Owner**, when the text has one of these shapes (names are 1–3 words, each
  starting with a capital letter):
  - `Kael: send the build` or `Kael — send the build` or `Kael - send …`
  - `Send the build (Kael)` or `Send the build (owner: Kael)`
  - `Send the build — Kael`
  The owner is removed from the shown text and shown as a chip.
- **Key** of an item: the meeting id plus the item text lowercased with
  whitespace collapsed (owner included). Done state is stored by key, so the
  same text after Regenerate keeps its state; changed text is a new open
  item.

## The Action items page

A new sidebar page **Action items** (symbol `checklist`), right after
Meetings (mockup screen 1).

- Header: "Action items", "12 open · 30 done".
- Filters: **Open** (default) / **Done** / **All**; **Owner** menu (Anyone,
  each owner found, No owner); **Meetings from** Last 7 days / Last 30 days
  / All time (default All time). The page's search field filters by item
  text and meeting title.
- Groups: one per meeting with matching items, newest meeting first. Header:
  meeting title, date, "4 open" — clicking it opens the meeting on its
  Action items tab.
- Rows: checkbox, item text, owner chip. Done rows (Done and All views) are
  struck through with "Done 14 Oct".
- Checking an item in the Open view keeps the row for 2 seconds (with an
  Undo link) before it leaves the view.
- **Copy open items**: Markdown of the visible open items grouped by meeting
  (`## Weekly sync — 13 Oct` then `- [ ] item (Kael)`).
- Empty states: no items at all → "No action items yet. Generate them on a
  meeting's Action items tab."; filters leave nothing → "Nothing open. Good
  work." for Open, "No items match." otherwise.

## The meeting's Action items tab

The tab shows the same parsed items as checkbox rows (sharing the done state)
instead of plain text (mockup screen 2). Generate / Regenerate / Send to
Scratchpad stay. Lines that are not items are shown under the list as
plain text so nothing the model wrote is hidden.

## MCP

A read-only tool `list_action_items`:

- Arguments: `status` (`open` default, `done`, `all`), `limit` (default 50,
  max 200), `meeting` (optional meeting id).
- Returns items with `meeting_id`, `meeting_title`, `meeting_date`, `text`,
  `owner`, `done`, `done_at`.
- Same exposure rules as the existing meeting tools.

## Storage

`action-items.json` in the BugVoice folder, tolerant decode:

```json
{ "schemaVersion": 1,
  "done": [ { "meetingID": "…", "key": "send the build to qa (kael)",
              "doneAt": "…" } ] }
```

- Only done items are stored; everything else is derived from meetings.
- Entries for a deleted meeting are removed at load.
- Entries whose key no longer appears in the meeting are kept (the text may
  come back after another Regenerate) up to 5,000 entries, oldest dropped.
- Added to `BackupPlan.rootFiles`.

## Where the logic lives

VoiceCore (test first):

- `ActionItemParser.items(in:)`: lines to `ActionItem` (text, owner, key).
- `ActionItemFile`: done set, toggle, prune deleted meetings, cap;
  `ActionItemStore` actor.
- `ActionItemBoard`: meetings + done file + filters → groups and counts, and
  the Copy Markdown.
- MCP: `list_action_items` argument checks and formatting next to the
  existing meeting tools.

App: the page, the sidebar entry, the meeting tab rows, Undo, routing to the
meeting tab.

## UI copy

Plain English, no hedging, no emoji. Strings are in the mockup.

## Left to the builder

- Row layout and spacing within the mockup.
- How the 2-second stay of a checked row is animated.

## Open for the owner

My calls; say if any is wrong:

1. A new sidebar page, not a tab inside Meetings.
2. Items cannot be added or edited by hand.
3. A changed item text after Regenerate counts as a new open item.
4. The meeting's own Action items tab becomes the same checklist.
5. MCP gets a read-only `list_action_items`.
