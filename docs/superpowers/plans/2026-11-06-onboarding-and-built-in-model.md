# Onboarding and Built-in Cleanup Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A non-technical user installs BugVoice from the DMG, gets past Gatekeeper, finishes a 7-step setup, and gets cleaned text from a model BugVoice downloads and runs itself.

**Architecture:** Three phases. Phase 1 (Tasks 1–7) ships the DMG help and the onboarding window, with the Built-in choice hidden. Phase 2 (Task 8) benches candidate GGUF models through a pinned `llama-server` and is a gate. Phase 3 (Tasks 9–15) adds the built-in engine: catalog and settings in VoiceCore, a bundled `llama-server` child process on `127.0.0.1`, downloads with SHA-256 checks, and the UI. Cleanup through the built-in engine reuses `OpenAICompatibleModel` (`.local` flavor).

**Tech Stack:** Swift 6 package (tools 6.0), SwiftUI/AppKit, Swift Testing, llama.cpp `llama-server` (MIT, bundled binary), Finder AppleScript for the DMG layout.

**Spec:** `docs/superpowers/specs/2026-11-06-onboarding-and-built-in-model-design.md` · Mockup: `docs/design/proposal-onboarding.html`

## Global Constraints

- Swift package, tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only (no CryptoKit there).
- No new Swift package dependency. WhisperKit stays the only one, pinned `exact: "1.1.1"`.
- llama.cpp is a bundled binary: pinned release tag + SHA-256, verified at build time, signed with `Bugler Local Dev`, listed in `THIRD_PARTY_NOTICES.md`. The app never downloads an executable.
- Model files: HTTPS only, pinned Hugging Face revision + SHA-256; a file that fails the hash is deleted.
- `llama-server` binds `127.0.0.1` only, with a random per-launch API key.
- TDD for VoiceCore; `swift test` passes before every commit. Commit after each task: `feat(core): …`, `feat(app): …`, `build: …`, `docs: …`.
- UI copy: plain English, no hedging words, no emoji (mockup emoji become SF Symbols).
- Fresh install = no `settings.json`. Existing installs never see onboarding automatically and keep their settings.
- Run the app with `Scripts/run-dev-app.sh` (non-primary display). Synthetic hotkey input that ends in a paste runs only while the owner is away.

## Review Focus

