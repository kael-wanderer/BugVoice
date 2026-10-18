# Appearance foundation — execution log

Branch: `feat/appearance-foundation`. Owner manual checks remain pending.

## Atkinson gate (Task 15)

Downloaded into the new empty directory `/tmp/bugvoice-atkinson-eb1_3g8t` from the
[official Google Fonts source](https://github.com/googlefonts/atkinson-hyperlegible-next/tree/7925f50f649b3813257faf2f4c0b381011f434f1/fonts/otf),
commit `7925f50f649b3813257faf2f4c0b381011f434f1`, version **2.001**, SIL OFL 1.1.
Regular, SemiBold, Bold, Italic, SemiBoldItalic and BoldItalic were checked with
`python3 -I Scripts/check-font-glyphs.py <six OTF files>`.

Result: **FAIL, 98 of 151 required code points missing in every face**:
`U+0128–U+0129`, `U+0168–U+0169`, `U+01A0–U+01A1`, `U+01AF–U+01B0`,
`U+0309`, `U+0323`, `U+1EA0–U+1EF1`, `U+1EF4–U+1EF9`.
An independent CoreText glyph lookup on Regular confirmed the same 151 required /
98 missing result.

No font or license resource was copied into the app; no third-party dependency
was added. `hyperlegibleAvailable` is permanently false; the font card is hidden;
a stored `.hyperlegible` still decodes and renders as System.

## Tasks and commits

| Task | Commit | Work |
|---|---|---|
| 0 | — | Branch setup, no commit specified; already complete when this run started. |
| 1 | `bd1a6f2` | Right Control default. |
| 2 | `edfd919` | Appearance settings and tolerant decoding. |
| 3 | `e59fb4b` | Theme catalog and contrast. |
| 4 | `bedafee` | Type scale and layout tokens. |
| 5 | `e9360be` | Changeable global shortcut letters. Follow-up reviewed fix: `0ada954`. |
| 6 | `ffaf023` | Appearance store, helpers, root/window injection. |
| 7 | `12b0442` | App and menu-bar PNG assets. |
| 8 | `13d7439` | Shortcuts, Editing, Theme & icons. |
| 9 | `e0fecf0` | View menu and text size commands. |
| 10 | `9d7bb78` | Token check script. |
| 11 | `b91836a` | Settings, Style, Dictionary, shared components. |
| 12 | `8e05275` | Main window pages and Library. |
| 13 | `c02d8f9` | Scratchpad, meeting window, permissions, popups, AppKit editors. |
| 14 | `32319d4` | Themed HUD with independent size. |
| 15 | `29e0ac9` | Atkinson gate failed; no font bundled. |
| 16 | This docs commit | Final audit, log and handoff; its hash is in the delivery report. A commit cannot contain its own hash. |

## Automated and device evidence

- `swift test` passed before each implementation commit: **892 VoiceCore tests / 98 suites,
  30 MCPKit tests / 2 suites, 94 BugVoiceMac tests / 16 suites** (1,016 tests total).
- `Scripts/check-tokens.sh` exits 0. `PENDING` is empty. The only `ALLOW` entry is
  `Sources/BugVoice/UI/MenuContent.swift  # native NSMenu, redesign spec`.
- App packages were built with `Scripts/build-app.sh`, signed with **Bugler Local Dev**,
  and launched with `Scripts/run-dev-app.sh`. Iteration builds used `CONFIGURATION=debug`;
  the final build uses the script's default release configuration.
- Final release deep/strict signature verification passed. Original `settings.json` bytes
  and the saved Scratchpad window frame were restored after stopping BugVoice.
  The final sidebar fill was inspected at 100%; a further 160% capture returned
  no accessibility window, so the preceding complete 100%/160% capture pass is the evidence
  for that scale. Local QA notes and short meeting records remain in app data.
- Task 6: temporary light/Sepia settings produced light window chrome and system controls
  with a brown accent. ⌃⌥B opened the main window on the secondary screen. ⌃⌥V was pressed
  in a non-secure Dictionary text field, but no last result was available after relaunch,
  so end-to-end paste was not proved.
- Task 7: 15 app images (1024 px), 30 template menu images (18/36 px). Nón Lá, Bee Bars,
  Firefly PNGs inspected; a signed launch with Nón Lá / Firefly succeeded. Deep signature
  verification passed. Dock/menu-bar rendering was not verified by the UI provider.
- Task 8: 130%, Nord, Large HUD, Bee Bars and Paste last K were changed through the UI,
  saved, and observed after relaunch. Paste last B was refused with the conflict message;
  the picker kept K. Both reset buttons worked. The Atkinson card is absent after the failed gate. The three new pages were inspected at
  100% and 160%, including in the main window's 1000 × 680 default size.
- Task 9: main-window keyboard checks saved 120% after two Bigger Text actions, 110%
  after Smaller Text, 160% after repeated Bigger Text, and 100% after Actual Size.
  Later Scratchpad editor-focused ⌘0 saved 100%; a meeting-window Smaller Text action
  saved 90% from 100%. The final ⌘= fix was verified in the main window and focused Scratchpad editor.
  Two main-window ⌘= presses saved 120%, shown in Editing after relaunch; the meeting
  window ⌘− saved 110%, also shown after relaunch. Scratchpad ⌘0 saved 100%, six ⌘= presses
  reached 160%, and ⌘+ stayed at 160%. Exhaustive all-keys-in-all-windows coverage remains pending.
- Tasks 11–12: window captures inspected at 100% and 160% for all eight main pages,
  all nine Settings tabs, all six Style tabs, and the empty Snippets subtab.
  The final signed release pass repeated all 24 captures at both scales. Dictionary was checked; final captures also cover the Snippets subtab.
  All modal/player/detail states were not comprehensively checked.
- Task 13: floating Scratchpad and meeting windows captured at 100% and 160% at their
  current saved sizes. New York at 130% rendered the Vietnamese sample consistently.
  An open AppKit note recolored when macOS changed light/dark, without relaunch.
  That check exposed stale root theme values: the root helper now reads the observable
  store inside its modifier body; repeat light/dark captures passed.
- Window positions were read before capture. Captures target BugVoice windows/panels,
  never desktop screen regions. HUD captures use the discovered panel's window ID.
- Temporary `settings.json` edits were restored byte-for-byte from the original backup;
  macOS dark mode was restored to its original value. Test Chrome and Terminal windows
  used for HUD checks were closed. Scratchpad frame defaults were backed up for restoration. The UI checks created temporary Untitled notes and
  short meetings in the local library; these were not broadly deleted because existing
  Untitled notes were already present.

## HUD readability

Actual panel captures at Small and Large were inspected for BugVoice Light, Sepia,
BugVoice Dark and High contrast dark. Light themes have dark readable text; dark themes
have readable light text. The High contrast dark edge is the clearest. Standard dark's
border is subtler against a dark background; the light pill's border is subtle on white.
No fallback was added; the owner's background/workday check decides whether one is needed.

The matrix attempted a Right Option hold with a white Chrome page and a dark Terminal
at each size/theme. Several first holds showed **Model loading / downloading 100%**,
and several rapid follow-up attempts had no visible HUD. Confirmed listening captures:
BugVoice Light Small, Sepia Small/Large, BugVoice Dark Large, High contrast dark Small/Large.
Loading-message captures also verified theme and size for the remaining combinations.
Window-only captures retain transparent surrounding pixels, so they do not prove the
entire pill/background relationship. A full successful spoken-dictation matrix over both
backgrounds, Small BugVoice Dark listening, and live HUD resize/theme switching remain
owner checks. No claim of a complete spoken-dictation matrix is made.

## 160% fit observations — layouts preserved

- **Fixed after review (rechecked at 100% and 160% in 1000 × 680):**
  - Settings and Style tabs: labels never break; when the row does not fit, whole pills
    move to a second row (`PillTabs` falls back to `FlowLayout`). Settings shows all nine
    tabs at both sizes; at 100% Storage sits on the second row.
  - Dictation: the four stat tiles form an adaptive grid (two per row at 160%); nothing
    runs past the window edge.
  - Sidebar: icons no longer overlap titles (fixed-width scaled icon column instead of
    `Label`); no clipped labels on Dictation, Insights, Meetings, Settings, Style.
  - Insights: stat cards wrap in an adaptive grid; the period pills and Local move under
    the Usage / Details pills when they do not fit.
  - Note editors: reading-width centering is recalculated when the editor resizes.
- **Handled in app-shell source; visual recheck pending:** Models controls now stack
  in the centered Settings column; Storage paths use middle truncation, full-path help
  and Reveal (Task 7). Token EmptyState replaced ContentUnavailableView in Phase A.
  See `docs/progress/app-shell-log.md`. The app-shell UI access denial prevented
  100%/160% screenshots, so the earlier clipping observations are not yet visually closed.
- **Dictionary:** the add-field placeholder truncates at both sizes. Its existing responsive
  rule hides the illustration at narrow widths. Snippet text deliberately uses one-line
  truncation; the empty Snippets subtab was also captured in the final pass.
- **Scratchpad main page:** card previews use existing ellipses, titles wrap, toolbar search
  is tight. Upload's visible content fits. Meetings list/empty detail has no observed overlap.
- **Floating windows:** no clipping observed in the captured saved-size Scratchpad and
  meeting windows; a further 720 × 560 Scratchpad check found a truncated “More professional”
  action and follow-up placeholder at 160%, while Vietnamese body text wrapped.
  Permissions was also captured: it fits at 160%, while its Input Monitoring
  description truncates at 100%. The detection popup still needs checks. Collapsed meeting state and all secondary/editor/dialog states remain pending.

No layout redesign was made to address these observations.

## Deviations and reasons

1. Menu glyphs are template PNGs at 1x/2x, as the plan permits, because headless Chrome
   renders PNG directly. App icons still change at runtime; Finder keeps the bundled icon.
2. ⌃⌥ shortcuts change letters A–Z only, per the plan; Agents stays until Integrations.
3. The required Superpowers execution/subagent skills were not installed. Work was executed
   sequentially with a file-backed task log; no subagents were used.
4. SwiftUI repeatedly replaced the manually installed AppKit View menu. `installViewMenu()`
   therefore returns SwiftUI `Commands`, inserted into the existing native View menu.
   SwiftUI owns its lifetime and prevents duplicate groups. The actions/signatures used
   by settings remain unchanged.
5. Other font uses an installed-family sheet, following the plan's family-picker interface;
   the spec's NSFontPanel presentation was not used.
6. Iterative signed packages used the build script's debug configuration to reduce build
   time; the final package uses release. An intermediate debug rebuild was started with
   a dev process open. The process was stopped and subsequent final packaging performed
   with the app stopped; no resources were injected into a running signed bundle.
7. Task 13 also corrected Task 6's root theme observation after the live flip exposed stale
   colors. Without that fix, the AppKit editor updated but surrounding text could keep its
   old color.
8. Atkinson was dropped under the plan's step 3b because the actual files failed the glyph
   gate. No THIRD_PARTY_NOTICES entry was added because no font was bundled.
9. The final key check reproduced a non-firing hidden ⌘= alternate (⌘+ and ⌘0 worked).
   Task 16 adds an app-local ⌘= handler calling the same Bigger Text setting action;
   SwiftUI retains the visible View menu and hidden alternate item.
10. Task 16 includes final token cleanup missed by the script's narrow literal patterns:
   conditional padding, layout spacing defaults, text minimum/maximum widths, the suggestion
   border, conditional status/shadow colors, and an explicit themed sidebar fill in place
   of the native vibrancy background. These finish the requested migration;
   no view hierarchy was redesigned.
11. Task 0 has no planned commit; Task 16 identifies itself in the table because storing its
    own final hash is impossible. The delivery report supplies Task 16's hash.

## Run checks still not verified

- Dock icon and menu-bar glyph/badge appearance, including a missing-permission badge.
- ⌃⌥V actually pasting a known last dictation; K pastes while V does nothing after remapping.
- Complete ⌘+ / ⌘− / ⌘0 and persistence checks from every window/editor. Main commands and
  Scratchpad editor reset, Bigger Text and clamp have evidence after the ⌘= fix;
  all remaining key/window combinations still need owner coverage.
- Meeting-detection popups at 100%/160%; no external meeting was generated just to trigger
  those states. Permissions was opened through native accessibility and inspected at both scales;
  Microphone, Accessibility and Input Monitoring remained granted.
- Every modal, detail, player, citation, AI-answer and collapsed meeting state at both sizes;
  Vietnamese in every font and a populated transcript. Atkinson visual checks are inapplicable.
- Full spoken HUD matrix, live HUD setting changes, and one full workday in Sepia / High contrast dark.
- A fresh-settings device launch proving Right Control; unit tests cover the default and
  preservation of stored Right Option, and the existing Right Option was used during this run.

## Owner manual checks

These are intentionally **Pending** even where the smoke checks above cover part of a row.

| # | Check | Result |
|---|---|---|
| 1 | Text size 160%: every page in the main window, the Scratchpad window, the meeting window, and Permissions shows no clipped or overlapping text at the default window size. | Pending |
| 2 | ⌘+ / ⌘− / ⌘0 from each window, including with the Scratchpad editor focused. | Pending |
| 3 | Each font: Vietnamese text in a note and a transcript shows no mismatched accent glyphs. | Pending |
| 4 | Match macOS: switch macOS between light and dark; BugVoice switches without a restart. | Pending |
| 5 | High contrast dark and Sepia paper for one full workday; note any element that is still hard to read. | Pending |
| 6 | App icon change shows in the Dock right away; after relaunch it is still the chosen icon. Finder still shows the built-in icon. | Pending |
| 7 | Menu-bar glyph change, with and without a missing permission (badge). | Pending |
| 8 | After rebuilding with Scripts/build-app.sh, macOS permissions are kept (the bundle was not modified at run time). | Pending |
| 9 | Shortcuts tab: change Paste last to K; ⌃⌥K pastes and ⌃⌥V does nothing. | Pending |
| 10 | Right Control is the default on a fresh settings.json; a stored Right Option is kept. | Pending |
