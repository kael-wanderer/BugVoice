# Onboarding and built-in model execution log

Spec: `docs/superpowers/specs/2026-11-06-onboarding-and-built-in-model-design.md`
Plan: `docs/superpowers/plans/2026-11-06-onboarding-and-built-in-model.md`
Mockup: `docs/design/proposal-onboarding.html`

All three phases are built on `feat/onboarding`: Phase 1 (onboarding, tour, DMG
layout), Phase 2 (bench gate, Task 8, results in "Phase 2 — Bench" below) and
Phase 3 (built-in model, Tasks 9 to 14). Full `swift test` at the end of Task 15
passes: 1467 tests in 157 suites (VoiceCore), 30 in 2 suites and 136 in 23
suites. No device check has run; the owner was at the keyboard, so every one is
open in the list at the end of this log. A final fix wave is still to come.

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
  test run. Focused green: 7 tests. Full `swift test` after the commit (controller run):
  1395 VoiceCore + 30 + 114 tests passed.
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
  (1399 + 30 + 114); `Scripts/build-app.sh` ok.
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

## Phase 2 — Bench (Task 8, 2026-11-06)

Verdict: **all three tiers pass the gate.** Picks: Small `Qwen3-VL-2B-Instruct`
Q4_K_M, Medium `Qwen3-4B` Q4_K_M, Large `Qwen3-8B` Q4_K_M; `memoryShare` 0.30.
The owner reviews the picks before Phase 3 writes the catalog.

### Setup

- Runtime: llama.cpp `b11829` (2026-10-22, newest build at least two weeks old;
  the `v0.x` releases carry no macOS binaries). llama.cpp now ships the macOS
  arm64 build as `llama-b11829-bin-macos-arm64.tar.gz`, not a `.zip`;
  `Scripts/llama-server.env` records `LLAMA_ASSET` and the archive hash in
  `LLAMA_ZIP_SHA256` (`e006ea32abe757c10a93718d246796b9bb7eafd309398927ff7b69139e4ba27e`,
  matches GitHub's asset digest). `Scripts/fetch-llama-server.sh` downloads it to
  `build/cache/`, deletes it on a hash mismatch, refuses unsafe archive paths and
  unpacks to `build/cache/llama-b11829/`. `llama-server --version`: 0.7.0-dev
  (build 11829, commit 184f65360).
- Server: `llama-server -m <file> --host 127.0.0.1 --port <free port> --api-key <random 48 hex> -c 4096 -ngl 999 --jinja`,
  one at a time, killed by a trap after each model. `lsof` showed it listening
  on 127.0.0.1 only. No llama-server was left running.
- Bench: new `bugvoice-bench --cleanup-bench` (see `Sources/BugVoiceBench/CleanupBench.swift`).
  It sends each history dictation (50 non-command entries with raw text, read
  only) plus 12 fixed sentences (5 English, 3 Vietnamese, 4 mixed EN/VI; 14–17
  words) through the dictation cleanup path: `PromptBuilder` request (owner's
  language per entry, keep English words on for Vietnamese, thinking off,
  pipeline `maxTokens`), `OpenAICompatibleModel` `.local`, `OutputSanitizer`,
  then `FidelityCheck`. One discarded warm-up request, then `--runs 3`; time per
  input is its median over runs. 18 inputs fall in the 10–20 word bucket
  (6 history, 12 fixed). Empty vocabulary and default custom rules, so the
  prompt differs slightly from the owner's live one.
- Baseline: the owner's dictation model on oMLX (`Qwen3.8-27B-MLX-8bit`,
  `http://127.0.0.1:8000/v1`, key read from `credentials.json` into an env var),
  same bench, same 62 inputs.
- First load is server start to `/health` 200 with the file already in the page
  cache (the files had just been downloaded and hashed). A cold read from disk
  will be slower; the one run before the cache was warm (VL-2B) took 3.42 s
  against 0.40 s warm.
- RSS is `ps -o rss=` on the server after the bench (the higher of the two
  readings; after-load values were 0.3–0.5 GB lower), at `-c 4096`.

### Candidates and results