1. **Upgrade of an existing install** (owner's `settings.json` with oMLX): no onboarding, connections and engines unchanged. Test in Task 1.
2. **Corrupt `settings.json`**: treated as an existing user (`onboardingDone == true`), not a fresh install. Test in Task 1.
3. **Talk key pressed during the Hotkey step, or the window closed on that step**: no dictation starts, and the probe is cleared when the step or window goes away so later presses dictate normally. Covered by `OnboardingFlow` tests (Task 2) and the probe wiring check (Task 4).
4. **Interrupted, truncated or tampered model download**: resume from the partial file; a hash mismatch deletes the file and reports it; an over-long partial restarts. Tests in Task 11.
5. **`llama-server` dies, its port is taken, or first load outlasts the dictation timeout**: the next cleanup restarts it; a slow load gives the normal raw-text fallback with a reason, never a hang. Tests in Task 13 (`BuiltInTextModel` with a fake server).

---

## Phase 1 — Install help and onboarding

### Task 1: Fresh-install settings and `onboardingDone`

**Files:**
- Modify: `Sources/VoiceCore/Settings.swift` (`AppSettings` and its decoder at `extension AppSettings`, ~line 449)
- Modify: `Sources/VoiceCore/SettingsStore.swift`
- Test: `Tests/VoiceCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces: `AppSettings.onboardingDone: Bool` (default `true` in `init()` and when the key is missing); `static func AppSettings.freshInstall() -> AppSettings`; `SettingsStore.load()` returns `freshInstall()` only when the file does not exist.

- [ ] **Step 1: Write failing tests** in `SettingsTests.swift`:

```swift
@Test func freshInstallHasNoServerAndNoCleanup() {
    let s = AppSettings.freshInstall()
    #expect(s.onboardingDone == false)
    #expect(s.models.connections.isEmpty)
    #expect(s.models.dictation.engine == .none)
    #expect(s.models.notes == nil)
    #expect(s.models.meetings.engine == .none)
}
@Test func decodedFileWithoutKeyCountsAsOnboarded() throws {
    let data = #"{"hotkey":"rightControl","models":{"connections":[{"id":"omlx","kind":"openAICompatible","baseURL":"http://localhost:8000","model":"Q"}],"dictation":{"engine":{"connection":"omlx"}}}}"#.data(using: .utf8)!
    let s = try JSONDecoder().decode(AppSettings.self, from: data)
    #expect(s.onboardingDone == true)
    #expect(s.models.connections.map(\.id) == ["omlx"])
    #expect(s.models.dictation.engine == .connection("omlx"))
}
@Test func onboardingDoneRoundTrips() throws {
    var s = AppSettings.freshInstall(); s.onboardingDone = true
    let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
    #expect(back.onboardingDone == true)
}
@Test func storeGivesFreshInstallOnlyWhenFileMissing() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = SettingsStore(url: dir.appendingPathComponent("settings.json"))
    #expect(store.load().onboardingDone == false)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: store.url)
    #expect(store.load().onboardingDone == true)   // corrupt file = existing user
}
```

- [ ] **Step 2:** `swift test --filter SettingsTests` → FAIL (`onboardingDone` / `freshInstall` not defined).
- [ ] **Step 3:** Add the property, `CodingKeys` entry, decoder line `onboardingDone = c.value(.onboardingDone, default: true)`, `freshInstall()`, and the missing-file branch in `SettingsStore.load()`. Fix any existing store test that expected `AppSettings()` for a missing file.
- [ ] **Step 4:** `swift test` → all PASS.
- [ ] **Step 5:** Commit `feat(core): fresh-install settings and onboardingDone`.

### Task 2: Onboarding flow and cleanup choice (pure)

**Files:**
- Create: `Sources/VoiceCore/Onboarding.swift`
- Test: `Tests/VoiceCoreTests/OnboardingTests.swift`

**Interfaces:**
- Produces:
  - `enum OnboardingStep: Int, CaseIterable, Sendable { case welcome, hotkey, permissions, speech, cleanup, tryIt, finish }` with `var number: Int` (1-based), `var next: OnboardingStep?`, `var previous: OnboardingStep?`, `var showsSkip: Bool` (false for `.welcome`, `.speech`, `.finish`), `var probesHotkey: Bool` (true only for `.hotkey`).
  - `enum CleanupChoice: Equatable, Sendable { case builtIn(modelID: String), appleIntelligence, connection(ModelConnection, local: Bool), none }`
  - `enum OnboardingSetup { static func apply(_ choice: CleanupChoice, to models: inout ModelSettings); static func choices(appleIntelligence: Bool, builtInEnabled: Bool) -> [CleanupChoiceKind] }` with `enum CleanupChoiceKind: Sendable { case builtIn, appleIntelligence, localApp, cloud, none }`.

- [ ] **Step 1: Write failing tests:**

```swift
@Test func stepsRunInOrder() {
    #expect(OnboardingStep.allCases.map(\.number) == [1, 2, 3, 4, 5, 6, 7])
    #expect(OnboardingStep.welcome.previous == nil)
    #expect(OnboardingStep.finish.next == nil)
    #expect(OnboardingStep.allCases.filter(\.probesHotkey) == [.hotkey])
}
@Test func connectionChoiceSetsDictationAndMeetings() {
    var m = AppSettings.freshInstall().models
    let c = ModelConnection(id: "server-abc123", name: "LM Studio", kind: .openAICompatible, baseURL: "http://localhost:1234/v1", model: "qwen3-4b")
    OnboardingSetup.apply(.connection(c, local: true), to: &m)
    #expect(m.connections == [c])
    #expect(m.dictation.engine == .connection("server-abc123"))
    #expect(m.dictation.disableThinking == true)
    #expect(m.notes == nil)
    #expect(m.meetings.engine == .connection("server-abc123"))
}
@Test func reapplyingSameConnectionReplacesIt() { /* apply twice with same id, different model → one entry, latest model */ }
@Test func appleIntelligenceLeavesMeetingsAlone() {
    var m = AppSettings.freshInstall().models
    OnboardingSetup.apply(.appleIntelligence, to: &m)
    #expect(m.dictation.engine == .appleIntelligence)
    #expect(m.meetings.engine == .none)
}
@Test func noneTurnsCleanupOff() { /* from a connection setup, apply(.none) → dictation .none, connections kept */ }
@Test func choicesHideUnavailableKinds() {
    #expect(OnboardingSetup.choices(appleIntelligence: false, builtInEnabled: false) == [.localApp, .cloud, .none])
    #expect(OnboardingSetup.choices(appleIntelligence: true, builtInEnabled: true) == [.builtIn, .appleIntelligence, .localApp, .cloud, .none])
}
```

`.builtIn` application is tested in Task 10, once the engine case exists; until then `apply(.builtIn…)` is unreachable because `builtInEnabled` is false (implement it in Task 10).

- [ ] **Step 2:** `swift test --filter OnboardingTests` → FAIL.
- [ ] **Step 3:** Implement. Cloud connections (`local: false`) keep `disableThinking` false.
- [ ] **Step 4:** `swift test` → PASS.
- [ ] **Step 5:** Commit `feat(core): onboarding steps and cleanup choice`.

### Task 3: Hotkey probe

**Files:**
- Modify: `Sources/BugVoice/DictationController.swift` (`receive(_:)`, ~line 108)
- Modify: `Sources/BugVoice/AppModel.swift` (new observable property)

**Interfaces:**
- Produces: `AppModel.hotkeyProbe: (() -> Void)?` (`@ObservationIgnored`). While non-nil, a `.hotkeyDown` calls it and the input is dropped (detector not fed, no recording). Key-up and other inputs are also dropped while the probe is set.

- [ ] **Step 1:** In `receive(_:)`, before the `isBusy` guard: `if let probe = model.hotkeyProbe { if case .hotkeyDown = input { probe() }; return }`.
- [ ] **Step 2:** `swift build` → succeeds; `swift test` → PASS.
- [ ] **Step 3:** Commit `feat(app): hotkey probe for onboarding`.

### Task 4: Onboarding window, steps 1–4 and 7, launch wiring

**Files:**
- Create: `Sources/BugVoice/UI/Onboarding/OnboardingWindowController.swift`
- Create: `Sources/BugVoice/UI/Onboarding/OnboardingView.swift` (frame: title, footer with dots, "Step N of 7", Back, Skip, primary)
- Create: `Sources/BugVoice/UI/Onboarding/OnboardingSteps.swift` (Welcome, Hotkey, Permissions, Speech, Finish bodies)
- Modify: `Sources/BugVoice/BugVoiceApp.swift` (lazy controller, `model.presentOnboarding`)
- Modify: `Sources/BugVoice/AppModel.swift:443` (launch: `if !settings.onboardingDone { openOnboarding() } else if !permissionsGranted { openPermissionsWindow() }`)
- Modify: `Sources/BugVoice/UI/Settings/GeneralTab.swift` (button "Run setup again"; settings search keywords "setup, onboarding, get started")

**Interfaces:**
- Consumes: `OnboardingStep` (Task 2), `AppModel.hotkeyProbe` (Task 3), existing `permissionStatus`, `refreshPermissions()`, `Permissions.openSettings(_:)`, `speechState`, `SpeechTab.whisperModels`, `HotkeyKey`.
- Produces: `AppModel.openOnboarding(at: OnboardingStep = .welcome)`, `AppModel.finishOnboarding()` (sets `settings.onboardingDone = true`, clears `hotkeyProbe`). Window id `AppWindow.onboarding`.

- [ ] **Step 1:** Build the window controller like `PermissionsWindowController` (keeps the window, `NSApp.setActivationPolicy(.regular)` on show, 1 s permission polling only while the window is open). `windowWillClose` calls `finishOnboarding()` (closing = skip, per spec).
- [ ] **Step 2:** Steps per the mockup and spec Part 2: Hotkey step sets `model.hotkeyProbe` on appear and clears it on disappear; shows "Key seen. It works." for 2 s after a probe call; shows the Input Monitoring note when `permissionStatus[.inputMonitoring] == false`. Speech step reads `speechState` (downloading N %, ready, failed with Retry). Finish step: mockup "Step 7: Take the tour or start"; "Skip, start using BugVoice" → `finishOnboarding()` and close; "Take a 1-minute tour" → `finishOnboarding()`, close, `startTour()` (no-op until Task 5b).
- [ ] **Step 3:** Steps 5 and 6 render a placeholder "Continue" body for now (filled in Task 5).
- [ ] **Step 4:** `Scripts/build-app.sh && Scripts/run-dev-app.sh` with `settings.json` moved aside (back it up first, restore after): onboarding opens; Back/Skip/Skip setup behave; closing the window and relaunching does not reopen it; "Run setup again" reopens at step 1. Restore the owner's `settings.json`.
- [ ] **Step 5:** `swift test` → PASS. Commit `feat(app): onboarding window`.

### Task 5: Cleanup step (5a, 5c) and Try it (6)

**Files:**
- Create: `Sources/BugVoice/UI/Onboarding/OnboardingCleanupStep.swift`
- Create: `Sources/BugVoice/UI/Onboarding/OnboardingTryItStep.swift`

**Interfaces:**
- Consumes: `OnboardingSetup.choices/apply` (Task 2), `AppModel.testConnection(_:)`, `connectionStatus`, `credentials`/`saveKey(_:account:)`, `appleIntelligenceAvailable`, `ModelConnection.newID(for:)`, the existing Models › "Send test sentence" code path for the cleaned-result line.
- Produces: `AppModel.lastTryItResult: TryItResult?` where `struct TryItResult { var text: String; var speechSeconds: Double; var cleanupSeconds: Double?; var cleanupName: String?; var problem: String? }`, filled by `DictationController` when the paste target is the Try-it text view.

- [ ] **Step 1:** 5a radio list from `OnboardingSetup.choices(appleIntelligence:builtInEnabled: false)`. "An app I already run": app picker LM Studio (`http://localhost:1234/v1`), Ollama (`http://localhost:11434/v1`), oMLX (`http://localhost:8000`), Other (address field); model picker filled from `connectionStatus[id] == .reachable(models:)`; Test. "A cloud service": OpenAI / Anthropic / OpenRouter, key field (saved with `saveKey` under `credentialAccount`), model field, Test, and the line "Your dictated text is sent to this service. Audio stays on this Mac." Continue applies the choice with `OnboardingSetup.apply`.
- [ ] **Step 2:** Try it: an `NSTextView`-backed box that is first responder on appear; the prompt uses `settings.hotkey.spokenName`; the result row shows "It works" with times and model, or `problem` (speech still downloading N %, cleanup failed: reason). Try again clears the box.
- [ ] **Step 3:** Device check with the owner away from the keyboard (or the owner doing it): pick oMLX, Test passes, Try it pastes into the box only.
- [ ] **Step 4:** `swift test` → PASS. Commit `feat(app): onboarding cleanup and try-it steps`.

