# Onboarding and built-in model execution log

Spec: `docs/superpowers/specs/2026-11-06-onboarding-and-built-in-model-design.md`
Plan: `docs/superpowers/plans/2026-11-06-onboarding-and-built-in-model.md`
Mockup: `docs/design/proposal-onboarding.html`

Phase 1 (onboarding, tour, DMG layout) is built on `feat/onboarding`. Build,
`swift test` and `Scripts/build-app.sh` pass. The device checks below were not
run; the owner is at the keyboard and they are open. Phase 2 (bench gate) and
Phase 3 (built-in model) follow.

## Task 1 — Fresh-install settings and onboardingDone (2026-11-06)

- Added `AppSettings.onboardingDone` (default true; decoder default true),
  `AppSettings.freshInstall()` (onboarding not done, no connections, dictation
  and meetings engine `.none`, notes unset), and `SettingsStore.load()`, which
  returns the fresh-install value only when `settings.json` does not exist.
  A corrupt or unreadable file still loads as an existing install.
- Test-first evidence: `swift test --filter SettingsTests` failed to compile
  with "no member 'onboardingDone'" before the change. Focused green: 67 tests
  in SettingsTests. Full `swift test`: 1388 tests passed.
- Round trip covered by `onboardingDoneRoundTrips`.
- Commit: ce00436 `feat(core): fresh-install settings and onboardingDone`.

## Task 2 — Onboarding steps and cleanup choice (2026-11-06)

- Added `Sources/VoiceCore/Onboarding.swift` (`OnboardingStep`, `CleanupChoice`,
  `CleanupChoiceKind`, `OnboardingSetup`) and `OnboardingTests` (7 tests).
- Cloud cleanup keeps thinking enabled (`disableThinking` false).
- `CleanupChoice.builtIn` is declared, but applying it is a no-op until Task 10
  adds `ModelEngine.builtIn`. The choice is not offered while the built-in
  model is disabled, so the path is unreachable for now.
- No RED output was captured: the implementation was written before the first
  test run. Focused green: 7 tests. Full `swift test`: 114 tests passed.
- Commit: 419965f `feat(core): onboarding steps and cleanup choice`.

## Task 3 — Hotkey probe (2026-11-06)

- Added `AppModel.hotkeyProbe`. While it is set, `DictationController.receive(_:)`
  passes only `.hotkeyDown` to the probe. Every other input returns early, so
  the detector is not fed and no dictation starts.
- Review found that a probe set mid-hold could orphan a running recording and
  let a late hold tick start a dictation. Fix: the probe cancels a running
  recording, always resets the detector, and the hold tick checks for the probe.
- Verification: `swift build` ok; full `swift test` passed. The app target has no
  unit tests, so TDD does not apply here.
- Commits: fc32b71 `feat(app): hotkey probe for onboarding`;
  61c94e5 `fix(app): hotkey probe cancels a running hold`.

## Task 4 — Onboarding window and settings entry (2026-11-06)

- Added `OnboardingWindowController` (620 x 460; permission status polled once
  a second while open; closing the window counts as Skip), `OnboardingView`
  (footer with "Step N of 7", dots, Back, Skip, primary button), and
  `OnboardingSteps`: Welcome, Hotkey (probe, "Key seen. It works." for 2 s,
  Input Monitoring note), Permissions (reuses `PermissionsView`), Speech (from
  `speechState`, with Retry).
- Skip on steps 2, 3, 5 and 6 skips that step. Skip setup on Welcome ends
  setup. Matches the mockup.
- `AppWindow.onboarding` added. `AppModel` gained `presentOnboarding`,
  `openOnboarding(at:)`, `finishOnboarding()` and launch wiring.
- General tab "Run setup again" card, and a "Run setup again" entry in global
  settings search (keywords: onboarding, get started). Search count test went
  from 45 to 46.
- Verification: `swift test` passed (VoiceCore 1395, other suites pass);
  `Scripts/build-app.sh` ok; `check-tokens` ok.
- Commit: d0a6805 `feat(app): onboarding window`.

## Task 5 — Cleanup and Try-it steps (2026-11-06)

- Step 5 (`OnboardingCleanupStep.swift`): radio list from
  `OnboardingSetup.choices`. Local form for LM Studio, Ollama, oMLX or Other,
  with an optional key, model field and picker, and Test. Cloud form for OpenAI,
  Anthropic or OpenRouter, with the key saved to `CredentialStore`, model, Test,
  and the line "Your dictated text is sent..." Nothing is preselected. Continue
  with no choice leaves settings unchanged. Test lists models, then runs one
  cleanup on a sample.
- Step 6 (`OnboardingTryItStep.swift`): a text box that takes the talk key,
  with an "It works" row showing times and model, problem text, a speech-download
  note, and Try again.
- VoiceCore `TryItResult` maps dictation outcomes to plain-English problems
  (4 tests).
- Try-it dictation is decided once at key-down: only when the onboarding window
  is key and the Try-it text view is first responder. Such results skip history,
  insights, correction learning and the Fix last paste record. Dictation into
  other apps is unchanged while step 6 is open.
- Review found that Try-it capture was keyed on a flag rather than the target.
  Fix round 1 made it stricter as above.
