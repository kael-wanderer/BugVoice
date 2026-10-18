# Appearance Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One text size, one font, a theme catalog, HUD size, icon pickers, and a Shortcuts tab that every BugVoice window follows, with a check script that keeps views on tokens.

**Architecture:** Settings, themes, the type scale and shortcut letters are pure data in `VoiceCore` (TDD, Foundation only). The app target turns them into an `@Observable AppearanceStore` injected into every SwiftUI root, plus AppKit hooks for the note editors, the HUD and window appearance. Views migrate onto `.bvFont(...)` and theme colors folder by folder; `Scripts/check-tokens.sh` shrinks its pending list until it is empty.

**Tech Stack:** Swift 6 package (tools 6.0, macOS 15 floor), SwiftUI + AppKit, Swift Testing, Carbon hot keys, headless Chrome for icon rendering (build-time script only).

**Spec:** `docs/superpowers/specs/2026-10-18-appearance-foundation-design.md`. Mockup: `docs/design/proposal-appearance.html` (Settings › Editing, Theme & icons, Shortcuts).

## Global Constraints

- Swift package, tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only.
- One external dependency: WhisperKit `exact: "1.1.1"`. Atkinson Hyperlegible Next is a bundled font file, not a package; it needs a `THIRD_PARTY_NOTICES.md` entry.
- TDD for everything in `VoiceCore`: failing test first. `swift test` passes before every commit.
- Work on branch `feat/appearance-foundation`, never on `main`. One commit per task; messages `feat(core): …`, `feat(app): …`, `docs: …`, each ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Tolerant decoding: every new settings struct decodes with `c.value(.key, default: x)`; a missing or unknown value keeps that field's default only.
- Text size: 90...160 percent, step 5, default 100. ⌘+/⌘− step 10. ⌘0 resets to 100. Every change saves to `settings.json` at once.
- View size = base × `textScale / 100`, rounded to 0.5 pt. Spacing (4 8 12 16 24 32) and radius (6 / 10 / 14) do not scale.
- Default hold-to-talk key: Right Control. A stored hotkey is kept.
- Build with `Scripts/build-app.sh` (signs with `Bugler Local Dev`); run with `Scripts/run-dev-app.sh`. Never modify the app bundle at run time.
- UI copy: plain English, no hedging, no emoji.
- Layouts stay as they are. The shell, menu bar, Style, Integrations and Help redesigns are later specs.

## Review Focus

1. **Old `settings.json`** without `appearance` or `shortcuts`, or with a removed theme id / uninstalled custom font — app opens with defaults for those fields only, everything else intact. (Task 2, Task 5 tests.)
2. **Text size at 160%** — no fixed-width column, label column, or HUD clips text; fixed widths go through `store.scaled(_:)`. (Task 6 test on `scaled`, Tasks 10–12 grep step, manual check 1.)
3. **⌘+/⌘−/⌘0 with the Scratchpad editor focused** — the note editor must not swallow them; at 160% ⌘+ stays at 160. (Task 2 test, Task 9 step.)
4. **Two global shortcuts set to the same letter, or a letter another app holds** — the change is refused or the row shows the warning; the old shortcut is not left registered twice. (Task 5 tests.)
5. **Match macOS switched while BugVoice is open** — every open window, the HUD and the AppKit editors recolor without relaunch. (Task 6 KVO step, Task 13/14 observation, manual check 4.)

---

## File map

| File | Responsibility |
|---|---|
| `Sources/VoiceCore/Settings.swift` | `HotkeyKey.rightControl`, defaults, `AppSettings.appearance` / `.shortcuts` decoding |
| `Sources/VoiceCore/KeyEventMapper.swift` | Right Control spec |
| `Sources/VoiceCore/AppearanceSettings.swift` (new) | `AppearanceSettings` and its enums, `ThemeID`, `LogoID` |
| `Sources/VoiceCore/ThemeCatalog.swift` (new) | `RGB`, `Contrast`, `ThemeSpec`, the 21 themes, derived colors, status colors |
| `Sources/VoiceCore/TypeScale.swift` (new) | `TextToken`, `TypeScale`, `LayoutTokens` |
| `Sources/VoiceCore/ShortcutSettings.swift` (new) | Global shortcut letters, key codes, conflict rule |
| `Sources/BugVoiceMac/GlobalShortcuts.swift` | `unregisterAll()` |
| `Sources/BugVoice/UI/Theme/` (new folder) | `AppearanceStore`, `BVTheme`, `BVTypography`, view helpers, `FontRegistry`, `IconImages` |
| `Sources/BugVoice/UI/Settings/EditingSettingsView.swift`, `ThemeSettingsView.swift`, `ShortcutsSettingsView.swift`, `LogoCarousel.swift` (new) | The three new tabs |
| `Scripts/make-logo-assets.sh` (new) | Renders `App/Icons/*.png` and `App/MenuBarIcons/*.png` from `docs/design/logo-options.html` |
| `Scripts/check-tokens.sh` (new) | Token rule check |
| `Tests/VoiceCoreTests/{AppearanceSettings,ThemeCatalog,TypeScale,ShortcutSettings,CheckTokens}Tests.swift` (new) | Tests |

---

### Task 0: Branch

- [ ] **Step 1:** `git switch -c feat/appearance-foundation` from `main` (`720d4e2` or later). `swift test` passes before any change.

---

### Task 1: Right Control as the default hotkey

**Files:**
- Modify: `Sources/VoiceCore/Settings.swift:32,273`, `Sources/VoiceCore/KeyEventMapper.swift:58-71`
- Modify: `Sources/BugVoice/UI/Settings/SettingsComponents.swift:6-20`
- Modify: `Sources/BugVoice/UI/DictationHistoryView.swift:38`, `Sources/BugVoice/UI/Style/StyleExamples.swift:13`, comments in `Sources/BugVoice/MeetingController+Assistant.swift` and `Sources/BugVoice/AppModel.swift:437`
- Test: `Tests/VoiceCoreTests/KeyEventMapperTests.swift`, `Tests/VoiceCoreTests/SettingsTests.swift:14,59`

**Interfaces:**
- Produces: `HotkeyKey.rightControl` (raw value `"rightControl"`); `HotkeyKey.displayName` (app) and new `HotkeyKey.spokenName` (app): `"Right Control"`, `"Right Option"`, `"Right Command"`, `"Fn"`, `"F13"`…; displayName for Right Control is `"Right ⌃"`.