### Task 5b: Main-window tour

**Files:**
- Create: `Sources/VoiceCore/Tour.swift`
- Test: `Tests/VoiceCoreTests/TourTests.swift`
- Create: `Sources/BugVoice/UI/Tour/TourOverlay.swift` (dim layer, ring, popover, Esc)
- Create: `Sources/BugVoice/UI/Tour/TourAnchor.swift` (`View.tourAnchor(_ stop: TourStop)` via anchor preferences)
- Modify: `Sources/BugVoice/UI/Shell/AppSidebar.swift` (anchors on Dictation, Scratchpad, Dictionary, Style rows), `Sources/BugVoice/UI/Shell/PageActions.swift` (anchor on the "Record meeting" split button), `Sources/BugVoice/UI/MainWindow.swift` (overlay; top-right anchor for stop 1), `Sources/BugVoice/UI/Settings/GeneralTab.swift` and `Sources/BugVoice/UI/Menu/MenuSections.swift` ("Take the tour")

**Interfaces:**
- Consumes: `AppModel.page`, `Page`, `ShortcutSettings.letter(for:)`, `settings.hotkey.spokenName`.
- Produces:
  - `enum TourStop: String, CaseIterable, Sendable { case menuBar, dictation, recordMeeting, scratchpad, dictionary, style }`
  - `struct TourCard: Equatable, Sendable { let stop: TourStop; let title: String; let body: String }`
  - `enum Tour { static func cards(hotkey: String, meetingShortcut: String?, scratchpadShortcut: String?) -> [TourCard]; static func visibleStops(_ cards: [TourCard], onScreen: Set<TourStop>) -> [TourCard] }`
  - `AppModel.startTour()`, `AppModel.tourIndex: Int?` (nil = no tour), `AppModel.endTour()`; the page for each stop: `.dictation` for menuBar and dictation, `.meetings`, `.notes`, `.dictionary`, `.style`.

