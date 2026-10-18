# Appearance foundation — design

Date: 2026-10-18
Status: draft, round 3 (owner feedback of 2026-10-18 applied), waiting for owner review
Mockup: `docs/design/proposal-appearance.html` (open in a browser; every control is live)
Earlier proposal: `docs/design/proposal-app-redesign.html` (three directions per page and for the menu bar)

## Why this comes first

The owner wants five UI changes: a mixed-layout app shell, a new menu bar
menu, appearance settings (text size, font, themes), a simpler Style page,
and selectable app and menu-bar icons. The owner works 8–12 hours a day and
needs larger, higher-contrast text.

Text size, font, and theme are not one more page. Every other screen is
built on them. If the shell and menu are redesigned first, each screen is
touched twice. This spec builds the foundation: one place that defines
every text size, font, color, space, and corner radius, plus the Settings
page that controls it. The shell, menu, and Style redesigns follow as their
own specs and use only these tokens.

## What the code does today

- 215 `.font(...)` calls in `Sources/BugVoice`. Most use SwiftUI text
  styles: `.caption` 119, `.callout` 27, `.headline` 20, `.title2` 12,
  `.caption2` 8, `.title3` 5, `.body` 3. 19 use `.system(size:)` with a
  fixed number (HUD, Insights stat cards, Markdown headings, heatmap,
  toolbar).
- On macOS, `.caption` is 10 pt. Most secondary text in the app is
  therefore 10 pt, which is too small for the owner.
- macOS has no Dynamic Type. `dynamicTypeSize` does not scale SwiftUI text
  on the Mac, so a text size setting must come from our own scale.
- Colors come from system styles: `.secondary` 157 times, `Color.accentColor`
  21, `.orange` 25, `.red` 7, `.green` 5, `labelColor` 5. No theme layer.
- Surfaces: main window (`MainWindow.swift`), Scratchpad window, meeting
  window, permissions window, HUD (`NSPanel`, `HUDView.swift`), and the
  menu bar (`MenuBarExtra` with `.menuBarExtraStyle(.menu)`, a native menu).
- Two AppKit text editors: `ScratchpadNoteEditor.swift` and
  `MeetingNotesEditor.swift` (`NSTextView`). They set fonts in AppKit, not
  SwiftUI.
- The menu-bar glyph is drawn in code (`BrandImages.menuBar`). The app icon
  is `App/AppIcon.icns`, built from `App/Icon/AppIcon.svg` by
  `Scripts/make-app-icon.sh`. Fifteen logo options with app-icon and
  menu-bar art already exist in `docs/design/logo-options.html`.

## Goals

1. One text size setting that changes every BugVoice window: 90% to 160%
   in 5% steps, default 100%. ⌘+, ⌘−, and ⌘0 work in any BugVoice window.
2. One font setting used for all text, plus a separate code font.
3. Themes for long days: four eye-comfort themes, nine dark, eight light.
   Light, Dark, or Match macOS with a separate light and dark choice.
4. Line spacing and reading width settings.
5. HUD size setting.
6. App icon and menu-bar icon pickers.
7. A Shortcuts tab listing every shortcut, and Right Control as the
   default hold-to-talk key.
8. A rule that keeps it consistent: views use tokens only. A check script
   fails the build when a view sets its own size or color.

## Non-goals

- Layout changes. Pages keep their layout in this project; the shell
  redesign is its own spec. The only visible change at 100% is that
  secondary text grows from 10 pt to 11–12 pt (see Type scale).
- The menu bar menu. It stays a native menu here. A native `NSMenu` always
  uses the system font and colors, so it will follow the tokens only after
  the menu redesign turns it into a popover.
- Style categories and the first-run setup (own spec, see Follow-up specs).
- Per-window or per-page text sizes. One size for everything is the point.

## Settings model (VoiceCore, TDD)