Licence of every repo: Apache-2.0 (Hugging Face `license:apache-2.0`). Files from
the Qwen organisation's own GGUF repos, pinned by commit, SHA-256 checked with
`shasum -a 256` after download (all matched the repo's LFS hash).

| Model | Repo | Revision | File | Size (bytes) | SHA-256 | First load s | RSS MB | Median s 10–20 w | P90 s | Overall median s | Flagged (per run) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| oMLX baseline | owner's `Qwen3.8-27B-MLX-8bit` | – | – | – | – | – | – | 1.360 | 1.779 | 1.016 | 0 (0, 0, 0) |
| Qwen3-VL-2B-Instruct Q4_K_M | Qwen/Qwen3-VL-2B-Instruct-GGUF | 52d6c8ffea26cc873ac5ad116f8631268d7eb503 | Qwen3VL-2B-Instruct-Q4_K_M.gguf | 1107409952 | 089d75c52f4b7ffc56ba998ffc50aae89fcafc755f9e7208aacca281dca6c2ae | 0.40 | 2080 | 0.103 | 0.121 | 0.066 | 0 (1, 0, 0) |
| Qwen3-1.7B Q8_0 | Qwen/Qwen3-1.7B-GGUF | 90862c4b9d2787eaed51d12237eafdfe7c5f6077 | Qwen3-1.7B-Q8_0.gguf | 1834426016 | 061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a | 1.66 | 2583 | 0.185 | 0.222 | 0.116 | 0 (0, 0, 0) |
| Qwen3-4B Q4_K_M | Qwen/Qwen3-4B-GGUF | bc640142c66e1fdd12af0bd68f40445458f3869b | Qwen3-4B-Q4_K_M.gguf | 2497280256 | 7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5 | 1.45 | 3483 | 0.225 | 0.283 | 0.153 | 0 (0, 0, 0) |
| Qwen3-VL-4B-Instruct Q4_K_M | Qwen/Qwen3-VL-4B-Instruct-GGUF | 1cd86afb9a95c410a6038ab3b40d8b578c892266 | Qwen3VL-4B-Instruct-Q4_K_M.gguf | 2497281664 | 66358cb18bb6b3b1b6675aa412c7a88ef01d228f481184d13668e5201c730a0a | 1.46 | 3553 | 0.182 | 0.218 | 0.117 | 0 (0, 0, 0) |
| Qwen3-8B Q4_K_M | Qwen/Qwen3-8B-GGUF | 7c41481f57cb95916b40956ab2f0b139b296d974 | Qwen3-8B-Q4_K_M.gguf | 5027783488 | d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785 | 3.12 | 5904 | 0.321 | 0.362 | 0.196 | 0 (0, 0, 0) |

No sanitizer rejections and no request errors for any model. "Flagged" is the
median over the three runs, with each run's count in brackets.

Candidate notes:

- Qwen publishes no Q4_K_M for Qwen3-1.7B, only Q8_0, so that file was benched.
- The two "newest small" slots went to Qwen3-VL-2B/4B-Instruct (2025-10-31), the
  newest small models Qwen publishes as GGUF. Qwen3.5 0.8B/2B/4B/9B (2026-02) are
  newer and Apache-2.0, but Qwen ships no GGUF for them, so they fall outside the
  "publisher's own GGUF" rule. The VL files are loaded text-only (no `mmproj`).

### Model ids passed to the bench

| Model | `--llm-model` id |
|---|---|
| oMLX baseline | `Qwen3.8-27B-MLX-8bit` |
| Qwen3-VL-2B-Instruct Q4_K_M | `qwen3-vl-2b-instruct-q4_k_m` |
| Qwen3-1.7B Q8_0 | `qwen3-1.7b-q8_0` |
| Qwen3-4B Q4_K_M | `qwen3-4b-q4_k_m` |
| Qwen3-VL-4B-Instruct Q4_K_M | `qwen3-vl-4b-instruct-q4_k_m` |
| Qwen3-8B Q4_K_M | `qwen3-8b-q4_k_m` |

llama-server serves whichever model it loaded and ignores the request's
`model` field, but BugVoice does not: `PromptBuilder` appends `/no_think` to
the user message, and sets `disableThinking` (which sends
`chat_template_kwargs.enable_thinking = false`), only when the id contains
"qwen", case-insensitive (`PromptBuilder.swift:80`). Every id above contains
"qwen", so every run had thinking off. **Phase 3's catalog ids must contain
"qwen" the same way** (use the ids above); an id without it would run the
Qwen3 models with thinking on and these timings would not hold.

### Qwen3-4B-Instruct-2507 (follow-up check)

Qwen publishes no official GGUF for Qwen3-4B-Instruct-2507: there is no
`Qwen/Qwen3-4B-Instruct-2507-GGUF` repo (the Hugging Face API returns not
found), and `Qwen/Qwen3-4B-Instruct-2507` (Apache-2.0, revision
`cdbee75f17c01a7cc42f958dc650907174af0554`) has safetensors only, plus an FP8
variant. It was not benched, and Qwen3-4B stays the Medium pick.

### Gate

Spec: median 10–20 word cleanup at most 1.0 s (Small), 1.5 s (Medium), 2.5 s
(Large), and fidelity failures no more than oMLX's (0).

| Tier | Limit | Pick | Median s | Flagged | Verdict |
|---|---|---|---|---|---|
| Small | 1.0 s | Qwen3-VL-2B-Instruct Q4_K_M | 0.103 | 0 | pass |
| Medium | 1.5 s | Qwen3-4B Q4_K_M | 0.225 | 0 | pass |
| Large | 2.5 s | Qwen3-8B Q4_K_M | 0.321 | 0 | pass |

Every candidate passes on speed by a wide margin (all at least 4x faster than the
oMLX 27B baseline) and none exceeds oMLX's flagged count. The picks therefore
rest on what the fixed sentences showed (only these 12 bench sentences were
read back with `--show-text`; no history text was printed):

- Small: Qwen3-VL-2B is the smallest and fastest and does clean English
  (capitals, punctuation, fillers). It left two Vietnamese sentences uncleaned
  and changed "mười giờ" to "10 giờ" and "update" to "cập nhật". It had one
  flagged entry in run 1 of 3 (median 0). Qwen3-1.7B was not picked: it passed
  but barely cleaned anything (most sentences came back lowercase with fillers).
- Medium: Qwen3-4B kept the Vietnamese meaning intact. Qwen3-VL-4B was faster
  (0.182 s) but rewrote "cuộc họp" (meeting) as "Hội nghị" (conference) and
  dropped words, which FidelityCheck does not catch. Qwen3-4B left four of five
  English sentences without a leading capital. Owner call: swap to VL-4B if
  English capitalisation matters more than that Vietnamese drift.
- Large: Qwen3-8B, the best-cleaned output overall, but it dropped "hôm nay"
  (today) from one Vietnamese sentence along with the filler.

FidelityCheck guards numbers, names and similar tokens; it does not catch word
substitutions or dropped ordinary words. A gate pass here is a speed and
token-fidelity pass, not a quality guarantee.

### Fit rule

`memoryShare` = **0.30**: "Fits this Mac" picks the largest model whose
`memoryNeed` is at most 0.30 × `physicalMemory`. Memory figures for the catalog,
from measured RSS rounded up: Small 2.1 GB, Medium 3.5 GB, Large 6.0 GB.
That gives 8 GB Macs Small (2.4 GB budget), 16 and 18 GB Macs Medium (4.8 /
5.4 GB), and 24 GB and up Large (7.2 GB+), leaving at least 70% of memory for
macOS, the speech model and the owner's apps.

## Phase 3 — Built-in model (Tasks 9 to 14, 2026-11-06)

The bench itself is the "Phase 2 — Bench" section above (Task 8: commits
94f7789 `feat(bench): cleanup bench mode`, 56af1f5 `fix(bench): cleanup bench
prints n/a for empty sets and fails when ev...`, a02192a `docs: built-in model
bench`, 0984e87 `docs: bench follow-up`). All three tiers passed the gate. Picks:
Small Qwen3-VL-2B-Instruct Q4_K_M, Medium Qwen3-4B Q4_K_M, Large Qwen3-8B
Q4_K_M, with `memoryShare` 0.30. llama.cpp is pinned at `b11829` (the macOS
build ships as a `.tar.gz`). The owner still reviews the picks; the catalog
values are easy to change. Quality notes for that review: Small left two
Vietnamese sentences uncleaned, Medium leaves leading capitals off some English
sentences, and Large dropped "hôm nay" from one sentence. `FidelityCheck` does
not catch changed or dropped ordinary words.

- Task 9, built-in model catalog. 0b57361 `feat(core): built-in model catalog`.
  `BuiltInModel` and `BuiltInCatalog` hold the three tiers with pinned
  revision, SHA-256 and size, plus the fit rule that picks the largest model
  within 0.30 of physical memory. Model ids contain "qwen" so thinking stays
  off.
- Task 10, built-in engine in settings, resolver and readiness. 6c48485
  `feat(core): built-in engine in settings, resolver and readiness`. Adds
  `ModelEngine.builtIn`, `ModelPlan.builtIn`, the resolver case and the
  readiness case, and replaces the Task 2 no-op for `CleanupChoice.builtIn`.
- Task 11, download plan and verifier. 4725c7a `feat(core): built-in model
  download plan and verifier`; 2ef8489 `fix(app): verify download ranges and cap
  size`. Resumable HTTPS download with a pinned revision and SHA-256 check; a
  file that fails the hash is deleted. The fix checks the `Content-Range` start
  and total, caps the body at the model size, replaces the final file
  atomically, makes the URLSession injectable and removes temp directories.
- Task 12, bundled helper. 413e1b4 `build: bundle llama-server helper`.
  `Scripts/build-app.sh` fetches the pinned, hash-checked llama.cpp build and
  signs `llama-server` and its libraries with `Bugler Local Dev`. The helpers
  are signed without `--options runtime` because library validation rejects
  them without a Team ID.
- Task 13, built-in server. 85b503f `feat(app): built-in model server`.
  `BuiltInServerController` starts `llama-server` on 127.0.0.1 only with a
  random per-launch key, stops it after idle and on quit, and cleans up stale
  processes. The key stays on the command line (`--api-key`), which only the
  same user or root can read.
- Task 14, built-in models in onboarding and Settings. 0b1f2b2 `feat(app):
  built-in models in onboarding and settings`; 390a29a `fix(app): built-in load
  failures and late onboarding downloads`. Step 5 offers the built-in model
  with download, cancel and resume; Settings has a Built-in section with
  delete; readiness shows "<name>, built in". The fix makes a server start
  failure show in readiness (amber) and stops a late onboarding download from
  overriding a later Settings choice.

## Final fix wave (2026-11-06)

Fixes from the whole-branch review plus the deferred minors below. Commits:
14cde51 `fix(core): model load outside the cleanup limit, built-in kept to
cleanup`, a635f04 `fix(app): warm the built-in model at key-down, clearer
start failures`, 689da01 `build: fail when llama-server links a library not in
Helpers`.

- Cold start: recording start now loads the built-in model while the user
  speaks, and the time spent waiting for the model is no longer counted
  against the cleanup timeout (`TextModel.prepare()`, awaited before
  `withTimeout`). The server's own 60-second start limit still bounds the wait.
- Ask AI and Transforms do not use built-in models. With a built-in model for
  Dictation, they show "Built-in models clean dictation only. Choose a model
  for Ask and Transforms in Settings → Models." Notes dictation cleanup still
  uses the built-in model (it resolves through `plan(for: .notes)`, not
  `transformPlan`).
- A helper that cannot run, or quits within 3 seconds, reports "The built-in
  model did not start. If you opened BugVoice with Open Anyway, run the
  Terminal command from the Read Me (Way B) once."
- Switching Dictation and Notes away from built-in models stops the server.
- The idle stop waits while a cleanup request is in flight.
- `llama-server` runs with `--no-webui` (b11829 accepts it).
- Onboarding clears the Notes override for every cleanup choice.

## Owner checks (open)

Not run by the implementers. Record results here at hand-over. Every item is
open.

Onboarding and Try it:

- [ ] Fresh install path: with no `settings.json`, onboarding opens at step 1;
      Back, Skip and Skip setup behave as the mockup shows.
- [ ] Hotkey probe: step 2 shows "Key seen. It works." when the talk key is
      held, and the press does not dictate.
- [ ] Existing install path: an install with a `settings.json` never shows
      onboarding automatically and keeps its settings.
- [ ] Close and relaunch after closing onboarding does not reopen it.
- [ ] Run setup again: Settings > General reopens onboarding at step 1.
- [ ] Step 5: oMLX with a key, Test passes, Continue; a cloud key is saved and
      the privacy line shows.
- [ ] Try it: hold the talk key; text lands only in the box; the "It works" row
      shows times and model; Try again clears; long dictation wraps and scrolls.
- [ ] Try it isolation: with step 6 open, dictate into another app; it reaches
      History and Fix last paste, and the Try-it row does not change. Try-it
      dictation does not appear in History and is not the "Fix last paste"
      target.
- [ ] Try it while speech still downloads: the note shows the download percentage.
- [ ] Try it cleanup failure: the reason shows in the Try-it row.

Tour:

- [ ] All three entry points work: from onboarding finish, Settings > General,
      and the menu popover Tools > "Take the tour". Esc ends it, arrows move it,
      a narrow or hidden sidebar skips hidden stops, and it matches the mockup.
- [ ] The overlay swallows clicks to the main window; nothing starts a recording,
      opens the meeting window or pastes.

DMG and install:

- [ ] Run `Scripts/build-dmg.sh` (allow Automation if asked) and compare the
      window with mockup Part 1: window bounds, icon positions, Way A text not
      overlapping the Read Me icon, Retina sharpness, hidden `.background`.
      Not run in Task 15; the script drives Finder.
- [ ] Quarantined-download "Way A" walk: install the DMG from a browser
      download and follow Way A end to end. Not run in Task 15.
- [ ] Screenshots: capture `App/DMG/screenshots/not-opened.png` and
      `open-anyway.png`, rerun `Scripts/make-dmg-readme.sh`, commit.
- [ ] Update note: Settings > General shows the Way A and Way B text correctly.

Built-in model:

- [ ] Real Small download: cancel, resume, and the hash passes. Note the
      download speed; if it is slow, switch the downloader from byte-wise
      `AsyncBytes` to a `URLSessionDataDelegate`.
- [ ] Fresh install, step 5 with Small: cancel and resume work, Try it works,
      readiness shows "<name>, built in", and Delete flips the choice to Off.
- [ ] A server start failure shows amber in readiness.
- [ ] A late step 5 download after picking another engine in Settings does not
      override that choice.
- [ ] `lsof` shows the server listening on 127.0.0.1 only.
- [ ] A request to the server without the key gets 401.
- [ ] The server process exits on quit. After the idle period: set Unload after
      to 5 minutes, wait, confirm the process exits.
- [ ] Install from a browser-downloaded DMG with Way A only (Open Anyway, no
      Terminal command), then use the built-in model. If it does not start, the
      readiness card names Way B.
- [ ] First dictation after the server unloaded cleans the text (it is not
      pasted raw while the model loads).
- [ ] Switching Dictation from a built-in model to another engine stops the
      `llama-server` process.
- [ ] With a built-in model for Dictation, Ask AI and Transforms say to choose
      another model in Settings → Models.
- [ ] Review the three model picks and the catalog values (see Phase 3).

## Known follow-ups

Minor review findings deferred to the final fix wave. Ticked items were fixed
in that wave (see "Final fix wave"); open items remain.

- [x] Try-it text view lacks min/max size and horizontal resize settings, so
      long text may not wrap or scroll. Fixed in a635f04.
- [x] Closing the main window mid-tour leaves the tour index set; the tour
      reappears on reopen. Fixed in a635f04: closing the window ends the tour.
- [x] Speech step lacks the download size (spec: name, size, progress). Already
      shown: the model label reads "large-v3-turbo · 1.6 GB" (from
      `SpeechTab.whisperModels`); a custom model id has no known size.
- [ ] Duplicated cleanup-test block between `OnboardingCleanupStep` and
      `UseForCard.runTest`.
- [ ] Re-running onboarding adds a second local connection.
- [ ] Cloud Continue is allowed with an empty key.
- [ ] The `connection` getter writes `cloudIDs`.
- [ ] Field edits during a running cleanup test are not caught.
- [ ] `begin()` catch path does not reset `tryItRun` (harmless).
- [ ] The tour's on-screen set is a heuristic, not measured anchors; a clipped
      row gives a ring-less card. The card is not clamped at the bottom for low
      sidebar rows.
- [ ] The tour overlay swallows Tab and Return.
- [ ] `onChange(page)` ending the tour relies on same-update writes.
- [x] `presentOnboarding` sits between the `hotkeyProbe` doc comment and its
      property. Fixed in a635f04.
- [ ] `PlaceholderStep` has an unused `advance` parameter.
- [ ] The hotkey step's "Other choices" line is hard-coded.
- [ ] The step dots are off-centre and "Step N of 7" layout needs a GUI look.
- [ ] The probe cancels a running hold on the next input, not at the instant it
      is set. The talk hotkey still dictates normally during the tour, so the
      log's "never records" means tour actions only.
- [ ] `SettingsStore` doc comment should say an unreadable-but-present file
      counts as an existing user.
- [ ] Meetings-unchanged tests start only from a fresh install; add a
      connection-first test.
- [ ] `.appleIntelligence` and `.none` replace the dictation `ModelUse`
      wholesale and drop its other fields. (Both now clear the Notes override,
      14cde51.)
- [ ] No explicit legacy-encoding regression test for connection, cli and
      `appleIntelligence` engines.
- [ ] Missing RED evidence for Tasks 2 and 5 (`TryItResult`); code was written
      before the tests.
- [ ] No boundary test that 8 GB gives Small.
- [x] The Large summary should read "Qwen3 8B · best text, needs 24 GB+" (the
      fit rule recommends Large from about 21 GB). Fixed in 14cde51.
- [ ] Read Me HTML puts a paragraph and images inside an `<ol>` (cosmetic).
- [ ] `make-dmg-background.sh` runs `sips` before its `-s` check, so the
      friendly Chrome message never prints; `-s` passes on a stale file; the
      diskutil UDZO path skips zlib level 9.
- [ ] `fetch-llama-server.sh` unsafe-path check ignores symlink entries (hash is
      pinned, low risk); `CleanupBench` parsing is untested.
- [ ] The bench log says the Hugging Face API returned "not found" for
      Qwen3-4B-Instruct-2507-GGUF; it was HTTP 401 (same as a nonexistent repo).
- [x] `BuiltInDownloader`: a size mismatch on a resumed 206 kept the `.part`
      file, so retry looped on the same error. Fixed in 14cde51: it restarts
      from zero once.
- [x] `build-app.sh` hardcodes the dylib list; check every `@rpath`
      dependency of the helper exists in Helpers (`otool -L`) so a tag bump
      fails at build time. Fixed in 689da01 (the list stays; the check fails
      the build with the missing names).
- [x] `BuiltInServerController` `stop()` removed the pid file before the
      process exited. Fixed in a635f04: removed on exit.
- [x] `BuiltInServerController` shutdown polled `Process.isRunning` under
      `Thread.sleep`. Fixed in a635f04: polls `kill(pid, 0)`.
- [x] `BuiltInServerController` `cleanUpStale` delayed SIGKILL should skip
      when the pid is the running process. Fixed in a635f04.
- [x] A cancelled start (stop, shutdown, release) may be reported as a load
      failure (amber). Fixed in a635f04: a start BugVoice stops throws
      `CancellationError` and skips `onLoadResult`.

Accepted as is: same-size final model file returned without a hash check;
`build-app.sh:78` relies on the fetch script's last stdout line; no port retry
if the port is lost between probe and bind; a minimised setup window skips the
late apply; delete waits through the hash check; Readiness Download while
another download runs.
