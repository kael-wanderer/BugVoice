# App shell — design

Date: 2026-10-18. Status: draft for owner review.

Mockup: `docs/design/proposal-appearance.html#shell` (open in a browser; the
`#shell` view shows this round: Integrations and Help as Coming soon pages,
Agents still in Settings). Without `#shell` the same file shows the later
rounds too.

Follows the appearance foundation
(`docs/superpowers/specs/2026-10-18-appearance-foundation-design.md`, merged as
`fb6d092`). Its "Follow-up specs" section holds the owner's earlier decisions
for this round; this document turns them into a buildable design.

## Why

The foundation made fonts, colors, and text size consistent, but the window
still looks like the old app: a flat list of eight pages, a title repeated
inside each page, Settings tabs in a row that wraps at large text, and content
pinned to the left edge. The owner works in BugVoice 8 to 12 hours a day and
wants the window from the mockup: pages grouped by what they are for, one
title bar with search and the page's main action, and content that sits in
the middle of the window at any width and text size.

## Goals

1. Sidebar with groups, full window height, Settings and Help at the bottom.
2. A title bar for the right panel: sidebar button, page title, search, page
   action.
3. Search everything (⌘K) across notes, meetings, and dictations.
4. Hide and show the sidebar (button and ⌃⌘S).
5. Section lists: Meetings and Scratchpad get a full-height list pane;
   Settings and Style get a vertical list inside the page.
6. One control for views and filters: equal-width round pills.
7. Content centered in the right panel.
8. Integrations and Help pages that say Coming soon.

## Non-goals (later specs)

- Integrations content (Calendar, export, MCP moving out of Settings).
- Help content.
- Style redesign: cards, first-run setup, "Run setup again", merging
  Document into Other, Coding/Other renames.
- Menu bar popover.
- A note editor in the main window. Editing stays in the floating Scratchpad
  window this round; the main window shows a read-only preview (owner,
  2026-10-18: "B first, we will do A later").

## Anti-goals

- Anything clipped or overlapping at 160% text or at the 820 pt minimum window
  width. The foundation fixed these once; this round must not bring them back.
- Search that sends text off the Mac or needs a text model. It is keyword
  search over local files.
- Losing a feature a page has today (Meetings Stop and Transcribing state,
  Scratchpad "Open window", folder and tag filters, sort).

## Constraints

- Swift package, tools 6.0, macOS 15 floor. `VoiceCore` imports Foundation
  only; TDD for everything in `VoiceCore`.
- No new dependencies.
- Every font, color, and spacing value comes from the foundation tokens
  (`.bvFont`, `.bv…` colors, `LayoutTokens.spacing`, `store.scaled`).
  `Scripts/check-tokens.sh` must stay clean.
- UI copy: plain English, no hedging, no emoji.
- The main window stays AppKit-owned (`MainWindowController`) with
  `.fullSizeContentView` and a transparent, hidden title.

## Window layout

Two panels side by side, split by a 1 pt `separator` line:

```
┌──────────────┬───────────────────────────────────────────────────────────┐
│ ● ● ●        │ [▯] Title          [ 🔍 Search notes, meetings…  ⌘K ]  [Action ▾] │
│ [icon] BugVoice ├───────────────────────────────────────────────────────────┤
│ CAPTURE      │                                                           │
│  Dictation   │                      page content                         │
│  Insights    │                                                           │
│ LIBRARY      │                                                           │
│  Meetings    │                                                           │
│  Scratchpad  │                                                           │
│  Upload      │                                                           │
│ PERSONALIZE  │                                                           │
│  Style       │                                                           │
│  Dictionary  │                                                           │
│ CONNECT      │                                                           │
│  Integrations│                                                           │
│      …       │                                                           │
│  Settings    │                                                           │
│  Help        │                                                           │
└──────────────┴───────────────────────────────────────────────────────────┘
```

- Replace `NavigationSplitView` with an own two-panel layout, so the title bar
  belongs to the right panel and the sidebar can run under the window buttons.
  (Builder's call: `HStack` or an `NSSplitView`; the sidebar width is fixed,
  not draggable.)