New `AppearanceSettings` in `Sources/VoiceCore/AppearanceSettings.swift`,
stored as `settings.appearance` in `settings.json`. Decoded with the same
`decodeIfPresent ... ?? fallback` pattern as the rest of `Settings`, so an
older file without the key loads the defaults.

```swift
public struct AppearanceSettings: Codable, Equatable, Sendable {
    public var textScale = 100            // percent, clamped to 90...160, step 5
    public var font: AppFont = .system    // .system, .rounded, .serif, .hyperlegible, .monospaced, .custom(name)
    public var codeFont: CodeFont = .sfMono   // .sfMono, .menlo, .custom(name)
    public var lineSpacing: LineSpacing = .normal   // .normal 1.5, .relaxed 1.65, .loose 1.8
    public var readingWidth: ReadingWidth = .medium // .narrow 620, .medium 760, .wide 980 (points, before scale)
    public var mode: AppearanceMode = .dark  // .light, .dark, .system
    public var theme: ThemeID = .bugVoiceDark       // used when mode is .light or .dark
    public var lightTheme: ThemeID = .bugVoiceLight // used when mode is .system and macOS is light
    public var darkTheme: ThemeID = .bugVoiceDark   // used when mode is .system and macOS is dark
    public var hudSize: HUDSize = .medium    // .small 0.85, .medium 1.0, .large 1.3
    public var appIcon: LogoID = .antennaMic
    public var menuBarIcon: LogoID = .antennaMic
}
```

Unknown enum values (a theme removed later, a custom font that is no longer
installed) fall back to the default for that field, not the whole struct.

Tests:
- defaults, round-trip, missing key, unknown theme ID, clamp and step of
  `textScale` (85 → 90, 163 → 160, 102 → 100);
- `resolvedTheme(systemIsDark:)` for all three modes;
- `stepTextScale(by:)` for ⌘+/⌘− (±10, clamped) and `reset` for ⌘0.

## Tokens

### Type scale

Base sizes at 100%. Each view size = base × `textScale / 100`, rounded to
0.5 pt. No view sets a size of its own.

| Token | Base pt | Weight | Use | Replaces |
|---|---|---|---|---|
| `largeTitle` | 28 | semibold | First-run questions | — |
| `title1` | 22 | semibold | Page titles | `.title`, `.system(size: 22)` |
| `title2` | 18 | semibold | Detail and card titles | `.title2`, Markdown H2 |
| `title3` | 15 | semibold | Section headings | `.title3`, `.headline` used as heading |
| `reading` | 15 | regular | Transcripts, notes, dictation text, summaries | `.body` in reading views |
| `body` | 13 | regular | Controls, rows, menus | `.body`, `.callout` |
| `bodyStrong` | 13 | semibold | Row titles, labels | `.headline` used inline |
| `footnote` | 12 | regular | Secondary lines, metadata | `.caption` |
| `caption` | 11 | regular | Group labels, badges | `.caption2`, `.system(size: 9–10)` |
| `stat` | 26 | bold | Insights numbers | `.system(size: 26)` |

The smallest text in the app goes from 9–10 pt to 11 pt at 100%. At the
owner's likely 130%, secondary text is 15.5 pt and reading text 19.5 pt.

### Fonts

| Setting | SwiftUI | AppKit (`NSTextView`) |
|---|---|---|
| System (SF Pro) | `.system(size:weight:design: .default)` | `NSFont.systemFont` |
| SF Rounded | `design: .rounded` | `systemFont` + `.rounded` descriptor |
| New York | `design: .serif` | `systemFont` + `.serif` descriptor |
| Atkinson Hyperlegible Next | `.custom(name, fixedSize:)` | `NSFont(name:size:)` |
| SF Mono everywhere | `design: .monospaced` | `monospacedSystemFont` |
| Any installed font | `.custom(name, fixedSize:)` | `NSFont(name:size:)` |