- [ ] **Step 1: Write the failing tests** in `KeyEventMapperTests.swift`, following the existing `rightOption…` tests and the file's `map(...)` helper (add `Code.rightControl = 62`, `Code.leftControl = 59`, `Bits.rightControlDown = control | rightControl`, `Bits.leftControlDown = control` if missing):
  - `rightControlPressAndRelease`: `map(.flagsChanged, Code.rightControl, Bits.rightControlDown, hotkey: .rightControl, at: 2) == .hotkeyDown(2)`; release with `0` → `.hotkeyUp(3)`.
  - `leftControlIsNeverTheRightControlHotkey`: left press → `.otherKeyDown(1)`; left release with `0` → `nil`.
  - `rightControlReleaseWhileLeftControlStillHeldIsHotkeyUp`: mirror the Right Option test.
  - `rightControlThenOptionVIsAChord`: Right Control down, then flagsChanged `Code.leftOption` → `.otherKeyDown`, then keyDown V → `.otherKeyDown` (the chord rule in `HoldGestureDetector` turns that into a cancel; no new detector test needed, the detector is key-agnostic and its double-tap tests already cover hands-free).
  - In `SettingsTests.swift`: line 14 expects `s.hotkey == .rightControl`; line 59 (unknown hotkey) falls back to `.rightControl`; new `storedRightOptionIsKept`: decoding `{"hotkey":"rightOption"}` gives `.rightOption`.
- [ ] **Step 2:** `swift test --filter "KeyEventMapperTests|SettingsTests"` — FAIL (`rightControl` not a member).
- [ ] **Step 3:** Add `case rightControl` to `HotkeyKey` (first in the list); `AppSettings.hotkey = .rightControl`; in `spec(for:)`: `case .rightControl: Spec(keyCode: 62, downBit: rightControl, ownBits: control | rightControl)`.
- [ ] **Step 4:** `swift test` — PASS.
- [ ] **Step 5:** App: add `.rightControl` to `displayName` and add `spokenName`. Replace the fixed "Right Option" copy in `DictationHistoryView.swift:38` and `StyleExamples.swift:13` with `model.settings.hotkey.spokenName` (e.g. `"Hold \(name) to speak"`). Update the two comments to say "the hotkey". `rg -n "Right Option|Right ⌥" Sources` returns only `displayName`/`spokenName` cases.
- [ ] **Step 6:** `swift build` succeeds; commit `feat(core): Right Control is the default hold-to-talk key`.

---

### Task 2: AppearanceSettings

**Files:**
- Create: `Sources/VoiceCore/AppearanceSettings.swift`
- Modify: `Sources/VoiceCore/Settings.swift` (`AppSettings.appearance`, decoding line)
- Test: `Tests/VoiceCoreTests/AppearanceSettingsTests.swift`

**Interfaces:**
- Produces (all `public`, `Codable, Equatable, Sendable`):
  - `struct AppearanceSettings` with the spec's fields and defaults (spec lines 79–93); tolerant `init(from:)`.
  - `enum AppFont { case system, rounded, serif, hyperlegible, monospaced, custom(String) }` — encodes as a single string: `"system"`, `"rounded"`, `"serif"`, `"hyperlegible"`, `"monospaced"`, `"custom:<family>"`. Unknown string → `.system`.
  - `enum CodeFont { case sfMono, menlo, custom(String) }` — strings `"sfMono"`, `"menlo"`, `"custom:<family>"`; unknown → `.sfMono`.
  - `enum LineSpacing: String { normal, relaxed, loose }` with `var multiple: Double` 1.5 / 1.65 / 1.8.
  - `enum ReadingWidth: String { narrow, medium, wide }` with `var points: Double` 620 / 760 / 980.
  - `enum AppearanceMode: String { light, dark, system }`.
  - `enum HUDSize: String { small, medium, large }` with `var factor: Double` 0.85 / 1.0 / 1.3.
  - `enum ThemeID: String, CaseIterable` — cases and raw values: `highContrastDark "hc-dark"`, `highContrastLight "hc-light"`, `sepia "sepia"`, `warmNight "warm-dark"`, `bugVoiceDark "bv-dark"`, `catppuccinMocha "catppuccin-mocha"`, `nord "nord"`, `tokyoNight "tokyo-night"`, `dracula "dracula"`, `oneDark "one-dark"`, `gruvboxDark "gruvbox-dark"`, `everforestDark "everforest"`, `solarizedDark "solarized-dark"`, `bugVoiceLight "bv-light"`, `githubLight "github-light"`, `oneLight "one-light"`, `catppuccinLatte "catppuccin-latte"`, `rosePineDawn "rose-pine-dawn"`, `gruvboxLight "gruvbox-light"`, `solarizedLight "solarized-light"`, `everforestLight "everforest-light"`.
  - `enum LogoID: String, CaseIterable` in this order (index + 1 = symbol number in `logo-options.html`): `waveBug "wave-bug"`, `antennaMic "antenna-mic"`, `caretBubble "caret-bubble"`, `waveB "wave-b"`, `optionWave "option-wave"`, `firefly`, `ladybugLevel "ladybug-level"`, `beeBars "bee-bars"`, `soundRings "sound-rings"`, `hudPill "hud-pill"`, `quoteWave "quote-wave"`, `nonLa "non-la"`, `keycapMic "keycap-mic"`, `codeBug "code-bug"`, `voiceV "voice-v"`; `var displayName` ("Wave Bug" … "Nón Lá" … "Voice V"); `var symbolNumber: Int`.
  - `static let textScaleRange = 90...160`; `static func normalizedScale(_ value: Int) -> Int` (clamp, then nearest multiple of 5).
  - `mutating func stepTextScale(by delta: Int)`; `mutating func resetTextScale()`; `mutating func resetEditing()` (textScale, font, codeFont, lineSpacing, readingWidth); `mutating func resetThemeAndIcons()` (mode, theme, lightTheme, darkTheme, hudSize, appIcon, menuBarIcon).
  - `func resolvedTheme(systemIsDark: Bool) -> ThemeID`.
  - `AppSettings.appearance: AppearanceSettings` (decoded with `c.value(.appearance, default: appearance)`).

