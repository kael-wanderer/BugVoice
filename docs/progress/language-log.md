# Language per app and fix last paste — execution log

Branch: `feat/language-fix-last` from `main`. Implemented 2026-10-19. No merge or push.

## Tasks and commits

| Task | Result | Commit | `swift test` counts (VoiceCore / MCPKit / BugVoiceMac) |
|---|---|---|---|
| 1. Language rules and resolver | Added tolerant per-app language settings, defaults, website matching, and resolver tests. Wrote the tests before implementation; the targeted test run failed to compile as expected. | `a41a97e` `feat(core): language per app rules and resolver` | 944 / 30 / 94 |
| 2. Language key gesture | Added Shift/Option mapping, tap detection during a recording, and the Auto → EN → VI cycler. Wrote failing mapper, gesture, and cycler tests first. | `d3a5892` `feat(core): language key taps while recording` | 1003 / 30 / 94 |
| 3. Prompts and pipeline language | Routed the resolved/forced language into transcription and cleanup prompts; added the mixed-language example and English-word preservation. Wrote failing tests first. | `7bdb2b5` `feat(core): dictation language from rules, keep English words` | 1013 / 30 / 94 |
| 4. Fix-last core | Added replacement safety decisions, shortcut defaults, and in-place history replacement. Wrote failing tests first. | `ecde596` `feat(core): fix last paste guard, shortcuts and history replace` | 1025 / 30 / 94 |
| 5. Language app UI | Added language settings and per-app rules, popover switch and badge, and language-aware HUD/key wiring. | `f4ab028` `feat(app): language per app, menu switch and language key` | 1025 / 30 / 94 |
| 6. Fix-last app wiring | Added marked synthetic paste/delete events, focus checks, Raw and other-language replacement, history updates, shortcuts, menu controls, and HUD messages. The new BugVoiceMac test failed to compile before the event helper existed, then passed. | `00f2294` `feat(app): paste raw and redo in other language` | 1025 / 30 / 95 |

The final `swift test` passed all 1,150 tests: 1,025 VoiceCore, 30 MCPKit, and 95 BugVoiceMac. `Scripts/build-app.sh` succeeded and signed `build/BugVoice.app` with `Bugler Local Dev`.

## Deviations and environment limits

- No lasting code or interface deviations from the plan. The implementation uses actor-isolated, `Sendable` paste callbacks to satisfy Swift 6 concurrency checking.
- GUI smoke checks could not run. `Scripts/run-dev-app.sh` launched the development app, but the computer-use provider explicitly rejected access to BugVoice before any device check. The owner’s `~/Library/Application Support/BugVoice` was backed up to `/private/tmp/bv-before-codex` and restored after the attempted launch; the dev data was kept separately in `/private/tmp/bv-language-dev-data`.
- No device check is marked passed. L1–L12 are all **not run** for the provider access reason above; automated tests and a build are not device evidence.

## Review and device checks (Claude, 2026-10-19)

Branch review found two bugs, fixed in `342d92e`:

- Paste raw compared against the transcript before Dictionary replacements and
  the Terminal trailing-period trim, so in Terminal (cleanup off) it re-added
  the period instead of saying "Already raw". The pipeline now records
  `DictationResult.uncleanedText` (what cleanup-off would paste) and Paste raw
  uses it (`uncleanedTextMatchesCleanupOffPaste`,
  `uncleanedTextKeepsReplacementsWithoutCleanup`).
- Language per app rows were keyed by position; removing a row could index past
  the end of the list. Rows are now keyed by kind and ID.

Polish after the device run: the Add app… button no longer stretches the full
width, and iTerm2 / Warp show their names when the app is not installed.

1,152 tests pass (1,027 VoiceCore / 30 MCPKit / 95 BugVoiceMac).

### How the checks ran

The Mac has no microphone that can hear a speech file played from its own
speaker, so a temporary, uncommitted hook swapped each recording for a
`say`-generated WAV (English: Ava; Vietnamese: Linh). The hotkey hold and Shift
taps were real `CGEvent`s through the hotkey tap; everything after the
recording (routing, transcription, cleanup, paste, replacement, history) ran
as shipped. The hook was removed and the library restored from a snapshot
(checksums matched). Test target: TextEdit on the second display.

Synthetic ⌃⌥ key events do not trigger the Carbon global shortcuts (⌃⌥B did
not open the window either), so ⌃⌥R / ⌃⌥L were exercised through the popover
buttons, which call the same methods.

The run was stopped after L6: during that dictation the owner was using Chrome,
which became frontmost, and the paste went there. Synthetic dictation must not
run while the owner is at the keyboard.

### Device checks

| Check | Result | Evidence |
|---|---|---|
| L1 Defaults | Pass | Settings › Speech lists the 9 defaults in order (Orca … chatgpt.com); the owner's settings file had no `appLanguages`. |
| L2 Orca English | Not run | Orca hosts the agent sessions; not dictated into. Resolver covered by `ruleLanguageReachesTranscriber`. |
| L3 Vietnamese keeps English words | Pass (forced VI via L6) | Linh clip → "Mình đang sửa cái module này, bạn kiểm tra lại API giúp mình nhé." `lang=vi`; module and API stayed English. Claude desktop itself not dictated into. |
| L4 Website rules | Not run | Needs a chatgpt.com tab; covered by `websiteBeatsApp`, `subdomainMatches`. |
| L5 Popover switch | Partial | Popover shows Auto · EN · VI under the tiles and Raw / Vietnamese in the Last dictation card (matches mockup screen 2). Switching to VI and the badge not driven. |
| L6 Shift language tap | Pass | Hold in TextEdit (Auto) with two Shift taps → `lang=vi`, recording not cancelled, text inserted. HUD captures not kept. |
| L7 Paste raw | Pass (popover) | Filler clip cleaned to "Please check the server and run the tests."; Raw replaced it in place with "Um so uh please check the module, no I mean the server, and um run the tests."; history `replacedBy: raw`. "Already raw" seen on a clip where raw equals cleaned. Terminal case covered by the new test. |
| L8 Redo in other language | Pass (popover) | HUD "Transcribing Vietnamese" → "Cleaning (Qwen)"; text replaced in place; history `language: vi`, `replacedBy: otherLanguage`. Flip back not driven. |
| L9 Typed-key safety | Pass | A key typed after the paste, then Raw: HUD "Copied — press ⌘V · text changed since the paste", document unchanged, clipboard held the raw text (owner's clipboard restored after). |
| L10 Multi-line safety | Not run | Covered by `multiLineIsCopied`. |
| L11 History | Pass | See L7 and L8 history lines; the popover's Last dictation showed the replacement. |
| L12 Light/dark | Dark only | Settings › Speech and the popover match the mockup in dark; light not checked. |

Owner to try with real speech: ⌃⌥R and ⌃⌥L from the keyboard, the VI switch
and its menu bar badge, Orca in English, Claude desktop in Vietnamese,
chatgpt.com in Chrome, and the light theme.