- Custom fonts use `fixedSize:` because our scale already did the sizing.
- Atkinson Hyperlegible Next was designed for low vision and is free (SIL
  OFL). It would be bundled as a font file in `App/Fonts/`, copied into the
  app by `Scripts/build-app.sh`, and registered at launch with
  `CTFontManagerRegisterFontsForURL`. It is a resource, not a Swift
  package, so the one-dependency rule holds. It still gets a
  `THIRD_PARTY_NOTICES.md` entry. **Gate:** it must cover Vietnamese
  (ă â đ ê ô ơ ư and all five tone marks, stacked forms like ẩ ữ ộ). If a
  glyph is missing, macOS borrows it from another font and the word looks
  patched. Check every glyph in the font file before bundling; drop the
  option if any is missing.
- "Any installed font" opens `NSFontPanel`, keeps the family name only, and
  falls back to System if the font disappears.
- Every font card in Settings shows a Vietnamese sample so the owner sees
  accents before choosing.

### Colors

Each theme is seven colors. Everything else is mixed from them, so adding a
theme means adding seven values.

| Token | Use |
|---|---|
| `background` | Window content |
| `sidebar` | Sidebar and list panes |
| `card` | Panels, cards, popovers |
| `separator` | Lines and control borders |
| `text` | Primary text |
| `secondaryText` | Secondary text, icons |
| `accent` | Selection, primary button, focus ring |
| `hover` (derived) | `card` mixed with `text`, 8% dark / 6% light |
| `accentSoft` (derived) | `background` mixed with `accent`, 24% dark / 14% light: selected rows, chips |
| `onAccent` (derived) | Black or white, whichever contrasts more with `accent` |
| `recording`, `success`, `warning` | Fixed red, green, orange; checked against every background |

Each theme also sets `NSAppearance` (`.aqua` or `.darkAqua`) on every
BugVoice window, so system controls (text fields, pickers, scroll bars,
toggles) match the theme's light or dark mode, and `.tint(accent)` so they
use the theme accent.

### Spacing and shape

- Spacing: 4, 8, 12, 16, 24, 32. Does not scale.
- Corner radius: 6 controls, 10 cards, 14 large cards.
- Control padding and row heights come from text size, so buttons grow with
  text and never clip. Fixed-width columns (sidebar, list pane, label
  column) are multiplied by the scale too.
- At 130% and up, SwiftUI controls use `.controlSize(.large)`.

### Theme catalog

Themes are pure data in VoiceCore (`ThemeCatalog.swift`: ID, name, group,
light or dark, seven hex values), so contrast can be unit-tested. The app
turns hex into `Color` and `NSColor`.

- Eye comfort: High contrast dark, High contrast light, Sepia paper, Warm
  night (amber accent, low blue light for late hours).
- Dark: BugVoice Dark, Catppuccin Mocha, Nord, Tokyo Night, Dracula, One
  Dark, Gruvbox Dark, Everforest Dark, Solarized Dark.
- Light: BugVoice Light, GitHub Light, One Light, Catppuccin Latte, Rosé
  Pine Dawn, Gruvbox Light, Solarized Light, Everforest Light.

The colors are copied from BugMind (`src/themes.ts`), with BugVoice's own
Dark and Light from the first proposal.

Contrast rules, enforced by `ThemeCatalogTests` for every theme:

| Pair | Minimum |
|---|---|
| `text` on `background` and on `card` | 7:1 |
| `secondaryText` on `background` and on `card` | 4.5:1 (7:1 for eye-comfort themes) |
| `accent` on `background` | 3:1 |
| `onAccent` on `accent` | 4.5:1 |

The BugMind values do not all pass. Measured from the mockup values:
One Dark (text 6.6, secondary 3.3 on card), Solarized Dark (text 5.6,
secondary 4.1 on card), Solarized Light (text 5.0, secondary 3.3),
Everforest Light (text 5.2, secondary 3.1, accent 2.7), Rosé Pine Dawn
(text 6.7, secondary 4.0), Catppuccin Latte (secondary 4.4), Gruvbox Light
(secondary 4.3), Everforest Dark (secondary 4.4 on card). These get darker
or lighter text values in BugVoice and keep their names. The mockup shows the original values and a
contrast badge on each tile.