- [ ] **Step 1: Write the failing tests** (`AppearanceSettingsTests`):
  - `defaults`: textScale 100, font `.system`, codeFont `.sfMono`, lineSpacing `.normal`, readingWidth `.medium`, mode `.dark`, theme `.bugVoiceDark`, lightTheme `.bugVoiceLight`, darkTheme `.bugVoiceDark`, hudSize `.medium`, both icons `.antennaMic`.
  - `roundTrip`: a value with `font: .custom("Inter")`, `codeFont: .menlo`, mode `.system`, textScale 130 encodes and decodes equal; the JSON contains `"custom:Inter"`.
  - `missingAppearanceKeyLoadsDefaults`: `AppSettings` decoded from `{"hotkey":"rightOption"}` has `appearance == AppearanceSettings()` and hotkey `.rightOption`.
  - `unknownThemeFallsBackPerField`: `{"theme":"neon","darkTheme":"nord","textScale":130}` → theme `.bugVoiceDark`, darkTheme `.nord`, textScale 130.
  - `unknownFontFallsBack`: `{"font":"comic"}` → `.system`.
  - `scaleIsClampedAndStepped`: decoding textScale 85 → 90, 163 → 160, 102 → 100; `normalizedScale(117) == 115`.
  - `stepTextScale`: from 100 by +10 → 110; from 155 by +10 → 160; from 95 by −10 → 90; from 160 by +10 → 160. `resetTextScale()` → 100.
  - `resolvedTheme`: mode `.dark` with theme `.nord` → `.nord` for both `systemIsDark` values; mode `.light` with theme `.sepia` → `.sepia`; mode `.system` → `darkTheme` when `systemIsDark`, else `lightTheme`.
  - `resetEditingKeepsTheme`: after changing textScale and theme, `resetEditing()` restores textScale 100 and keeps theme.
  - `logoOrder`: `LogoID.allCases.count == 15`, `.waveBug.symbolNumber == 1`, `.voiceV.symbolNumber == 15`, `.nonLa.displayName == "Nón Lá"`.
- [ ] **Step 2:** `swift test --filter AppearanceSettingsTests` — FAIL (type missing).
- [ ] **Step 3:** Implement the file and add `appearance` to `AppSettings` and its `init(from:)`.
- [ ] **Step 4:** `swift test` — PASS.
- [ ] **Step 5:** Commit `feat(core): appearance settings with tolerant decoding`.

---

### Task 3: Theme catalog and contrast

**Files:**
- Create: `Sources/VoiceCore/ThemeCatalog.swift`
- Test: `Tests/VoiceCoreTests/ThemeCatalogTests.swift`

**Interfaces:**
- Consumes: `ThemeID` (Task 2).
- Produces:
  - `struct RGB: Equatable, Sendable { r, g, b: Double }` (0...1); `init?(hex: String)` accepting `#rrggbb` and `rrggbb`; `func mixed(with other: RGB, amount: Double) -> RGB` (linear in sRGB, `amount` = share of `other`); `var hex: String`.
  - `enum Contrast { static func luminance(_ c: RGB) -> Double; static func ratio(_ a: RGB, _ b: RGB) -> Double }` (WCAG 2 formula, 0.03928 threshold).
  - `enum ThemeGroup: String, Sendable { comfort, dark, light }`.
  - `struct ThemeColors: Equatable, Sendable { background, sidebar, card, separator, text, secondaryText, accent: RGB }` with derived `func hover(isDark: Bool) -> RGB` (card mixed with text 0.08 dark / 0.06 light), `func accentSoft(isDark: Bool) -> RGB` (background mixed with accent 0.24 / 0.14), `var onAccent: RGB` (black or white, higher ratio vs accent).
  - `struct ThemeSpec: Sendable { id: ThemeID; name: String; group: ThemeGroup; isDark: Bool; colors: ThemeColors }`.
  - `struct StatusColors: Sendable { recording, success, warning: RGB }`; `static let dark` = `#ff6b6b`, `#4cc38a`, `#ffa94d`; `static let light` = `#c62828`, `#1e7a3c`, `#b45309`; `ThemeSpec.status` picks by `isDark`.
  - `enum ThemeCatalog { static let all: [ThemeSpec]; static func spec(_ id: ThemeID) -> ThemeSpec }` — `all` in the order of the table below.

Theme values (background, sidebar, card, separator, text, secondary, accent). These are the tuned values that pass every rule; copy exactly:

| id | name | group | dark | bg | sidebar | card | sep | text | secondary | accent |
|---|---|---|---|---|---|---|---|---|---|---|
| hc-dark | High contrast dark | comfort | yes | #000000 | #0b0b0b | #121212 | #8a8a8a | #ffffff | #d6d6d6 | #6cb6ff |
| hc-light | High contrast light | comfort | no | #ffffff | #f2f2f2 | #ffffff | #5c5c5c | #000000 | #2e2e2e | #0040b0 |
| sepia | Sepia paper | comfort | no | #f3ead8 | #eadfc8 | #f8f1e2 | #cdbb98 | #33281c | #5a4b3a | #8a4b12 |
| warm-dark | Warm night | comfort | yes | #1e1a16 | #18150f | #272219 | #463d31 | #ece1d0 | #bcae98 | #e8a85a |
| bv-dark | BugVoice Dark | dark | yes | #202225 | #1b1d20 | #272a2e | #393d43 | #eeeff1 | #a4aab3 | #88aaff |
| catppuccin-mocha | Catppuccin Mocha | dark | yes | #1e1e2e | #181825 | #262637 | #45475a | #cdd6f4 | #a6adc8 | #cba6f7 |
| nord | Nord | dark | yes | #2e3440 | #292e39 | #3b4252 | #4c566a | #eceff4 | #aeb8c5 | #88c0d0 |
| tokyo-night | Tokyo Night | dark | yes | #1a1b26 | #16161e | #222433 | #3b4261 | #c0caf5 | #9aa5ce | #7aa2f7 |
| dracula | Dracula | dark | yes | #282a36 | #21222c | #343746 | #4d5066 | #f8f8f2 | #a4a6b8 | #bd93f9 |
| one-dark | One Dark | dark | yes | #282c34 | #21252b | #2f343e | #3e4451 | #bdc3cd | #999da5 | #61afef |
| gruvbox-dark | Gruvbox Dark | dark | yes | #282828 | #1d2021 | #32302f | #504945 | #ebdbb2 | #a89984 | #d79921 |
| everforest | Everforest Dark | dark | yes | #2d353b | #272e33 | #343f44 | #4a555b | #dacfb7 | #9faba2 | #a7c080 |
| solarized-dark | Solarized Dark | dark | yes | #002b36 | #00252e | #073642 | #1f4f5a | #b7c0c0 | #8c9b9d | #268bd2 |
| bv-light | BugVoice Light | light | no | #fafbfc | #f0f1f4 | #ffffff | #dce0e7 | #222833 | #646d7b | #315fc8 |
| github-light | GitHub Light | light | no | #ffffff | #f6f8fa | #ffffff | #d1d9e0 | #1f2328 | #59636e | #0969da |
| one-light | One Light | light | no | #fafafa | #f0f0f1 | #ffffff | #d3d3d5 | #383a42 | #696c77 | #4078f2 |
| catppuccin-latte | Catppuccin Latte | light | no | #eff1f5 | #e6e9ef | #f7f8fa | #bcc0cc | #4c4f69 | #6a6d82 | #8839ef |
| rose-pine-dawn | Rosé Pine Dawn | light | no | #faf4ed | #f2e9e1 | #fffaf3 | #dfdad9 | #534e73 | #716d89 | #907aa9 |
| gruvbox-light | Gruvbox Light | light | no | #fbf1c7 | #f2e5bc | #fdf6d8 | #d5c4a1 | #3c3836 | #776b60 | #b57614 |
| solarized-light | Solarized Light | light | no | #fdf6e3 | #eee8d5 | #fffbf0 | #d8d0b6 | #46575c | #667373 | #268bd2 |
| everforest-light | Everforest Light | light | no | #fdf6e3 | #f4f0d9 | #fffbef | #e0dcc7 | #4a555b | #687467 | #859701 |

