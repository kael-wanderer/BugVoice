# Onboarding and built-in cleanup model — design (2026-11-06)

Mockup: `docs/design/proposal-onboarding.html` (approved by the owner 2026-11-06).

## Why

BugVoice works well for its owner, who already runs oMLX and has API keys. For anyone else,
the first hour goes wrong in three places:

1. **Install.** The DMG is downloaded in a browser, so macOS adds a quarantine flag and refuses
   the first open ("BugVoice Not Opened"). The way past it, `xattr -cr /Applications/BugVoice.app`,
   is shown only in the update note inside Settings, which the user cannot reach yet.
2. **First launch.** There is no first-run flow. The app opens the Permissions window if a grant
   is missing, and that is all. Nothing explains the hotkey or checks that dictation works.
3. **Cleanup model.** A fresh install points dictation cleanup at an oMLX connection on
   `localhost:8000` (`ModelSettings.defaultConnection`). On a Mac without oMLX every dictation
   falls back to raw text with a "model unavailable" note. A non-technical user has no LM Studio,
   no Ollama and no API key, so they never get cleanup.

Goal: someone who has never used a terminal installs BugVoice, gets past Gatekeeper, finishes a
short setup and pastes cleaned text, without installing anything else.

Prior art the owner pointed to: Bugler's onboarding (`../Bugler/Sources/Bugler/Features/OnboardingView.swift`:
every step skippable and repeatable, step dots, Back, "Start Using"); Superwhisper's S1-mini and
VoiceInk Refine (cleanup models that the app downloads and runs itself).

## Goals

- DMG window that shows how to install and both ways past the Gatekeeper block.
- A 7-step onboarding window on first launch, reopenable from Settings.
- A **built-in cleanup model**: BugVoice downloads a model with one click, with progress, and runs
  it itself. No other app to install.
- A short tour of the main window (6 stops), offered at the end of onboarding and runnable later.

## Non-goals

- Apple Developer ID signing or notarization (personal app, no Team ID).
- A built-in model for Meetings summaries or Ask AI in this project. The engine choice must allow
  it later; this project wires it to Dictation and Notes cleanup only.
- Replacing WhisperKit or adding a built-in speech engine (VibeVoice and others were reviewed and
  set aside on 2026-11-06).
- Teaching every feature. The tour is 6 stops, about a minute, not a manual.

## Anti-goals

- Onboarding that blocks the app. Every step can be skipped; Skip setup ends it at once.
- Pasting into another app during setup. The "Try it" step pastes into a text box in the
  onboarding window only.
- Showing onboarding to the owner's existing install on upgrade.
- Downloading or running unverified code. Model files are checked against a pinned SHA-256;
  executables are never downloaded at run time.
- Text or audio leaving the Mac without the user picking a cloud service.

## Part 1 — DMG install help

`Scripts/build-dmg.sh` produces a DMG whose Finder window shows:

- a background image: "1. Drag BugVoice into Applications" with an arrow from the app icon to
  the Applications shortcut;
- below it: "2. Open BugVoice. If macOS says *BugVoice Not Opened*, use one of these:"
  - **Way A — System Settings (Easiest):** click Done on the message; open System Settings ›
    Privacy & Security; scroll down and click Open Anyway next to BugVoice; enter your Mac password.
  - **Way B — Terminal:** paste `xattr -cr /Applications/BugVoice.app`, press Return, open BugVoice again.
- a `Read Me First.pdf` in the DMG with the same steps and screenshots of the two macOS screens
  (the "Not Opened" alert and the Privacy & Security row with Open Anyway).

Way A goes first because it needs no Terminal. On macOS 15 and later, right-click › Open no longer
bypasses the block, so it is not mentioned.

The update note in Settings › General (`GeneralTab.swift`, `unquarantineCommand`) gets the same
two ways, Way A first.