- Verification: `TryItResultTests` 4 passed; full `swift test` passed
  (VoiceCore 1399, MCPKit 30, app 114); `Scripts/build-app.sh` ok.
- Commits: 53a8099 `feat(app): onboarding cleanup and try-it steps`;
  353ac8d `fix(app): try-it capture only for the onboarding text box`.

## Task 5b — Main-window tour (2026-11-06)

- VoiceCore `Tour` (`TourStop`, `TourCard`, `Tour.cards`, `Tour.visibleStops`),
  3 tests. RED: `swift test --filter TourTests` failed with "cannot find 'Tour'
  in scope". Green: 3 tests.
- App: tour overlay with anchors on the main window, `AppModel.startTour`,
  `endTour`, `tourNext`, `tourBack`. Entry points: finish of onboarding,
  Settings > General, and the menu popover Tools > "Take the tour".
- On-screen stops follow the sidebar state and meeting recording state. Esc
  ends the tour; arrows move it. The tour ends if the page changes outside it.
- This replaces the Task 4 no-op `startTour`.
- Verification: full `swift test` passed; `swift build` and
  `Scripts/build-app.sh` ok.
- Commit: a0ba11e `feat(app): main-window tour`.

## Task 6 — DMG layout and install help (2026-11-06)

- `App/DMG/background.svg` with rendered `background.png` (660 x 420) and
  `background@2x.png` (1320 x 840). `Scripts/make-dmg-background.sh` renders them.
- `Scripts/make-dmg-readme.sh` builds "Read Me First" (Markdown and PDF) with
  python3 stdlib and headless Chrome. Screenshot slots are omitted until
  captured. `App/DMG/screenshots/` holds a `.gitkeep`.
- `Scripts/build-dmg.sh` rewritten: writable image with headroom, Finder layout
  through AppleScript, convert to UDZO, verify. The two PNGs are combined into
  `.background/background.tiff` so Retina uses the 2x image.
- Review found that a same-name mounted volume could make Finder target the wrong
  disk. Fix round 1: the script requires the mount point to be
  `/Volumes/<name>` and otherwise exits with an error. It also surfaces
  `tiffutil`, `hdiutil` and `osascript` failures, and checks render outputs are
  non-empty.
- GeneralTab update note: way A text, then way B with a Copy button for clearing
  the download quarantine.
- Verification: `bash -n` on all three scripts; background and PDF rendered and
  viewed; a scratch image was created, converted and verified. `swift test` passed
  (114). `Scripts/build-dmg.sh` was not run: it drives Finder and may raise an
  Automation prompt on the owner's screen.
- Commits: 1196e30 `build: DMG layout with install help`;
  b3e86d5 `fix(build): DMG script guards volume name and shows errors`.

## Owner checks (open)

Not run by the implementer. Record results here at hand-over.

Device checks, Phase 1:

- [ ] Fresh install path: with no `settings.json`, onboarding opens at step 1;
      Back, Skip and Skip setup behave as the mockup shows.
- [ ] Hotkey probe: step 2 shows "Key seen. It works." when the talk key is
      held, and the press does not dictate.
- [ ] Tour, all three entry points: from onboarding finish, Settings > General,
      and the menu popover Tools > "Take the tour". Esc ends it, arrows move it,
      narrow or hidden sidebar skips hidden stops, and it matches the mockup.
- [ ] Existing install path: an install with a `settings.json` never shows
      onboarding automatically and keeps its settings.
- [ ] Run setup again: Settings > General reopens onboarding at step 1.
- [ ] Try it: hold the talk key; text lands only in the box; the "It works" row
      shows times and model; Try again clears; long dictation wraps and scrolls.
- [ ] Try it isolation: with step 6 open, dictate into another app; it reaches
      History and Fix last paste, and the Try-it row does not change.
- [ ] Step 5: oMLX with a key, Test passes, Continue; a cloud key is saved and
      the privacy line shows.
- [ ] Close and relaunch after closing onboarding does not reopen it.
- [ ] DMG window: run `Scripts/build-dmg.sh` (allow Automation if asked); compare
      with mockup Part 1 (window bounds, icon positions, text not overlapped,
      Retina sharpness, hidden `.background`).
- [ ] Screenshots: capture `App/DMG/screenshots/not-opened.png` and
      `open-anyway.png`, rerun `Scripts/make-dmg-readme.sh`, commit.
- [ ] Update note: Settings > General shows the way A and way B text correctly.

Deferred minors (from the task reviews; fix in the final wave):

- [ ] Try-it text view lacks min/max size and horizontal resize settings, so long
      text may not wrap.
- [ ] Closing the main window mid-tour leaves the tour index set; it reappears on
      reopen.
- [ ] Speech step lacks the download size (spec: name, size, progress).
- [ ] Duplicated cleanup-test block between `OnboardingCleanupStep` and
      `UseForCard.runTest`.
- [ ] Re-running onboarding adds a second local connection.
- [ ] Cloud Continue is allowed with an empty key.
- [ ] `make-dmg-background.sh` runs `sips` before its `-s` check, so the friendly
      Chrome message never prints.