- [ ] **Step 1: Write the failing tests** (`ThemeCatalogTests`):
  - `hexParses`: `RGB(hex: "#202225")` has r ≈ 32/255; `RGB(hex: "zz")` is nil; `RGB(hex: "88aaff")?.hex == "#88aaff"`.
  - `blackOnWhiteIs21`: `Contrast.ratio(.white, .black)` ≈ 21 (±0.01).
  - `catalogShape`: 21 themes; groups comfort 4, dark 9, light 8; ids unique; every `ThemeID.allCases` has exactly one spec; `isDark` matches the table.
  - `textContrast` (parameterized over `ThemeCatalog.all`): text on background and on card ≥ 7.
  - `secondaryContrast`: secondaryText on background and card ≥ 4.5, ≥ 7 for `.comfort`.
  - `accentContrast`: accent on background ≥ 3.
  - `onAccentContrast`: onAccent on accent ≥ 4.5.
  - `statusContrast`: each status color ≥ 3 on background and on card of every theme with the same `isDark`.
  - `onAccentPicksBlackForLightAccent`: `bv-dark` onAccent is black; `bv-light` onAccent is white.
- [ ] **Step 2:** `swift test --filter ThemeCatalogTests` — FAIL.
- [ ] **Step 3:** Implement `ThemeCatalog.swift` with the table above.
- [ ] **Step 4:** `swift test` — PASS (if a contrast test fails, the value was mistyped; recheck against the table, do not loosen the rule).
- [ ] **Step 5:** Commit `feat(core): theme catalog with contrast rules`.

---

### Task 4: Type scale and layout tokens

**Files:**
- Create: `Sources/VoiceCore/TypeScale.swift`
- Test: `Tests/VoiceCoreTests/TypeScaleTests.swift`

**Interfaces:**
- Produces:
  - `enum TextToken: String, CaseIterable, Sendable { largeTitle, title1, title2, title3, reading, body, bodyStrong, footnote, caption, stat }`, `var baseSize: Double` (28, 22, 18, 15, 15, 13, 13, 12, 11, 26), `var weight: TokenWeight`.
  - `enum TokenWeight: Sendable { regular, semibold, bold }` — semibold for largeTitle, title1–3, bodyStrong; bold for stat; regular otherwise.
  - `enum TypeScale { static func size(_ token: TextToken, scale: Int) -> Double; static func scaled(_ points: Double, scale: Int) -> Double }` — `(points × scale / 100 × 2).rounded() / 2`.
  - `enum LayoutTokens { static let spacing: [Double] = [4, 8, 12, 16, 24, 32]; static let controlRadius = 6.0, cardRadius = 10.0, largeCardRadius = 14.0; static func usesLargeControls(scale: Int) -> Bool }` (true at ≥ 130).