## App structure

### ThemeStore (app target)

`@Observable final class AppearanceStore` owned by `AppModel`. It holds the
resolved `BVTheme` (colors), `BVTypography` (fonts at the current scale),
and layout numbers. It watches:
- `settings.appearance` changes;
- `NSApp.effectiveAppearance` (KVO) for Match macOS.

It is injected into every SwiftUI root with `.environment(store)`: main
window, Scratchpad window, meeting window, permissions window, HUD. Views
read `@Environment(AppearanceStore.self)`.

View helpers, so call sites stay short:

```swift
Text(title).bvFont(.title2)
Text(detail).bvFont(.footnote).foregroundStyle(.bvSecondary)
VStack { … }.bvCard()
```

`.bvSecondary` and the other colors are `ShapeStyle` extensions that read
the store from the environment.

### AppKit pieces

- `ScratchpadNoteEditor` and `MeetingNotesEditor` read font, code font,
  text color, background, insertion point color, and line spacing
  (`NSParagraphStyle.lineHeightMultiple`) from the store and update when
  it changes.
- `HUDController` scales the pill by `hudSize`, independent of
  `textScale`. The pill follows the theme (card background, text color,
  font). Because it floats over other apps, it always has a 1 pt
  `separator` border and a soft shadow, so a light pill stays visible over
  a white page and a dark pill over a dark one. If that is not readable in
  a theme during the manual check, the fallback is BugVoice Light for
  light themes and BugVoice Dark for dark themes.
- Every `NSWindow` gets `appearance` set from the theme mode.

### Keyboard

A View menu in the main menu: Bigger Text (⌘+), Smaller Text (⌘−),
Actual Size (⌘0). Steps of 10%. Works in any BugVoice window with focus.
The Scratchpad editor must not swallow these keys.

### Icons

- **App icon.** Fifteen logos from `docs/design/logo-options.html`.
  `Scripts/make-app-icon.sh` gains a mode that renders each `app<N>` symbol
  to `App/Icons/<id>.png` (1024 px). The chosen PNG is set with
  `NSApp.applicationIconImage` at launch and on change. This changes the
  Dock, app switcher, and window icons while BugVoice runs. Finder and
  Launchpad keep the built-in `AppIcon.icns`; changing those would mean
  writing into the signed app bundle, which breaks the signature and the
  saved macOS permissions.
- **Menu-bar icon.** The same fifteen `menu<N>` glyphs, rendered at build
  time to single-color template PDFs in `App/MenuBarIcons/`, loaded as
  template `NSImage`s so macOS tints them. The permission badge dot from
  `BrandImages.menuBar(badge:)` is drawn on top of whichever glyph is
  chosen. The default stays Antenna Mic, matching today's glyph.
