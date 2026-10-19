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

## Device checks

| Check | Result | Evidence / reason |
|---|---|---|
| L1 Defaults | Not run | BugVoice GUI access was rejected by the computer-use provider before inspection. |
| L2 Orca English | Not run | BugVoice GUI access was rejected by the computer-use provider before dictation. |
| L3 Claude Vietnamese | Not run | BugVoice GUI access was rejected by the computer-use provider before dictation. |
| L4 Website rules | Not run | BugVoice GUI access was rejected by the computer-use provider before browser dictation. |
| L5 Popover switch | Not run | BugVoice GUI access was rejected by the computer-use provider before interaction. |
| L6 Shift language tap | Not run | BugVoice GUI access was rejected by the computer-use provider before interaction. |
| L7 Paste raw / Already raw | Not run | BugVoice GUI access was rejected by the computer-use provider before dictation. |
| L8 Redo in other language | Not run | BugVoice GUI access was rejected by the computer-use provider before dictation. |
| L9 Typed-key safety | Not run | BugVoice GUI access was rejected by the computer-use provider before interaction. |
| L10 Multiline safety | Not run | BugVoice GUI access was rejected by the computer-use provider before dictation. |
| L11 History replacement | Not run | BugVoice GUI access was rejected by the computer-use provider before inspection. |
| L12 Light/dark themes | Not run | BugVoice GUI access was rejected by the computer-use provider before inspection. |