- [ ] **Step 1: Failing tests:** `cards(hotkey: "Right Control", meetingShortcut: "⌃⌥M", scratchpadShortcut: "⌃⌥N")` gives the six stops in spec order with the spec's exact titles and bodies (shortcut and key substituted); with `meetingShortcut: nil` stop 3's body is "Record a call and get a transcript, summary and action items." and with `scratchpadShortcut: nil` stop 4's is "Speak into a note."; `visibleStops` keeps order and drops stops not on screen; `visibleStops(_, onScreen: [])` is empty.
- [ ] **Step 2–4:** FAIL → implement → `swift test` PASS.
- [ ] **Step 5:** App: `startTour()` opens the main window, computes on-screen anchors after one layout pass, does nothing if none are visible; Next/Back switch `model.page` then move the ring; Done/End tour/Esc call `endTour()`. Popover for stop 1 points up from the window's top-right corner. The overlay swallows clicks outside the popover so nothing starts a recording or paste.
- [ ] **Step 6:** Device check on the non-primary display: run from onboarding finish, from Settings › General and from the menu popover; Esc ends; narrow window skips stops whose target is hidden; compare with the mockup's tour section.
- [ ] **Step 7:** Commit `feat(app): main-window tour`.

### Task 6: DMG layout and install help

**Files:**
- Create: `App/DMG/background.svg` (660×420 pt; drag arrow, "1. Drag BugVoice into Applications", "2. …Not Opened…" with Way A and Way B text as in the mockup)
- Create: `Scripts/make-dmg-background.sh` (SVG → `App/DMG/background.png` and `@2x`, same tool as `Scripts/make-app-icon.sh`)
- Create: `App/DMG/Read Me First.md` and generated `App/DMG/Read Me First.pdf`
- Create: `App/DMG/screenshots/` (two PNGs, captured in Step 4)
- Modify: `Scripts/build-dmg.sh`
- Modify: `Sources/BugVoice/UI/Settings/GeneralTab.swift` (update note: Way A first, then Way B with the existing copy button)