- [ ] **Step 1: Write the failing tests**: at 100 every token equals its base; at 130 body 17, footnote 15.5, reading 19.5; at 115 title2 20.5; at 160 largeTitle 45; `scaled(240, scale: 130) == 312`; `usesLargeControls(scale: 125) == false`, `(130) == true`; weights as listed.
- [ ] **Step 2:** `swift test --filter TypeScaleTests` — FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test` — PASS.
- [ ] **Step 5:** Commit `feat(core): type scale and layout tokens`.

---

### Task 5: Changeable global shortcuts

The Shortcuts tab lets the owner change the four ⌃⌥ shortcuts. Modifiers stay ⌃⌥; the owner picks the letter.

**Files:**
- Create: `Sources/VoiceCore/ShortcutSettings.swift`; modify `Sources/VoiceCore/Settings.swift` (`AppSettings.shortcuts`)
- Modify: `Sources/BugVoiceMac/GlobalShortcuts.swift`, `Sources/BugVoice/AppModel.swift:213-218,462-471`, `Sources/BugVoice/DictationController.swift:46-51`
- Test: `Tests/VoiceCoreTests/ShortcutSettingsTests.swift`, `Tests/BugVoiceMacTests/GlobalShortcutsTests.swift`

**Interfaces:**
- Produces:
  - `enum ShortcutAction: String, CaseIterable, Codable, Sendable { pasteLast, toggleMeeting, openApp, newNote }` with `var title` ("Paste last dictation", "Start or stop a meeting", "Open BugVoice", "Floating scratchpad").
  - `struct ShortcutSettings: Codable, Equatable, Sendable` storing one uppercase letter per action; defaults V, M, B, N; `func letter(for: ShortcutAction) -> String`; `mutating func setLetter(_ letter: String, for: ShortcutAction) -> Bool` (false and no change when not A–Z or already used by another action); tolerant decoding: an invalid letter or a duplicate falls back to that action's default.
  - `enum ShortcutKeys { static func keyCode(forLetter: String) -> Int? }` — ANSI codes A0 B11 C8 D2 E14 F3 G5 H4 I34 J38 K40 L37 M46 N45 O31 P35 Q12 R15 S1 T17 U32 V9 W13 X7 Y16 Z6.
  - `AppSettings.shortcuts: ShortcutSettings`.
  - `GlobalShortcuts.unregisterAll()` — unregisters every ref and clears actions; the test init gains an `unregisterHotKey` closure (production: `UnregisterEventHotKey`).
  - `AppModel.registerGlobalShortcuts()` — calls `unregisterAll()`, clears `unavailableShortcuts`, registers the four actions from `settings.shortcuts`; `unavailableShortcuts` entries become `"⌃⌥\(letter) \(action.title)"`. Called once at launch (replacing the scattered `registerShortcut` calls, which `DictationController.start()` no longer makes) and from `settingsDidChange` when `shortcuts` changed. `AppModel.unavailableShortcutActions: Set<ShortcutAction>` for the Shortcuts tab warning.

- [ ] **Step 1: Write the failing tests**:
  - `ShortcutSettingsTests`: defaults V/M/B/N; `setLetter("K", for: .pasteLast)` true; `setLetter("B", for: .pasteLast)` false and pasteLast stays V; `setLetter("7", …)` false; lowercase `"k"` is stored as `"K"`; decoding `{"pasteLast":"B"}` (duplicate of openApp) keeps V; decoding missing key gives defaults; `keyCode(forLetter: "V") == 9`, `"N" == 45`, `"é" == nil`.
  - `GlobalShortcutsTests`: with injected closures, register two shortcuts then `unregisterAll()` → the unregister closure was called twice; registering again after `unregisterAll()` succeeds and fires the new action only.
- [ ] **Step 2:** `swift test --filter "ShortcutSettingsTests|GlobalShortcutsTests"` — FAIL.
- [ ] **Step 3:** Implement VoiceCore and `GlobalShortcuts` changes.
- [ ] **Step 4:** `swift test` — PASS.
- [ ] **Step 5:** Wire `registerGlobalShortcuts()` into `AppModel` and remove the registrations from `DictationController.start()`. `swift build` succeeds; `Scripts/build-app.sh && Scripts/run-dev-app.sh`, then ⌃⌥B opens the main window.
- [ ] **Step 6:** Commit `feat(core): changeable global shortcut letters`.

---

### Task 6: AppearanceStore, theme helpers, injection

**Files:**
- Create: `Sources/BugVoice/UI/Theme/AppearanceStore.swift`, `BVTheme.swift`, `BVTypography.swift`, `ThemeModifiers.swift`
- Modify: `Sources/BugVoice/AppModel.swift` (owns `let appearance: AppearanceStore`; `settingsDidChange` calls `appearance.apply(settings.appearance)`)
- Modify the five roots: `UI/MainWindow.swift:99`, `UI/PermissionsView.swift:128`, `UI/Scratchpad/ScratchpadWindowController.swift:77`, `MeetingWindowController.swift:132`, `HUD/HUDController.swift:39`; also `MeetingDetectionController.swift:155` (popup)

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces:
  - `@MainActor @Observable final class AppearanceStore` with `private(set) var settings: AppearanceSettings`, `theme: BVTheme`, `type: BVTypography`, `systemIsDark: Bool`; `func apply(_ settings: AppearanceSettings)`; `func scaled(_ points: CGFloat) -> CGFloat` (via `TypeScale.scaled`); `var readingWidth: CGFloat`; `var lineSpacingMultiple: CGFloat`; `var nsAppearance: NSAppearance` (`.aqua` / `.darkAqua` from the resolved theme's `isDark`); `func attach(_ window: NSWindow)` (sets `appearance` now and on every change; keeps a weak list); observes `NSApp.effectiveAppearance` by KVO to update `systemIsDark`.
  - `struct BVTheme` — `Color` and `NSColor` for background, sidebar, card, separator, text, secondaryText, accent, hover, accentSoft, onAccent, recording, success, warning; `init(_ spec: ThemeSpec)`; `var isDark: Bool`.
  - `struct BVTypography` — `func font(_ token: TextToken) -> Font` and `func nsFont(_ token: TextToken) -> NSFont`; `func codeFont(_ token: TextToken) -> Font` / `nsCodeFont`. Font mapping per spec table (lines 130–137): `.custom(name, fixedSize:)` for hyperlegible/custom, falling back to system when `NSFont(name:size:)` is nil.
  - View helpers in `ThemeModifiers.swift`: `func bvFont(_ token: TextToken) -> some View`; `func bvCode(_ token: TextToken) -> some View`; `func bvCard(radius: CGFloat = LayoutTokens.cardRadius) -> some View` (card fill, 1 pt separator border); `func bvTheme(_ store: AppearanceStore) -> some View` (injects `.environment(store)`, `.tint(accent)`, `.preferredColorScheme`, `.controlSize(.large)` at ≥ 130%, background). Colors via `ShapeStyle` statics resolved from the environment: `.bvText`, `.bvSecondary`, `.bvAccent`, `.bvBackground`, `.bvSidebar`, `.bvCard`, `.bvSeparator`, `.bvHover`, `.bvAccentSoft`, `.bvOnAccent`, `.bvRecording`, `.bvSuccess`, `.bvWarning` — implement as a `ShapeStyle` struct whose `resolve(in:)` reads an `EnvironmentValues.bvTheme` entry set by `bvTheme(_:)`.

- [ ] **Step 1:** Implement the four files. No VoiceCore change, so no new unit test here; the logic under test (scale, contrast, resolve) lives in Tasks 2–4.
- [ ] **Step 2:** Every root view gets `.bvTheme(model.appearance)`; every window controller calls `model.appearance.attach(window)` after creating its window (including the HUD panel and the meeting popup panel).
- [ ] **Step 3:** `swift build` succeeds; `swift test` passes.
- [ ] **Step 4:** Build and run. Temporarily set `"appearance":{"mode":"light","theme":"sepia"}` in `settings.json`, relaunch: window chrome and system controls turn light and the accent is brown. Restore the file.
- [ ] **Step 5:** Commit `feat(app): appearance store and theme helpers in every window`.

---

### Task 7: Icon assets and the app / menu-bar icon

**Files:**
- Create: `Scripts/make-logo-assets.sh`, `App/Icons/<logo-id>.png` (15, 1024 px), `App/MenuBarIcons/<logo-id>.png` + `<logo-id>@2x.png` (15 × 2, 18 / 36 px)
- Create: `Sources/BugVoice/UI/Theme/IconImages.swift`
- Modify: `Scripts/build-app.sh` (copy `App/Icons`, `App/MenuBarIcons`, `App/Fonts` when present into `Contents/Resources/`), `Sources/BugVoice/BrandImages.swift` (`menuBar(badge:)` takes a `LogoID`), `Sources/BugVoice/BugVoiceApp.swift` (menu bar label uses the chosen glyph), `AppModel.settingsDidChange` (apply icon on change)

**Interfaces:**
- Consumes: `LogoID` (Task 2).
- Produces: `enum IconImages { static func appIcon(_ id: LogoID) -> NSImage?; static func menuGlyph(_ id: LogoID) -> NSImage? }` (template image; loads from `Bundle.main.resourceURL/Icons` and `/MenuBarIcons`; nil outside a built app). `BrandImages.menuBar(logo: LogoID, badge: Bool) -> NSImage` draws the glyph then today's badge dot; falls back to today's drawn Antenna Mic when the PNG is missing (so `swift run` still shows an icon). App icon: `NSApp.applicationIconImage = IconImages.appIcon(id)` at launch and when `appIcon` changes.

Deviation from the spec: menu glyphs are template PNGs (1x and 2x), not PDFs. Headless Chrome renders PNG directly, and `NSImage` with both reps and `isTemplate = true` tints the same way.

- [ ] **Step 1:** Write `Scripts/make-logo-assets.sh`: a Python block (run with `python3 -I`) reads the sprite in `docs/design/logo-options.html`, writes one standalone SVG per `app<N>` / `menu<N>` symbol to a temp dir (menu SVGs with `color: black`, transparent background), then renders each with the same headless Chrome call `Scripts/make-app-icon.sh` uses: app at 1024 × 1024, menu at 18 and 36. Output names come from `LogoID` raw values in order (symbol N → N-th id).
- [ ] **Step 2:** Run it; `ls App/Icons | wc -l` is 15, `ls App/MenuBarIcons | wc -l` is 30. Open three PNGs with the Read tool to confirm they are not blank.
- [ ] **Step 3:** Implement `IconImages`, `BrandImages.menuBar(logo:badge:)`, launch and change hooks, and the `build-app.sh` copies.
- [ ] **Step 4:** `Scripts/build-app.sh && Scripts/run-dev-app.sh`. Set `"appIcon":"non-la","menuBarIcon":"firefly"` in `settings.json`, relaunch: Dock shows Nón Lá, menu bar shows Firefly. `codesign --verify --deep build/BugVoice.app` succeeds. Restore.
- [ ] **Step 5:** Commit `feat(app): app and menu-bar icon assets`.

---

### Task 8: Settings tabs — Shortcuts, Editing, Theme & icons

**Files:**
- Create: `Sources/BugVoice/UI/Settings/ShortcutsSettingsView.swift`, `EditingSettingsView.swift`, `ThemeSettingsView.swift`, `LogoCarousel.swift`, `RoundPills.swift`
- Create: `Sources/BugVoice/UI/Theme/FontRegistry.swift` (lists installed families via `NSFontManager.shared.availableFontFamilies`; custom font picker)
- Modify: `Sources/BugVoice/UI/Settings/SettingsView.swift:3-30`

**Interfaces:**
- Consumes: Tasks 1, 2, 3, 5, 6, 7.
- Produces: `enum SettingsTab { general, shortcuts, editing, theme, speech, models, agents, meetings, storage }` in that order (Agents stays until the Integrations spec). Titles: "General", "Shortcuts", "Editing", "Theme & icons", "Speech", "Models", "Agents", "Meetings", "Storage". `RoundPills<Value: Hashable>(items: [(Value, String)], selection: Binding<Value>, small: Bool = false)` — equal-width round pills in a rounded track, selected pill filled `.bvBackground` with bodyStrong text (the follow-up specs reuse it). `LogoCarousel(selection: Binding<LogoID>, kind: .app | .menuBar)` — ‹ › buttons, wraps at both ends, name below, 15-dot row; `.menuBar` shows the glyph on a light and a dark strip.

Content, top to bottom, as in the mockup and spec lines 298–337:

- **Shortcuts:** four groups (Dictation, Windows, Text size, Scratchpad). Hold to talk: picker over `HotkeyKey.allCases` showing `displayName`. Hands-free: text "Double-tap \(hotkey.spokenName)". The four ⌃⌥ rows: a letter picker A–Z; a refused change (`setLetter` false) leaves the picker on the old letter and shows "Already used by \(other.title)." under the row; a row in `unavailableShortcutActions` shows "Another app uses this shortcut." Fixed rows (⌘K, ⌃⌘S, ⌘+ ⌘− ⌘0, Scratchpad keys) show their keys with no control; ⌘K and ⌃⌘S rows say "Coming with the new window layout."
- **Editing:** live preview card (title2 title, reading text in English and "Tiếng Việt có dấu: ẩ ữ ộ đ ơ ư", a code line, primary and secondary button, a toggle, a chip); Text size slider 90…160 step 5 with A− / A+ buttons (±10) and "\(n)%"; font cards (System, SF Rounded, New York, Atkinson Hyperlegible Next only if `FontRegistry.hyperlegibleAvailable`, SF Mono, Other font… which opens a family picker) each showing "Chữ Việt rõ ràng"; code font picker (SF Mono, Menlo, Other…); Line spacing pills Normal / Relaxed / Loose; Reading width pills Narrow / Medium / Wide; "Reset editing" button calling `resetEditing()`.
- **Theme & icons:** mode pills Light / Dark / Match macOS; with Match macOS two pickers "Light theme" / "Dark theme"; tiles grouped Eye comfort, Dark, Light (small window preview in the theme's colors, name, secondary contrast as "\(ratio, 1 decimal):1"); Recording pill pills Small / Medium / Large with previews on a light and a dark strip; app icon carousel; menu-bar icon carousel; "Reset theme and icons" calling `resetThemeAndIcons()`. Picking a tile sets `theme` in Light/Dark mode, or `lightTheme`/`darkTheme` (by the tile's `isDark`) in Match macOS.

Every control writes `model.settings.appearance` / `model.settings.shortcuts` / `model.settings.hotkey` directly; `settingsDidChange` saves.

- [ ] **Step 1:** Implement the five views and `FontRegistry`; wire the tabs. Use tokens only (`bvFont`, `.bv…` colors) — these files are not on the check-tokens pending list.
- [ ] **Step 2:** `swift build`, `swift test` pass.
- [ ] **Step 3:** Build and run. Compare each tab with the mockup (`docs/design/proposal-appearance.html` › Settings): change text size to 130%, theme to Nord, HUD to Large, app icon to Bee Bars, Paste last to K; quit and relaunch: all five kept. Try setting Paste last to B: refused with the message. Reset both groups.
- [ ] **Step 4:** Commit `feat(app): Shortcuts, Editing, and Theme & icons settings`.

---

### Task 9: View menu and text size keys

**Files:**
- Modify: `Sources/BugVoice/BugVoiceApp.swift` (next to `installEditMenu()`, line 69)
- Modify: the Scratchpad and meeting notes `NSTextView` subclasses only if Step 3 shows they swallow the keys

**Interfaces:**
- Consumes: `AppearanceSettings.stepTextScale(by:)`, `resetTextScale()`.
- Produces: `installViewMenu()` adding a "View" menu after Edit with "Bigger Text" (`+`, ⌘; also accepts ⌘= via a hidden alternate item), "Smaller Text" (`-`, ⌘), "Actual Size" (`0`, ⌘). Actions call `model.settings.appearance.stepTextScale(by: ±10)` / `resetTextScale()`.

- [ ] **Step 1:** Implement, guarding against a duplicate menu like `installEditMenu` does.
- [ ] **Step 2:** `swift build` succeeds.
- [ ] **Step 3:** Run; press ⌘+ twice from the main window (120%), ⌘− from the meeting window, ⌘0 from the Scratchpad window with the editor focused (100%). Each step shows in Settings › Editing and survives relaunch. At 160%, ⌘+ stays 160%.
- [ ] **Step 4:** Commit `feat(app): View menu with bigger, smaller, and actual size`.

---

### Task 10: check-tokens script

**Files:**
- Create: `Scripts/check-tokens.sh`, `Tests/VoiceCoreTests/CheckTokensTests.swift`

**Interfaces:**
- Produces: `Scripts/check-tokens.sh` — exits 1 and prints `path:line: rule` for each hit under `Sources/BugVoice`, excluding `Sources/BugVoice/UI/Theme/`, the `ALLOW` list, and the `PENDING` list. Rules (`rg -n` patterns): `\.font\(\.system\(size:`; `\.font\(\.(caption2?|body|headline|subheadline|title[23]?|largeTitle|callout|footnote)\b`; `Color\.(secondary|primary|accentColor)`; `\.foregroundStyle\(\.(secondary|tertiary|primary)\)`; `Color\(red:`; `NSColor\(( *)(red|white|calibratedRed|srgbRed)`; `#[0-9a-fA-F]{6}\b` inside string literals. `ALLOW` lines are `path  # reason`. `PENDING` starts as every folder or file under `Sources/BugVoice` that has a hit today; Tasks 11–13 delete lines from it.
- `CheckTokensTests.checkTokensPasses`: runs `/bin/bash Scripts/check-tokens.sh` from the package root (found from `#filePath`) with `Process`, expects exit status 0.

- [ ] **Step 1:** Write the test; run `swift test --filter CheckTokensTests` — FAIL (script missing).
- [ ] **Step 2:** Write the script with an empty `PENDING`; run it to list today's hits; fill `PENDING` with the files that have them (expect the Settings, Style, Dictionary, Insights, Library, Meetings, Upload, Scratchpad, MeetingWindow, HUD, Permissions, Menu files). The Task 8 files must not appear.
- [ ] **Step 3:** `swift test` — PASS.
- [ ] **Step 4:** Commit `feat(app): token check script`.

---

### Tasks 11–13: Move views onto tokens

Same procedure for each group; layout stays the same. Replacement table (spec Type scale):

| Today | Token |
|---|---|
| `.largeTitle`, `.title`, `.system(size: 22)` | `.bvFont(.title1)` |
| `.title2`, `.system(size: 17–18)` | `.bvFont(.title2)` |
| `.title3`, `.headline` as heading | `.bvFont(.title3)` |
| `.body` in transcripts, notes, dictation text, summaries | `.bvFont(.reading)` |
| `.body`, `.callout`, `.subheadline` elsewhere | `.bvFont(.body)` |
| `.headline` inline, `.body.weight(.semibold)` | `.bvFont(.bodyStrong)` |
| `.caption`, `.footnote` | `.bvFont(.footnote)` |
| `.caption2`, `.system(size: 9–10)` | `.bvFont(.caption)` |
| `.system(size: 26)` numbers | `.bvFont(.stat)` |
| `.monospaced` text | `.bvCode(<token>)` |
| `.secondary` / `.tertiary` | `.bvSecondary` |
| `.primary` | `.bvText` |
| `Color.accentColor` | `.bvAccent` |
| `Color(red:…)` card / row fills | `.bvCard`, `.bvHover`, `.bvAccentSoft` |
| fixed `.frame(width: N)` holding text | `.frame(width: store.scaled(N))` |
| `.padding(22)` and other padding | nearest of 4 8 12 16 24 32 |
| reading views (note editor, transcript, dictation text, summary) | content capped at `.frame(maxWidth: store.readingWidth)` (scaled `ReadingWidth.points`), centered |

Each task: (1) remove its lines from `PENDING`; (2) `Scripts/check-tokens.sh` lists the hits; (3) replace per table until it passes; (4) `rg -n "frame\(width: [0-9]" <folders>` and route every width that holds text through `scaled`; (5) `swift build`, `swift test`; (6) run the app at 100% and 160% and look at every page in the group — no clipped or overlapping text, and at 100% the layout matches before except secondary text is larger; (7) commit.

### Task 11: Settings, Style, Dictionary
- Files: `Sources/BugVoice/UI/Settings/`, `UI/Style/`, `UI/Dictionary/`, `UI/Components/`.
- Commit `feat(app): settings, style, and dictionary use tokens`.

### Task 12: Main window pages
- Files: `UI/MainWindow.swift`, `UI/DictationHistoryView.swift`, `UI/Insights/`, `UI/Library/`, `UI/MeetingsPage.swift`, `UI/MeetingPlayer.swift`, `UI/MeetingSpeakersRow.swift`, `UI/NotesPage.swift`, `UI/UploadPage.swift`.
- Commit `feat(app): main window pages use tokens`.

### Task 13: Scratchpad, meeting window, permissions, popups, AppKit editors
- Files: `UI/Scratchpad/`, `UI/MeetingWindow/`, `UI/PermissionsView.swift`, `UI/MenuContent.swift`, `MeetingDetectionController.swift` popup view, `UI/Scratchpad/MarkdownTextStyler.swift`, `ScratchpadNoteEditor.swift:455`, `MeetingNotesEditor.swift:22`.
- AppKit editors: `MarkdownTextStyler` drops the fixed `bodySize = 14` / `codeSize = 13` and takes a `MarkdownTextStyle` value (`bodyFont: NSFont` = `type.nsFont(.reading)`, `codeFont: NSFont` = `type.nsCodeFont(.body)`, heading fonts from `title2`/`title3`, `textColor`, `secondaryColor`, `lineHeightMultiple`). Both editors build it from `model.appearance`, set `backgroundColor`, `insertionPointColor`, `textColor`, `typingAttributes`, and restyle the whole storage when the store changes (observe with `withObservationTracking`, re-arming after each change). `MenuContent` is a native menu and keeps system fonts; it goes on the `ALLOW` list with reason "native NSMenu, redesign spec".
- Extra check: Vietnamese note at 130% in Atkinson (if bundled) and New York shows no mixed accent glyphs; Match macOS flip recolors an open note without relaunch.
- Commit `feat(app): scratchpad, meeting window, and editors use tokens`.

---

### Task 14: HUD follows the theme

**Files:**
- Modify: `Sources/BugVoice/HUD/HUDView.swift`, `Sources/BugVoice/HUD/HUDController.swift`; remove the HUD from `PENDING`

**Interfaces:**
- Consumes: `AppearanceStore`, `HUDSize.factor`.
- Produces: HUD text uses `type.font(.body)` scaled by `hudSize.factor` **instead of** `textScale` (HUD size is its own setting): size = `TypeScale.size(.body, scale: 100) × factor`, rounded to 0.5. Pill fill `.bvCard`, text `.bvText`, recording dot `.bvRecording`, 1 pt `.bvSeparator` border, shadow radius 8 / y 2 / black 25%. Paddings and the waveform multiplied by `factor`. `HUDController` resizes the panel when `hudSize` or theme changes.

- [ ] **Step 1:** Implement; `Scripts/check-tokens.sh` passes with the HUD removed from `PENDING`.
- [ ] **Step 2:** `swift build`, `swift test` pass.
- [ ] **Step 3:** Run; dictate over a white web page and a dark terminal with BugVoice Light, Sepia, BugVoice Dark and High contrast dark at Small and Large. If a theme's pill is hard to see, log it in `docs/progress/appearance-log.md` for the owner's manual check (the spec's fallback is decided there, not here).
- [ ] **Step 4:** Commit `feat(app): HUD follows the theme and HUD size`.

---

### Task 15: Atkinson Hyperlegible Next — gate, then bundle or drop

**Files:**
- Create (if the gate passes): `App/Fonts/AtkinsonHyperlegibleNext-*.otf` (Regular, SemiBold, Bold, and matching italics if shipped), `App/Fonts/OFL.txt`; modify `THIRD_PARTY_NOTICES.md`, `Sources/BugVoice/UI/Theme/FontRegistry.swift`
- Create: `Scripts/check-font-glyphs.py`

**Interfaces:**
- Produces: `FontRegistry.registerBundledFonts()` (called at launch; `CTFontManagerRegisterFontsForURL(url, .process, nil)` for each file in `Resources/Fonts`); `FontRegistry.hyperlegibleAvailable: Bool`; family name `"Atkinson Hyperlegible Next"`.

- [ ] **Step 1:** Download the font from its official source (Braille Institute / Google Fonts, SIL OFL 1.1) into its own new empty directory under the scratchpad. Record the URL and version.
- [ ] **Step 2:** `Scripts/check-font-glyphs.py <font>` (run with `python3 -I`; reads the `cmap` table with the standard library or `fontTools` if installed) checks every code point in: `ăâđêôơư ĂÂĐÊÔƠƯ`, all five tones on `a ă â e ê i o ô ơ u ư y` in both cases (precomposed U+1EA0–U+1EF9 and U+00C0–U+01B0 Vietnamese set), and the combining marks U+0300 U+0301 U+0303 U+0309 U+0323. Prints missing code points; exit 1 if any.
- [ ] **Step 3a (gate passes):** copy the font files and `OFL.txt` into `App/Fonts/`; add a `THIRD_PARTY_NOTICES.md` entry (name, version, URL, SIL OFL 1.1, bundled as a font resource); implement registration. Build and run: the Atkinson card appears in Settings › Editing and its sample shows "Chữ Việt rõ ràng" in one font.
- [ ] **Step 3b (gate fails):** do not bundle; set `hyperlegibleAvailable = false` permanently, remove `.hyperlegible` from the font cards (keep the enum case so a saved value still decodes, falling back to `.system` in `BVTypography`), record the missing code points in `docs/progress/appearance-log.md`.
- [ ] **Step 4:** `swift test` passes; commit `feat(app): bundle Atkinson Hyperlegible Next` or `docs: Atkinson Hyperlegible Next lacks Vietnamese glyphs`.

---

### Task 16: Finish — tokens check empty, docs

**Files:**
- Modify: `Scripts/check-tokens.sh` (`PENDING` empty), `AGENTS.md` (Key documents: plan and log), `docs/progress/HANDOFF.md`
- Create: `docs/progress/appearance-log.md`

- [ ] **Step 1:** `PENDING` is empty; `Scripts/check-tokens.sh` exits 0 and `ALLOW` holds only lines with reasons.
- [ ] **Step 2:** `docs/progress/appearance-log.md`: one line per task with its commit hash, the deviations (menu glyphs as PNG; ⌃⌥ letters only; Agents tab kept until Integrations; Atkinson outcome), and a manual checks table numbered 1–10 (own numbering, like `ask-log.md`): 1–8 copied from the spec's Manual checks section (lines 387–404), 9 Shortcuts tab — change Paste last to K, ⌃⌥K pastes, ⌃⌥V does nothing; 10 Right Control is the default on a fresh `settings.json`, a stored Right Option is kept. Result column `Pending`.
- [ ] **Step 3:** `AGENTS.md` Key documents gain "Appearance foundation plan: `docs/superpowers/plans/2026-10-18-appearance-foundation.md`" and "Appearance execution log and manual checks: `docs/progress/appearance-log.md`"; `HANDOFF.md` notes the branch and the pending manual checks.
- [ ] **Step 4:** `swift test` passes; `Scripts/build-app.sh` succeeds; commit `docs: appearance foundation log and handoff`.