- UI: the same carousel for both (BugMind's `AppIconPicker`): ‹ and ›
  step through the fifteen, with the name and a dot row below. The
  menu-bar glyph is shown on a light and a dark menu bar.

## Settings pages

The Settings list becomes:

- General, Shortcuts, Editing, Theme & icons
- Engine: Speech, Models, Meetings, Storage

Agents moves out of Settings to the new Integrations page (see Follow-up
specs). Every change applies at once and is saved to `settings.json` right
away, including changes made with ⌘+ and ⌘−. No Save button.

**Editing**, top to bottom, as in the mockup:

1. **Preview**: title, reading text in English and Vietnamese, a code line,
   a primary and a secondary button, a toggle, a chip. Updates live.
2. **Text**: Text size slider with A− and A+ buttons and the percentage;
   font cards; code font picker; line spacing (Normal, Relaxed, Loose);
   reading width (Narrow, Medium, Wide).
3. **Reset editing** button.

**Theme & icons**:

1. **Theme**: Light / Dark / Match macOS (round pills). With Match macOS, two pickers for
   the light and dark theme. Theme tiles grouped as Eye comfort, Dark,
   Light, each with a small window preview and its secondary-text contrast
   number.
2. **Recording pill**: Small / Medium / Large (round pills), previewed over a light and a
   dark background.
3. **Icons**: app icon carousel; menu-bar icon carousel of the same kind
   (‹ › to step through, the glyph shown on a light and a dark menu bar,
   name and dots below).
4. **Reset theme and icons** button.

**Shortcuts** lists every shortcut in four groups and lets the owner change
the global ones:

| Group | Shortcut | Default | Changeable | Exists today |
|---|---|---|---|---|
| Dictation | Hold to talk | Right Control | yes (picker) | yes, default Right Option |
| Dictation | Hands-free | double-tap the hotkey | follows the hotkey | yes |
| Dictation | Paste last dictation | ⌃⌥V | yes | yes |
| Dictation | Start or stop a meeting | ⌃⌥M | yes | new |
| Windows | Open BugVoice | ⌃⌥B | yes | yes |
| Windows | Floating scratchpad | ⌃⌥N | yes | yes |
| Windows | Search everything | ⌘K | no | new (shell spec) |
| Windows | Show or hide sidebar | ⌃⌘S | no | new (shell spec) |
| Text size | Bigger, smaller, actual size | ⌘+, ⌘−, ⌘0 | no | new (this spec) |
| Scratchpad | New note, bold/italic/underline/link, copy as Markdown, AI bar | ⌘N, ⌘B/I/U/K, ⌘⇧C, ⌘↩ | no | yes |

A global shortcut that another app already holds shows a warning under its
row. `AppModel.unavailableShortcuts` already records this.

### Hotkey: Right Control as the default (VoiceCore, TDD)

- Add `HotkeyKey.rightControl`. `KeyEventMapper` already defines the
  right-side bit (`rightControl = 0x2000`, key code 62); the new case is
  `Spec(keyCode: 62, downBit: rightControl, ownBits: control | rightControl)`.
- Make it the default for `Settings.hotkey`. A `settings.json` that already
  stores a hotkey keeps it; the owner switches in Settings › Shortcuts.
- The existing chord rule covers ⌃⌥V and similar: the hotkey pressed while
  another modifier is held never starts a recording. Tests: Right Control
  alone starts and stops; left Control never acts as the hotkey; Right
  Control held, then ⌥ and V pressed, does not record; double-tap enters
  hands-free.
- UI copy that says "Right Option" or "Right ⌥" (menu status line, Dictation
  page, HUD hints, Help) reads the hotkey name from settings instead of
  a fixed string.

## Keeping it consistent

`Scripts/check-tokens.sh`, run by `swift test` through a test that shells
out to it (or run before each commit), fails when a file under
`Sources/BugVoice` outside `UI/Theme/`:
- calls `.font(.system(size:` or `.font(.` with a SwiftUI text style
  (`.caption`, `.body`, `.headline`, `.title…`, `.callout`, `.footnote`);
- uses `Color.secondary`, `Color.primary`, `Color.accentColor`,
  `.foregroundStyle(.secondary)` / `.tertiary`, `Color(red:`, `NSColor(`
  with literal values, or hex colors.

Allowed exceptions are listed in the script, one line each with a reason
(for example the HUD background).

## Migration plan (outline; the implementation plan comes next)

1. VoiceCore: `AppearanceSettings`, `ThemeCatalog` with tuned values,
   contrast function and tests.
2. App: `AppearanceStore`, `BVTypography`, `BVTheme`, view helpers,
   injection into all five SwiftUI roots, window `NSAppearance`.
3. Settings › Editing, Settings › Theme & icons, Settings › Shortcuts;
   `HotkeyKey.rightControl` as default.
4. Move views onto tokens, one folder per commit: Settings, Style,
   Dictionary, Insights, Library, Meetings, Upload, Scratchpad, HUD,
   Permissions. Layout stays the same.
5. AppKit editors.
6. View menu and ⌘+/⌘−/⌘0.
7. Icon rendering scripts, app icon and menu-bar icon pickers.
8. `check-tokens.sh` turned on with zero exceptions left except the listed
   ones.
9. Atkinson Hyperlegible Next: glyph check, bundle, notice — or drop.

## Manual checks (to add to the checklist)

1. Text size 160%: every page in the main window, the Scratchpad window,
   the meeting window, and Permissions shows no clipped or overlapping
   text at the default window size.
2. ⌘+ / ⌘− / ⌘0 from each window, including with the Scratchpad editor
   focused.
3. Each font: Vietnamese text in a note and a transcript shows no
   mismatched accent glyphs.
4. Match macOS: switch macOS between light and dark; BugVoice switches
   without a restart.
5. High contrast dark and Sepia paper for one full workday; note any
   element that is still hard to read.
6. App icon change shows in the Dock right away; after relaunch it is
   still the chosen icon. Finder still shows the built-in icon.
7. Menu-bar glyph change, with and without a missing permission (badge).
8. After rebuilding with `Scripts/build-app.sh`, macOS permissions are kept
   (the bundle was not modified at run time).

## Follow-up specs (decisions so far, from the owner and the mockup)

**App shell.** Two panels split by the sidebar border:
- *Left:* the app sidebar, full window height, with the window buttons
  (close, minimize, zoom) at its top, then the brand and the page list.
- *Right:* a title bar of its own, then the page:
  `[sidebar button] Title ……… [search, fixed width, centered] ……… [page action]`.
  When the sidebar is hidden, the window buttons move to the left end of
  this title bar.
- No subtitle under the title.
- Search is about 460 pt wide at 100% (scales with text), centered in the
  right panel, with empty space on both sides. It searches notes, meetings,
  and dictations (`SearchIndexer`), opens with ⌘K, and lists results from
  the current page first.
- The right slot holds the page action, a split button where it has
  variants: Dictation, a status chip "Hold Right Control to speak";
  Meetings, `● Record meeting ▾` (Record meeting, Upload a recording);
  Scratchpad, `+ New note ▾` (Note, Floating scratchpad, Ask AI); Upload,
  Choose files; Style, Run setup again; Dictionary, `+ Add ▾` (Word,
  Snippet); Insights, the range pills; Settings, Integrations, and Help, nothing.
- The sidebar button and ⌃⌘S hide and show the app sidebar.
- Sidebar groups: Capture (Dictation, Insights), Library (Meetings,
  Scratchpad, Upload), Personalize (Style, Dictionary), Connect
  (Integrations). Settings and Help at the bottom.

**Section lists (owner chose option 2, mixed).**
- Meetings and Scratchpad, whose lists grow with the owner's files, get a
  full-height list pane between the sidebar and the content.
- Settings, Style, Integrations, and Help have short fixed lists: a
  vertical list inside the page next to the content, with no pane border.
- Selection in both is a filled `accentSoft` background plus an accent
  border, separate from the keyboard focus ring.

**Round pill groups.** Views and filters that switch the content in place
use one control: a rounded track with equal-width round pills, the
selected pill filled with `background` and bold text. Used for:
- Dictation: All, Coding, Work, Personal, Email, Other.
- Insights: 7 days, 30 days, All time, in the title bar's right slot, at a
  smaller size (footnote text) so the title bar keeps its height.
- Meeting detail: Summary, Transcript, Ask.
- Dictionary: Words, Snippets (horizontal; Dictionary has no section list).
- Style: English examples, Tiếng Việt.
- First-run setup: English examples, Tiếng Việt.
- Settings › Theme & icons: Light, Dark, Match macOS; and the recording
  pill size Small, Medium, Large.
Line spacing and reading width in Settings › Editing keep the square
segmented control for now.

**Content is centered in the right panel.** The gap from the sidebar border
to the content equals the gap from the content to the window's right edge:
- Dictation, Insights, Upload, Dictionary: the content column has a maximum
  width and sits centered.
- Settings, Style, Integrations, Help: the section list and the content
  form one block, centered as a whole, so the gap left of the section list
  equals the gap right of the content. Style's block is wider (cards).
- Meetings and Scratchpad: the list pane stays against the sidebar; the
  detail content is centered in the space to its right.
- When the window is narrower than the maximum width, both gaps shrink to
  the same 24 pt.

**Menu bar.** Option 2 from the first proposal (custom popover: status,
four large buttons, last dictation with Copy and Retry), with Open BugVoice
moved down. Order: status; New note, Record meeting, Upload, Paste last;
last dictation; Library ›, Dictation options ›; Open BugVoice ⌃⌥B,
Settings… ⌘,, Tools ›, Quit ⌘Q. Being a popover, it follows text size,
font, and theme. Cost: keyboard navigation and VoiceOver must be built by
hand.

**Style.** Sections Personal, Work, Email, Coding, Other, and Cleanup
(under "All apps"), shown as a vertical list. Each section: a banner with
the app icons it applies to, three cards with a live example, and a
collapsed "Write your own instructions" box (today's `customRules`).
Examples can be shown in English or Vietnamese. Coding cards: As spoken (no
text model, today's terminal default), Exact, Clean prompt. Other cards:
Formal, Casual, Structured. Cleanup cards: None, Light, Medium, for every
app. A first-run setup asks the same six questions one per screen and can
be run again from Style. Today's Document style (Notion, Obsidian, Pages,
Word) is merged into Other; Structured covers its Markdown lists (owner
confirmed).

The "+" on the banner opens a menu:
- *You dictated here recently*: apps from dictation history that are not
  in a style yet, including the owner's own builds.
- *Choose app…*: today's file picker. It reads the app's bundle ID, which
  every `.app` has (Xcode, Tauri, Electron builds included), and stores it
  in `appOverrides`. This already works.
- *Add website…*: new. Web apps in a browser are matched by address, and
  today only built-in addresses exist. This adds user rules such as
  `localhost:5173` or `myapp.local` next to the built-in `urlRules`.
- Command-line tools run inside a terminal and get the Coding style; no
  rule is needed.

**Integrations** (roadmap item 7, "Calendar + export", plus the MCP server
moved from Settings › Agents). Sections:
- Meetings › Calendar: Apple Calendar through EventKit. Google, Exchange,
  and iCloud accounts already added to macOS work with no sign-in. Fills
  meeting titles and attendees; can suggest recording when an event with a
  video link starts.
- Export › Apple Notes, Notion. Notion needs an integration token and is
  the one export that sends data off the Mac, so it says so.
- Agents › MCP server: the switch, edit and upload permissions, copy-ready
  setup for Claude Code and other clients, recent activity. Agents ›
  Command line: marked Later.
- Models › Local model servers: status of oMLX, MTPLX, Apple Intelligence,
  with a link to Settings › Models.
- Later, not on the roadmap: a bot that joins calls to tell speakers apart.
  People in the call see it join, and teams may object. Listed as Later so
  the idea is kept.

**Help.** A page at the bottom of the sidebar: Getting started, Shortcuts,
Styles, Meetings, Coding agents, Troubleshooting, Privacy. Markdown files
shipped inside the app, so it works offline. Other pages link to it with
"Read the help".

## Decided

- Default text size 100%. The owner changes it while working; every change
  is saved and kept after relaunch.
- The HUD follows the theme (see AppKit pieces).
- Document style merges into Other.
- Hold to talk defaults to Right Control.
- Settings › Appearance is split into Editing and Theme & icons; a new
  Shortcuts tab.
- Section lists: option 2 (mixed). Round equal-width pills for in-page
  views and filters.
- Sidebar runs full height; the title bar belongs to the right panel.

## Open questions

1. Atkinson Hyperlegible Next Vietnamese coverage (gate above).