- Sidebar width `scaled(200)`, background `sidebar`.

### Sidebar

Top to bottom:
1. Space for the window buttons (close, minimize, zoom), which stay where macOS
   draws them.
2. Brand: the chosen app icon (`settings.appearance.appIcon`, 24 pt scaled,
   rounded) and "BugVoice", `title3`.
3. Groups, each with a caption heading (`caption`, `secondaryText`, upper case):
   - Capture: Dictation, Insights
   - Library: Meetings, Scratchpad, Upload
   - Personalize: Style, Dictionary
   - Connect: Integrations
4. Flexible space.
5. Settings, Help (no heading).

Rows keep today's icon-plus-title layout (icon frame `scaled(20)`), `body`
font. The Upload row keeps its progress ring. Selected row: `accentSoft` fill
and an accent border at 55% opacity, semibold title; this is separate from
the keyboard focus ring. The list scrolls when it does not fit (160% on a short
window) and Settings and Help then follow the last group instead of being
pinned.

`Page` gains `integrations` and `help` (titles "Integrations", "Help"; symbols
builder's call). Sidebar order is the group order above, not `allCases`
order.

### Title bar (right panel)

One row, `scaled(52)` minimum height, bottom `separator` line, three columns:
- Left: when the sidebar is hidden, space for the window buttons first; then
  the sidebar button (`sidebar.left`, plain icon button, help text "Hide
  sidebar ⌃⌘S" or "Show sidebar ⌃⌘S"); then the page title, `title2`, one
  line, truncates.
- Center: the search field, `scaled(460)` wide, centered in the right panel
  (left and right columns take equal flexible width). It shrinks when the
  panel is narrow; below `scaled(200)` it becomes a search icon button that
  opens the same results.
- Right: the page action, right aligned.

The title bar is also the window's drag area (double-click zooms, as in any
Mac title bar). No subtitle.

Pages stop drawing their own `title2` heading ("Dictation", "Meetings",
"Scratchpad", "Upload", "Style", "Dictionary", "Insights", "Settings").
`navigationTitle` and `.searchable` go away with `NavigationSplitView`.

### Page actions

| Page | Right slot |
|---|---|
| Dictation | Status chip: green dot, "Hold <hotkey> to speak" (`settings.hotkey.spokenName`), `footnote`. When a permission is missing, an orange dot and "Permissions needed", which opens the permissions window. |
| Insights | Range pills 7 days, 30 days, All time (small size). |
| Meetings | Split button `● Record meeting ▾`: main part starts a meeting; menu: Record meeting ⌃⌥M, Upload a recording… (goes to Upload). While recording or paused: a Stop button. While transcribing: "Transcribing…" label. Same states as today's header. |
| Scratchpad | Split button `+ New note ▾`: main part makes a new note (opens it in the floating window, as today's New note button); menu: Note ⌘N, Floating scratchpad ⌃⌥N, a divider, Ask AI about my notes. |
| Upload | Choose files… (today's file picker). |
| Style | Nothing this round. |
| Dictionary | Split button `+ Add ▾`: menu Word, Snippet; main part adds whichever the visible list holds. |
| Settings, Integrations, Help | Nothing. |

"Ask AI about my notes" opens the floating Scratchpad (the active note, or a
new one when none is open), shows its AI bar with the scope set to all notes,
and focuses the question field. *(My call; the mockup has the item.)*

Split button: primary style; the caret part opens a menu. Menu shortcuts show
on the right. Builder's call how (SwiftUI `Menu` with `primaryAction`, or two
buttons).

Insights drops its Usage/Details tabs: Details was disabled ("Later") and Usage
is the only view. The "Local" label stays inside the page.

## Search everything (⌘K)

- The title bar field. ⌘K focuses it while the main window is key. The main
  window has no note editor this round, so there is no clash with the
  Markdown toolbar's ⌘K (link), which lives in the floating Scratchpad
  window and keeps working there. Sheets over the main window take ⌘K away
  (nothing happens).
- Placeholder "Search notes, meetings, dictations". A `⌘K` hint sits at the
  right end of the field while it is empty.
- Typing shows a results panel under the field, same width (at least
  `scaled(320)`), up to 8 results, updated as the owner types (debounce about
  150 ms). Empty field: no panel.
- Each result: title (`bodyStrong`) and one line below (`footnote`,
  `secondaryText`): kind, and a short snippet of the matching text. Kinds:
  - Meeting: meeting title; snippet from transcript, summary, action items, or
    notes. Meeting titles are matched too, including meetings that are still
    recording or transcribing (they have no passages yet, so they can only
    match by title). Titles are matched in the search logic itself;
    `AskPassageBuilder` does not change, so Ask, MCP, and embeddings are not
    affected. *(My call.)*
  - Note: note title; snippet from the body.
  - Dictation: app name and time; snippet from the dictated text.
  - Settings: section names ("Editing", "Theme & icons", …) and a small fixed
    list of setting labels ("Text size", "Theme", "Hotkey", …) mapped to a
    section. Matched by prefix of a folded word, not BM25.
- Ranking: `AskRanking.wordScores` (BM25) over the passages that
  `SearchIndexer` already builds (`passages(source)` for every source,
  newest first). Results that belong to the current page come first (Meetings
  page: meetings; Scratchpad: notes; Dictation: dictations; Settings:
  settings), then the rest, each part ordered by score. One result per
  meeting or note (its best passage); dictations are one result per entry.
  No embeddings, no text model: works with no model configured.
  Folding follows `AskText` (Vietnamese diacritics fold the same way Ask
  does).
- Keyboard: ↑ ↓ move, Return opens, Esc clears and closes, clicking outside
  closes. Footer line: "Results from this page come first."
- No results: "No matches" in the panel.
- Opening a result:
  - Meeting: Meetings page, that meeting selected; when the match is a
    transcript line, the transcript tab opens scrolled to that line with the
    line highlighted. Audio does not start playing. Today's
    `pendingMeetingJump` plays audio (right for Ask citations); search needs a
    jump that selects and scrolls only, and a match in the summary, action
    items, or notes opens that tab with no line. *(My call.)*
  - Note: Scratchpad page, that note selected in the list pane, its preview
    shown.
  - Dictation: Dictation page, scrolled to that entry, briefly highlighted
    (`accentSoft`, fades in about 1.5 s).
  - Settings: Settings page, that section selected.

Pure logic (merging scores into one result per item, current-page-first
ordering, the settings label table and prefix match) lives in `VoiceCore`
with tests. The app side only gathers passages and shows results.

## Hide and show the sidebar

- The title bar button and ⌃⌘S toggle it. View menu gains "Hide Sidebar" /
  "Show Sidebar" ⌃⌘S (and "Search" ⌘K). ⌃⌘S works only while the main window
  is key; it is not a global shortcut.
- Hidden: the right panel takes the full width; the title bar leaves room for
  the window buttons at its left end.
- No animation beyond a short ease (0.2 s).
- Remembered across launches (`AppStorage`, not `settings.json`).

## Section lists

**Full-height list pane** (Meetings, Scratchpad): a pane between the sidebar
and the detail, `scaled(250)` wide (capped, see Large text), right `separator` line, background between
`sidebar` and `background` (builder picks a blend or `sidebar` itself). It
holds what the page's left column holds today: folder filter, tag filter, the
page's list search field, sort (Scratchpad), and the list. The detail sits to
its right. The pane is part of the page, not of the window: it does not exist
on other pages.

Meetings' record button moves to the title bar.

Scratchpad (owner chose B):
- Today's card grid becomes the list pane: one row per note (title, edited
  time, first line), same filter, search, and sort as today, same order.
- Selecting a row shows a read-only preview on the right, centered: edited
  time and folder (`footnote`), title (`title2`), tags, and the note body
  rendered as Markdown (`MarkdownDocView`, which the Scratchpad already
  uses). An "Open in window" button (primary) above the body opens that note
  in the floating window (`openNoteInWindow`); double-clicking a row does the
  same.
- Nothing selected: the empty state "Choose a note" with a New note button.
- The preview follows changes saved from the floating window (the notes
  controller already publishes them).
- "Open window ⌃⌥N" moves into the New note menu (Floating scratchpad).
- A later round puts the editor here (owner's option A).

**In-page section list** (Settings, Style): a vertical list `scaled(180)` wide
next to the content, no pane border, inside the centered block (see Centered
content). Group headings in `caption` upper case. Same selection look as the
sidebar.
- Settings: General, Shortcuts, Editing, Theme & icons; then a group "Engine":
  Speech, Models, Agents, Meetings, Storage. Agents stays until Integrations
  takes it. Selection keeps using `model.settingsTab`.
- Style: Personal messages, Work messages, Email, Document, Terminal, Other
  (today's `Style.allCases` and titles). The intro sentence stays above the
  detail. The Style redesign later replaces this list's entries.


## Round pills

One component for views and filters that switch content in place, based on
today's `RoundPills` (moved from `UI/Settings` to `UI/Components`): rounded
track (`hover` fill, `separator` outline), equal-width round pills, the
selected pill filled with `background`, bold text, and a light shadow.
Two sizes: regular (`body`) and small (`footnote`, used in the title bar).
Accessibility: each pill is a button with the selected trait; the track is a
group with a label ("Range", "Meeting view", …).

Replace `PillTabs` and segmented pickers with it in:
- Insights: range (title bar, small).
- Dictation: style filter, new: All, Personal, Work, Email, Document,
  Terminal, Other (short labels; filters `HistoryEntry.style`). Shown above
  the history, left; "Today"-style day headings stay.
- Meetings detail: today's tabs (`MeetingDetailTab`, same order and titles).
- Dictionary: Words, Snippets (today's "Dictionary" label becomes "Words").
- Settings › Theme & icons: already `RoundPills`.

Keep the square segmented control for: Settings › Editing line spacing and
reading width (already decided), Speech tab pickers, the Scratchpad editor's
view mode, and the meeting window. *(Last three: my call, they are tool
controls, not page views.)*

When pills do not fit the width (160%, narrow window) they wrap whole onto a
second row, as `PillTabs` does today (`ViewThatFits` falling back to
`FlowLayout`); equal width applies per row. `PillTabs` is deleted once nothing
uses it.

## Centered content

The gap from the sidebar border (or the list pane border) to the content
equals the gap from the content to the window's right edge.

| Page | Block | Max width |
|---|---|---|
| Upload, Dictionary | column | `store.readingWidth` |
| Dictation, Insights | wide column | `store.readingWidth + scaled(260)` |
| Settings | section list + content | `scaled(180) + 24 + store.readingWidth` |
| Style | section list + content | `scaled(180) + 24 + store.readingWidth + scaled(260)` |
| Meetings detail, Scratchpad preview | column, centered in the space right of the list pane | `store.readingWidth` |
| Integrations, Help | column | `store.readingWidth` |

- Page padding is 32 pt (`spacing[5]`) on all sides; when the panel is
  narrower than the block plus padding, the gaps shrink to the same 24 pt
  (`spacing[4]`) on both sides and the block takes the rest.
- Scroll views span the full panel width (scroll bar at the window edge); only
  the content inside is limited.
- One shared modifier (for example `.bvPageColumn(.reading | .wide | …)`), not
  per-page frames. Builder's call on name and shape.

### Large text and small windows

The fixed columns scale with text size but stop growing at a cap, and the
window's minimum size grows with text size, so content always keeps room:

| Column | Width |
|---|---|
| Sidebar | `min(scaled(200), 260)` |
| List pane | `min(scaled(250), 320)` |
| In-page section list | `min(scaled(180), 230)` |

- Window minimum width: `max(820, sidebar + list pane + 420 + 2 × 24)`,
  computed for the current text size (about 1050 pt at 160%), and never more
  than the screen's visible width. Minimum height stays 560. When text size
  grows past what the current window fits, the window grows to the new
  minimum (kept on screen).
- Content keeps at least 420 pt next to any list. If the screen is too small
  for that, the sidebar hides automatically (and can be shown again).
- *(My call.)*

## Integrations and Help

Plain pages, centered column, vertically placed about a third from the top:
title (`title2`), one sentence (`secondaryText`), and a "Coming soon" chip
(`accentSoft` fill, `footnote`). No title-bar action.

- Integrations: "Calendar, export to Apple Notes and Notion, and the MCP
  server will live here. The MCP server is in Settings › Agents for now."
  "Settings › Agents" is a link that opens that section.
- Help: "Guides for getting started, shortcuts, styles, meetings, and coding
  agents, readable offline."

Search and ⌃⌘S work on both pages.

## Other things that change

- `ContentUnavailableView` on Dictation, Meetings, and Scratchpad uses system
  fonts (open item from the foundation). Replace with a small shared empty
  state built from tokens (icon, `title3`, `secondaryText` line, optional
  button).
- Settings › Shortcuts lists ⌘K "Search everything" and ⌃⌘S "Show or hide
  sidebar" as fixed shortcuts (rows already planned there as "new (shell
  spec)").
- `docs/progress/appearance-log.md` open items "Models controls and Storage
  paths are cut off" are in scope here: the Settings content column must fit
  them at 100% and 160% (wrap labels or stack rows; no horizontal clipping).

## Review focus (inputs no test above pins)

1. 160% text on a 820 × 560 window: title bar (title, search, split button)
   never overlaps; sidebar scrolls; pills wrap.
2. ⌘K while a sheet or the floating scratchpad window is focused: nothing in
   a sheet; the scratchpad window keeps inserting a link.
3. Search with an empty library, with only dictations, and with Vietnamese
   with and without diacritics ("tieng viet" finds "tiếng Việt").
4. Opening a meeting result while that meeting is recording (no transcript
   yet: the meeting is selected, nothing else), and a note's preview while
   that note is being edited in the floating window (preview updates after
   each save).
5. Sidebar hidden, then the window is closed and reopened, then the app
   relaunched: the window buttons never cover the sidebar button.

## Manual checks (owner)

1. Sidebar groups and order match the mockup; Settings and Help at the bottom.
2. Each page's title-bar action works, including menu items.
3. ⌘K search finds a meeting line, a meeting by title, a note, a dictation,
   and "text size".
4. ⌃⌘S and the button hide and show the sidebar; state kept after relaunch.
5. Content centered at 100% and 160%, window narrow and wide.
6. Integrations and Help show Coming soon; the Agents link works.
7. VoiceOver reads sidebar groups, pills, and search results.
8. Scratchpad: select a note, see the preview; Open in window edits it; the
   preview shows the edit after it saves.

## Decided (owner)

- Scope: window frame, section lists, round pills, centered content;
  Integrations and Help as Coming soon (2026-10-18).
- Scratchpad: list pane plus read-only preview, editing stays in the floating
  window; editor in the main window is a later round (2026-10-18).
- Everything listed under "Follow-up specs › App shell", "Section lists",
  "Round pill groups", and "Content is centered" in the foundation spec,
  except where this document marks a later round.

## My calls (owner to check)

- Agents stays in Settings until Integrations is built.
- Fixed columns capped; window minimum grows with text size.
- Search selects and scrolls to a meeting line without playing audio.
- Search matches meeting titles, including unfinished meetings, without
  changing `AskPassageBuilder`.
- "Ask AI about my notes" stays in the New note menu.
- Insights loses its disabled Details tab.
- Dictation's own search field goes; ⌘K search covers dictations and ranks
  them first on that page.
- Style's "Run setup again" waits for the Style spec.
- Sidebar hidden state lives in `AppStorage`.
- Segmented controls kept in Speech, Scratchpad view mode, and the meeting
  window.

## Open questions

None.