- [ ] **Step 1:** `build-dmg.sh`: create a UDRW image from staging (add `.background/background.png` and the PDF), attach with `-nobrowse` off, run Finder AppleScript (window bounds, icon view, icon size 96, background picture, positions: app (165, 150), Applications (495, 150), PDF (330, 330)), `sync`, detach, convert to UDZO, `hdiutil verify`. If `osascript` fails, exit 1 with "Finder automation is needed to lay out the DMG. Allow Terminal under Privacy & Security › Automation."
- [ ] **Step 2:** Build: `SKIP_BUILD=1 Scripts/build-dmg.sh`, mount the result, screenshot the Finder window (BugVoice-free, on the non-primary display) and compare with mockup Part 1.
- [ ] **Step 3:** Update note copy in `GeneralTab.swift`.
- [ ] **Step 4 (owner present):** copy the app to a temp folder, `xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" <copy>`, open it, capture the "Not Opened" alert and the Privacy & Security row on the non-primary display, save as `App/DMG/screenshots/not-opened.png` and `open-anyway.png`, delete the copy. Generate the PDF from the Markdown (builder's tool choice, no new dependency in the package).
- [ ] **Step 5:** Commit `build: DMG layout with install help`.

### Task 7: Phase 1 log and docs

**Files:**
- Create: `docs/progress/onboarding-log.md` (what shipped per task, device checks with results)
- Modify: `CLAUDE.md` (Key documents: spec, plan, mockup, log)

- [ ] **Step 1:** Record device checks: fresh install path, tour (all three entry points), existing install path (no onboarding), Skip setup, Run setup again, hotkey probe does not dictate, Try it, DMG window, update note.
- [ ] **Step 2:** Commit `docs: onboarding log and key documents`.

## Phase 2 — Bench gate

### Task 8: Bench candidate models through `llama-server`

**Files:**
- Create: `Scripts/llama-server.env` (`LLAMA_TAG=…`, `LLAMA_ZIP_SHA256=…`)
- Create: `Scripts/fetch-llama-server.sh` (downloads `https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_TAG/llama-$LLAMA_TAG-bin-macos-arm64.zip` into `build/cache/`, verifies `shasum -a 256`, unzips to `build/cache/llama-$LLAMA_TAG/`)
- Modify: `docs/progress/onboarding-log.md` (bench section)

- [ ] **Step 1:** Pick the latest llama.cpp release at least two weeks old; record its tag and the zip's SHA-256 in `llama-server.env`.
- [ ] **Step 2:** Candidates (Q4_K_M GGUF from the publisher's own repo, Apache-2.0 or MIT licence only): Qwen3 1.7B, Qwen3 4B, Qwen3 8B, plus the newest Apache-2.0 Qwen small models published by Qwen at bench time (at most two). Record repo, revision, file, size, SHA-256, licence.
- [ ] **Step 3:** For each: run `llama-server -m <file> --host 127.0.0.1 --port <p> --api-key <k> -c 4096 -ngl 999 --jinja`, add it as an OpenAI-compatible connection in a scratch settings copy, and run `bugvoice-bench --fidelity-history <path>` plus the existing English, Vietnamese and mixed test sentences. Measure: median warm cleanup time for 10–20 word dictations, first-load time, resident memory (`ps -o rss`), fidelity failures vs the owner's oMLX model.
- [ ] **Step 4:** Apply the spec's gate: Small ≤ 1.0 s, Medium ≤ 1.5 s, Large ≤ 2.5 s median, fidelity failures ≤ oMLX's. Pick one model per passing tier; set `memoryShare` for the fit rule from the measured RSS (largest model whose RSS ≤ share × RAM). If no tier passes, stop here: Phase 3 is not built and Built-in stays hidden.
- [ ] **Step 5:** Owner reviews the bench table and the picks. Commit `docs: built-in model bench` (with the two scripts).

## Phase 3 — Built-in engine (only after Task 8 passes)

### Task 9: Built-in catalog and fit rule

**Files:**
- Create: `Sources/VoiceCore/BuiltInCatalog.swift`
- Test: `Tests/VoiceCoreTests/BuiltInCatalogTests.swift`

**Interfaces:**
- Produces: `struct BuiltInModel: Equatable, Sendable, Identifiable { enum Tier: String, Sendable { case small, medium, large }; let id: String; let tier: Tier; let name: String; let summary: String; let fileName: String; let url: URL; let sha256: String; let bytes: Int64; let memoryBytes: Int64; let speed: Int; let quality: Int }` (speed/quality 1…3); `enum BuiltInCatalog { static let models: [BuiltInModel]; static let memoryShare: Double; static func model(id: String) -> BuiltInModel?; static func recommended(physicalMemory: UInt64) -> BuiltInModel? }`.

- [ ] **Step 1: Failing tests:** catalog ordered small→large, ids unique, every `url` is `https://huggingface.co/…/resolve/<40-hex revision>/…`, every `sha256` is 64 lowercase hex; `recommended` returns the largest model with `memoryBytes ≤ memoryShare × RAM`: nil for 1 GB (even Small does not fit), the Large model for 96 GB, and for 16 GB whichever tier Task 8's numbers put there (assert by computing from the catalog, not a hard-coded id).
- [ ] **Step 2–4:** FAIL → implement with Task 8's values → PASS.
- [ ] **Step 5:** Commit `feat(core): built-in model catalog`.

### Task 10: Built-in engine in settings, resolver and readiness

**Files:**
- Modify: `Sources/VoiceCore/ModelSettings.swift` (`ModelEngine`)
- Modify: `Sources/VoiceCore/ModelResolver.swift`
- Modify: `Sources/VoiceCore/Readiness.swift`
- Modify: `Sources/VoiceCore/Onboarding.swift` (`apply(.builtIn…)`)
- Test: `Tests/VoiceCoreTests/ModelSettingsTests.swift`, `ModelResolverTests.swift`, `ReadinessTests.swift`, `OnboardingTests.swift`

**Interfaces:**
- Consumes: `BuiltInCatalog` (Task 9).
- Produces:
  - `ModelEngine.builtIn(String)`, encoded `{"builtIn":"<id>"}`.
  - `ModelSettings.builtInIdleMinutes: Int` (default 15, allowed 5, 15, 30, 60; any other decoded value → 15), key `builtInIdleMinutes`.
  - `ModelPlan.builtIn(BuiltInModel, timeout: TimeInterval)`; `shortName` = model name.
  - `ModelResolver.plan(for:settings:cliPaths:appleIntelligenceAvailable:builtInInstalled: Set<String>)` (new parameter, default `[]` for existing call sites).
  - `CleanupCheck.builtIn(name: String, state: BuiltInState)` with `enum BuiltInState: Equatable, Sendable { case ready, downloading(Double), notDownloaded, failed(String) }`; `ReadinessAction.downloadBuiltIn`.

- [ ] **Step 1: Failing tests:**
  - round trip `{"builtIn":"qwen3-4b"}`; a dictation engine `{"builtIn":"x"}` read by today's decoder path still falls back to the default (documented downgrade);
  - resolver: dictation `.builtIn(id)` installed → `.builtIn(model, timeout: settings.dictationTimeoutSeconds)`; not installed → `.unavailable("<name> is not downloaded. Download it in Settings → Models.")`; unknown id → `.unavailable("This built-in model is no longer offered. Choose another in Settings → Models.")`; meetings `.builtIn` → `.unavailable("Built-in models are for Dictation and Notes.")`; notes `.builtIn(other)` while dictation is `.builtIn(id)` → `.unavailable("Notes must use the same built-in model as Dictation.")`;
  - `builtInIdleMinutes` round trip; decoding 7 gives 15;
  - readiness rows: ready → "<name>, built in" ok; downloading 0.41 → "Downloading <name>, 41%" waiting; notDownloaded → "<name> not downloaded" problem, action `.downloadBuiltIn`, title "Download"; failed(msg) → "<name>: <msg>" problem, `.openModels`;
  - `OnboardingSetup.apply(.builtIn(modelID: "qwen3-4b"))` → dictation `.builtIn("qwen3-4b")`, `disableThinking` true, notes nil, meetings unchanged.
- [ ] **Step 2–4:** FAIL → implement → `swift test` PASS. Update every `switch` over `ModelEngine`/`ModelPlan` in the app target so it builds (`ProviderFactory` returns `UnavailableModel` for `.builtIn` until Task 13).
- [ ] **Step 5:** Commit `feat(core): built-in engine in settings, resolver and readiness`.

### Task 11: Model download with resume and SHA-256

**Files:**
- Create: `Sources/VoiceCore/BuiltInDownloadPlan.swift`
- Create: `Sources/BugVoiceMac/BuiltInDownloader.swift` (URLSession + CryptoKit)
- Modify: `Sources/VoiceCore/AppPaths.swift` (`cleanupModels: URL` = `root/Models/Cleanup`)
- Test: `Tests/VoiceCoreTests/BuiltInDownloadPlanTests.swift`, `Tests/BugVoiceMacTests/BuiltInDownloaderTests.swift`

**Interfaces:**
- Produces: `enum BuiltInDownloadPlan { static func partialURL(for: BuiltInModel, in dir: URL) -> URL /* <file>.part */; static func finalURL(for:in:) -> URL; static func next(partialBytes: Int64?, expected: Int64) -> DownloadStep }` with `enum DownloadStep: Equatable { case start, resume(rangeHeader: String), verify, restart }`; `final class BuiltInDownloader: Sendable` with `func download(_ model: BuiltInModel, into dir: URL, progress: @Sendable (Double) -> Void) async throws -> URL`, `static func sha256Hex(of url: URL) throws -> String` (streamed in 1 MB chunks), errors `BuiltInDownloadError.hashMismatch`, `.notEnoughSpace(neededBytes:)`.

- [ ] **Step 1: Failing tests:** `next(nil, 100) == .start`; `next(40, 100) == .resume(rangeHeader: "bytes=40-")`; `next(100, 100) == .verify`; `next(150, 100) == .restart`; `next(0, 100) == .start`; `sha256Hex` of a temp file with `"abc"` equals `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`; a verify step with a wrong hash deletes the file and throws `.hashMismatch`.
- [ ] **Step 2–4:** FAIL → implement (check free space with `volumeAvailableCapacityForImportantUsageKey` before starting; on HTTP 200 to a range request, restart from 0) → PASS.
- [ ] **Step 5:** Commit `feat(core): built-in model download plan and verifier`.

### Task 12: Bundle `llama-server` in the app

**Files:**
- Modify: `Scripts/build-app.sh` (call `Scripts/fetch-llama-server.sh`; copy `llama-server` and its `*.dylib` into `Contents/Helpers/`; sign dylibs, then the binary, before the app)
- Modify: `THIRD_PARTY_NOTICES.md` (llama.cpp, MIT, tag from `llama-server.env`)

- [ ] **Step 1:** `otool -L build/cache/llama-$TAG/llama-server` → confirm dylibs resolve via `@rpath`/`@loader_path`; set rpath with `install_name_tool -add_rpath @loader_path` if needed.
- [ ] **Step 2:** Sign with `--options runtime` like `bugvoice-mcp`. If the helper then fails to load its dylibs (library validation without a Team ID), sign the helper and its dylibs without `--options runtime` and note why in the script comment.
- [ ] **Step 3:** `Scripts/build-app.sh && codesign --verify --strict build/BugVoice.app && build/BugVoice.app/Contents/Helpers/llama-server --version` → prints the pinned tag.
- [ ] **Step 4:** Commit `build: bundle llama-server helper`.

### Task 13: Server lifecycle and the built-in text model

**Files:**
- Create: `Sources/VoiceCore/BuiltInServer.swift` (protocol, arguments, idle rule, text model)
- Create: `Sources/BugVoice/BuiltInServerController.swift` (process management)
- Modify: `Sources/BugVoice/ProviderFactory.swift`, `Sources/BugVoice/AppModel.swift` (own the controller; preload at launch when dictation is built-in; stop on quit)
- Test: `Tests/VoiceCoreTests/BuiltInServerTests.swift`

**Interfaces:**
- Produces:
  - `struct BuiltInEndpoint: Sendable, Equatable { let baseURL: URL; let apiKey: String }`
  - `protocol BuiltInServing: Sendable { func endpoint(for model: BuiltInModel) async throws -> BuiltInEndpoint; func noteUse() async }`
  - `enum BuiltInServerArguments { static func make(modelPath: String, port: Int, apiKey: String) -> [String] }` → `["-m", path, "--host", "127.0.0.1", "--port", "\(port)", "--api-key", key, "-c", "4096", "-ngl", "999", "--jinja"]`
  - `enum BuiltInIdle { static func shouldStop(lastUse: Date, now: Date, idleMinutes: Int) -> Bool }`
  - `struct BuiltInTextModel: TextModel { init(model: BuiltInModel, server: any BuiltInServing, requestTimeout: TimeInterval) }` — awaits `endpoint`, then delegates to `OpenAICompatibleModel(baseURL:model: model.id, apiKey:flavor: .local, requestTimeout:)`; calls `noteUse()` after.
  - `@MainActor final class BuiltInServerController: BuiltInServing` (app): one process; restarts when the model differs or the process died; free port via binding a socket to port 0; per-launch random key (32 bytes, `SecRandomCopyBytes`, hex); waits for `GET /health` 200 (poll 100 ms, give up after 60 s with "The built-in model did not start."); pid file `AppPaths.root/llama-server.pid`, stale pid killed at launch only if its executable path is our helper; idle check every minute against `settings.models.builtInIdleMinutes`.
- [ ] **Step 1: Failing tests:** arguments exact array; `shouldStop` at 14:59 false / 15:00 true; `BuiltInTextModel` with a fake `BuiltInServing` that throws → `clean` throws the same error (pipeline then pastes raw with the reason); with a fake that returns an endpoint pointing at a `URLProtocol` stub → request has `Authorization: Bearer <key>` and model id, and `noteUse` was called once.
- [ ] **Step 2–4:** FAIL → implement → PASS. `ProviderFactory.textModel` returns `BuiltInTextModel` for `.builtIn`; `cleanupModel` gives `modelID: model.id, disableThinking: true, timeoutSeconds: timeout`.
- [ ] **Step 5:** Device check: choose a downloaded model by editing a scratch settings copy, run the dev app, confirm `lsof -iTCP -sTCP:LISTEN -P | rg llama` shows `127.0.0.1` only, a request without the key gets 401, the process exits on app quit and after 15 min idle (set the idle rule's minimum to 1 minute in a local build for the check, then revert).
- [ ] **Step 6:** Commit `feat(app): built-in model server`.

### Task 14: Built-in UI — Settings card, pickers, readiness, onboarding 5b

**Files:**
- Create: `Sources/BugVoice/UI/Settings/Models/BuiltInModelsCard.swift`
- Create: `Sources/BugVoice/AppModel+BuiltIn.swift` (`builtInInstalled: Set<String>` from disk, `builtInDownloads: [String: Double]`, `downloadBuiltIn(_:)`, `cancelBuiltInDownload(_:)`, `deleteBuiltIn(_:)`)
- Modify: `Sources/BugVoice/UI/Settings/Models/UseForCard.swift` (Dictation/Notes pickers: "Built-in · <name>" for installed models; Notes shows only Dictation's built-in model)
- Modify: `Sources/BugVoice/AppModel+Models.swift` (pass `builtInInstalled` to the resolver), `AppModel+Readiness.swift` (map `.builtIn` plan to `CleanupCheck.builtIn`; `.downloadBuiltIn` action)
- Modify: `Sources/BugVoice/UI/Onboarding/OnboardingCleanupStep.swift` (`builtInEnabled: !BuiltInCatalog.models.isEmpty`; 5b list with "Fits this Mac" from `recommended(physicalMemory:)`, "Download N GB", progress, Cancel, self-test sentence result)
- Modify: `Sources/BugVoice/UI/Menu/MenuSubmenus.swift` (engine submenu lists installed built-in models)

- [ ] **Step 1:** Implement per mockup sections "Step 5b" and "Settings › Models: Built-in models card". The card has an "Unload after" picker (5, 15, 30, 60 minutes idle) bound to `builtInIdleMinutes`. Deleting the model in use sets Dictation to `.none` after a confirmation ("Delete <name>? Dictation cleanup turns off until you choose another model.").
- [ ] **Step 2:** Self-test sentence (fixed): "um so tomorrow mình họp lúc ba giờ nha, uh, with the design team". Show cleaned text and seconds.
- [ ] **Step 3:** Device check (owner away, or owner doing it): fresh-install run through 5b with the Small model, cancel mid-download and resume, Try it pastes cleaned text, Readiness shows "<name>, built in", Delete flips readiness to "Off".
- [ ] **Step 4:** `swift test` → PASS. Commit `feat(app): built-in models in onboarding and settings`.

### Task 15: Final log, docs and release check

**Files:**
- Modify: `docs/progress/onboarding-log.md`, `CLAUDE.md` (key documents), `docs/ROADMAP.md` (mark done)

- [ ] **Step 1:** `swift test` full run, `Scripts/build-dmg.sh`, install the DMG on this Mac from a browser download (quarantined) and walk Way A end to end with the owner.
- [ ] **Step 2:** Record results and open device checks in the log. Commit `docs: onboarding and built-in model log`.