Mechanics (builder's call within these limits): build a read-write image, mount it, set the
background picture, icon size and icon positions through Finder AppleScript, detach, convert to
compressed read-only. The background is generated from an SVG checked into `App/DMG/`, like the
app icon. If Finder scripting is unavailable (no Automation permission), the script fails with a
clear message rather than producing a DMG without the help.

## Part 2 — Onboarding window

A window of its own (not a sheet over the main window), about 620×460 points, with the
step dots, "Step N of 7", Back, Skip (where shown) and a primary button in the footer, as in the
mockup. Every string is plain English, no hedging, no emoji (the mockup's emoji icons become SF Symbols).

### When it shows

- New setting `onboardingDone`. A fresh `AppSettings()` has `false`; decoding a settings file
  that lacks the key gives `true`. So a brand-new install sees onboarding and every existing
  install, including the owner's, does not.
- Shown at the end of launch when `onboardingDone == false`. It replaces the automatic
  Permissions window on that launch (the Permissions step covers it).
- Finishing, or Skip setup at any step, sets `onboardingDone = true`.
- Settings › General gets "Run setup again", which opens the window at step 1 without changing
  any settings until the user changes them in a step.

### Steps

1. **Welcome.** Icon, "Talk instead of type", one line on what BugVoice does, "Setup takes about
   3 minutes." Buttons: Skip setup, Get started.
2. **Hotkey.** Talk-key picker (the same `HotkeyKey` choices as Settings), default Right Control.
   While this step is visible, pressing the chosen key shows "Key seen. It works." and does **not**
   start a dictation. If Input Monitoring is off the key cannot be seen; the step says so and says
   the next step fixes it.
3. **Permissions.** Microphone, Input Monitoring, Accessibility (required), System audio
   (optional, for Meetings). Same checks and buttons as the Permissions window, refreshed once a
   second while the step is visible. Continue is always enabled; anything missing stays on the
   Readiness card.
4. **Speech model.** Shows the WhisperKit model download that already starts at launch
   (`prepareSpeech`): name, size, progress, "You can continue." The user can move on before it
   finishes. The model picker stays in Settings › Speech; the step notes that 8 GB Macs can choose
   a smaller model there.
5. **Cleanup model.**
   - 5a: choose one of Built-in model (Recommended), Apple Intelligence (shown only when
     `appleIntelligenceAvailable`), An app I already run, A cloud service, No cleanup.
   - 5b (Built-in): the model list from the built-in catalog (Part 3), small to large, with
     speed and quality bars, size, and a "Fits this Mac" badge on the recommended one. "Download
     N GB" starts the download with progress, time left and Cancel. When done the model loads and
     cleans one fixed test sentence; the step shows the cleaned result and the time it took.
     A failed download shows the reason and Try again, which resumes.
   - 5c (An app I already run / A cloud service): a cut-down connection form (app or service,
     address or API key, model) with Test. Test uses the existing connection check. The
     cloud form says "Your dictated text is sent to this service. Audio stays on this Mac."
   - Whatever the user picks becomes the Dictation (and Notes) engine. No cleanup sets it to
     `.none`.
   - A fresh install starts with cleanup `.none` and no oMLX connection (see Decisions), so a new
     user never starts out pointed at a server they do not have.
6. **Try it.** A text box in the onboarding window and the prompt "Click the box, hold
   <key>, say a sentence, let go." The dictation pastes into that box (BugVoice is frontmost).
   A result row shows "It works", the speech and cleanup times and which cleanup model ran, or
   the reason it did not (for example "Speech model still downloading, 62%"). Try again repeats.
7. **Tour or start.** "You are ready", "Hold <key> in any app to speak." and two buttons:
   "Take a 1-minute tour" (primary) and "Skip, start using BugVoice". Both end onboarding
   (`onboardingDone = true`) and close the window; the tour then opens the main window and starts.

### The tour (owner decided 2026-11-06)

Six stops in the main window, in this order. The window is dimmed except the target, which gets
an accent ring; a popover attached to the target shows the title, one line, "N of 6", End tour,
Back and Next (Done on the last). Esc ends the tour. Selecting a stop switches the main window to
that stop's page.

| # | Target | Page | Title | Text |
|---|---|---|---|---|
| 1 | Top-right of the main window, arrow pointing up toward the menu bar | Dictation | BugVoice lives in the menu bar | Click the BugVoice icon for status, quick actions and settings. The window can stay closed. |
| 2 | Sidebar › Dictation | Dictation | Dictate anywhere | Hold <key> in any app, speak, let go. Everything you dictated is listed here. |
| 3 | "Record meeting" button (page actions) | Meetings | Record a meeting | Record a call and get a transcript, summary and action items. Shortcut: <meeting shortcut>. |
| 4 | Sidebar › Scratchpad | Scratchpad | Scratchpad | Speak into a note. <scratchpad shortcut> opens a floating scratchpad from any app. |
| 5 | Sidebar › Dictionary | Dictionary | Your words | Add names and terms so they come out right every time. |
| 6 | Sidebar › Style | Style | Style | Terminal, chat and email each get their own cleanup. Change how each one reads here. |

- `<key>` is the user's talk key; the shortcuts are read from `ShortcutSettings` (defaults ⌃⌥M and
  ⌃⌥N) and the sentence is dropped if that shortcut is off.
- Stop 1 is not attached to the menu bar icon: popovers on a status item are unreliable. It sits
  in the main window's top-right corner, pointing up.
- A stop whose target is not on screen (page hidden, window too narrow) is skipped; if every stop
  is skipped the tour does not start.
- Run again from Settings › General ("Take the tour") and from the menu bar popover.
- The tour never starts a recording, opens a meeting window, or pastes.

## Part 3 — Built-in cleanup model

### What the user sees

- In onboarding step 5b (above).
- In Settings › Models: a **Built-in models** card listing the catalog. Each row: name, one-line
  description, size, speed/quality bars, and Download / Downloading N% (Cancel) / Delete. A
  downloaded model appears in the Dictation and Notes engine pickers as "Built-in · <name>".
- On the Readiness card, cleanup row: "<name>, built in" (green) when downloaded and loadable;
  "<name> not downloaded" (amber, Download); "Downloading <name>, N%" (grey); load failure reason
  (amber, Open Models).
- HUD shows "Cleaning (<short name>)" as for any other model.

### Runtime (owner chose llama-server on 2026-11-06)

The built-in model runs in **llama.cpp's `llama-server`**, bundled inside the app and started by
BugVoice as a child process on `127.0.0.1`. It speaks the OpenAI-compatible API BugVoice already
uses for local servers, so cleanup, timeouts, thinking control and the test sentence reuse the
existing `OpenAICompatibleModel` path.

Why not MLX Swift in-process: MLX needs its Metal shader library built by Xcode; `swift build`,
which `Scripts/build-app.sh` uses, does not produce it, and MLX would add several Swift packages
(mlx-swift, mlx-swift-lm, swift-transformers and their dependencies). `llama-server` adds no Swift
package, keeps model memory out of the BugVoice process, and a crash in it cannot take the app down.

Rules:

- **Binary.** A pinned llama.cpp release (tag and SHA-256 recorded in the build script) for
  macOS arm64. `Scripts/build-app.sh` fetches it once into a cache, verifies the hash, copies
  `llama-server` and its dylibs into `Contents/Helpers/`, and signs them with the same
  `Bugler Local Dev` identity. Nothing executable is downloaded by the app at run time.
  `THIRD_PARTY_NOTICES.md` gets the llama.cpp (MIT) entry.
- **Models.** GGUF files from the model publishers' own Hugging Face repos, pinned to a commit
  revision with a SHA-256, listed in a catalog in VoiceCore. Downloaded over HTTPS with resume
  (HTTP range) into `~/Library/Application Support/BugVoice/Models/Cleanup/`, verified, then
  moved into place. A file that fails the hash is deleted and reported.
- **Process.** Started on first need (Try it, test sentence, or the first dictation after launch
  with a built-in engine), with the model preloaded so the first dictation does not wait for it
  when possible. Bound to `127.0.0.1` on a free port, with a random per-launch API key so other
  local processes cannot use it. Stopped after a configurable idle time (default 15 minutes; it
  frees the model's memory), on app quit, and on model change. A stale server left by a crash
  is found by its pid file and stopped on the next launch.
- **Memory fit.** "Fits this Mac" picks the largest catalog model whose stated memory need is
  at most a fixed share of `ProcessInfo.physicalMemory`. The share and the per-model figures come
  from the bench.
- **Settings shape.** A new engine case for built-in models (for example
  `ModelEngine.builtIn(modelID)`); `ModelResolver` returns a plan for it; `ProviderFactory`
  makes the text model after the server is running. Older settings files decode unchanged.

### Catalog: chosen by a bench, not now

The mockup's names (Qwen3 1.7B / 4B / 8B) and sizes are placeholders. Before the catalog is
written, a bench runs 3–5 candidate GGUF models (4-bit) through `llama-server` with the existing
cleanup-fidelity replay and Vietnamese, English and mixed test sentences, on this Mac. It records
for each: cleanup latency for a short dictation, first-load time, resident memory, and fidelity
failures. The catalog keeps three tiers (Small, Medium, Large) chosen from those numbers; the
licence of each model must allow redistribution through a download link (Apache-2.0 or similar).
Results go in the execution log.

## Constraints

- Swift package, tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only.
- TDD for VoiceCore: the onboarding-done decoding, the cleanup-engine choice from a step, the
  built-in catalog and fit rule, download verification and resume logic, the resolver plan and
  Readiness rows for the built-in engine are all pure and tested.
- No new Swift package dependency.
- Release builds keep the `Bugler Local Dev` signature; the helper is signed with it too.
- Synthetic hotkey tests that end in a paste run only while the owner is away (project rule);
  the Try-it step's own paste target is BugVoice's text box, but device checks still follow the rule.

## Left to the builder

Window controller structure, view decomposition, how the hotkey step intercepts the key without
starting a dictation, the DMG background artwork beyond the mockup, the exact idle timeout UI,
the fixed test sentence, port selection, and how download progress is surfaced, as long as the
behavior above holds.

## Decisions settled after the builder check (Claude's calls unless marked)

- **Fresh-install model defaults.** A fresh install (no `settings.json`) starts with no oMLX
  connection and every feature's engine `.none`. Step 5 sets Dictation (Notes follows it). If
  step 5 picks a connection (local app or cloud), Meetings uses the same connection; if it picks
  Built-in, Apple Intelligence or No cleanup, Meetings stays `.none` and the Meetings page shows
  its existing "choose a model" state. Existing installs keep their settings untouched.
- **Leaving setup early.** Skip setup, or closing the window at any step, counts as finishing:
  `onboardingDone = true`. On a fresh install, if step 5 was never completed, the `.none` defaults
  above simply stay. The window does not come back on the next launch.
- **One built-in model at a time.** One `llama-server`, one loaded model. Notes can use the
  built-in engine only with the model Dictation uses; its picker shows that model and no other
  built-in entry. Changing Dictation's built-in model restarts the server with the new model.
- **Timeout.** Built-in plans use the existing dictation timeout like any local model.
- **Bench gate.** Measured warm on this Mac (M3 Ultra) with a 10–20 word dictation: a tier ships
  only if its median cleanup time is at most 1.0 s (Small), 1.5 s (Medium) or 2.5 s (Large) and it
  has no more fidelity-check failures on the replay than the owner's current oMLX model. A tier
  that fails is dropped; if no tier passes, Part 3 stops and Parts 1–2 ship with Built-in hidden.
  Slower Macs are expected to be slower; "Fits this Mac" only considers memory.
- **Gatekeeper screenshots.** Captured on this Mac by marking a copy of the app with the
  quarantine flag and opening it, with the owner present (the alert and System Settings open on
  the non-primary display). No recreated images.
- **Downgrade.** An older build reading a settings file that uses the built-in engine falls back
  to its default for that feature. Accepted: downgrades are rare and the choice is one click to
  restore.

## Owner decisions

- 2026-11-06: mockup approved; runtime is the bundled `llama-server` (option A), not MLX Swift.
- 2026-11-06: the built-in model is downloaded by BugVoice itself, with progress, not through a browser.
