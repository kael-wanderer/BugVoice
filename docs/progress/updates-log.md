# Update check — execution log

2026-10-24. Ported from Bugler's `UpdateFeed.swift` / `UpdateWatcher` (and BugMind
Phase 474, which reads the same kind of feed).

## What it does

- Feed: `https://kael.io.vn/projects/bugvoice/latest.json`,
  `{"version":"0.1.0-build.306","release_url":"https://…"}`.
- `VoiceCore/UpdateFeed.swift`: one GET on the no-redirect session, 8 s timeout,
  16 KiB cap, version must be a plain SemVer-shaped string of at most 64
  characters, `release_url` kept only when `https`. Failures are classes
  (`not_found`, `server_error`, `timeout`, `malformed`, `transport`); no body or
  message reaches the screen or the log.
- The running build is compared as `CFBundleShortVersionString-build.CFBundleVersion`
  (`0.1.0-build.330`) with a SemVer comparator: builds order numerically, a
  version bump beats any build, and anything unparseable is never newer.
- `UpdateWatcher`: forced check at launch, then hourly wake with a one-day
  cooldown (a single 24-hour sleep stretches while the Mac sleeps). `found`
  reports every answer, so the menu row survives relaunches; `announce` runs
  once per version and only logs.
- Settings › General › Updates: Version, Check for updates (Checking… / Check
  again / Retry with the reason / Open <version>), and the switch
  `updateNotify` (default on, `settings.json`). Turning it off clears the menu
  row; turning it on checks at once.
- Menu popover: "BugVoice <version> is available" row with Open, while an offer
  stands. Opens the release page in the browser; nothing downloads or installs.

Not taken from Bugler: the Beta channel (the feed has no `beta` entry) and a
macOS notification (BugVoice has no UserNotifications path; a new one would add
a permission prompt).

## Tests

`Tests/VoiceCoreTests/UpdateFeedTests.swift` (feed version, SemVer, decode,
selection, watcher, setting). Full suite: **1,289 VoiceCore, 30 MCPKit, 114
BugVoiceMac**, all pass. `swift build` succeeds. No app launch: `run-dev-app.sh`
would restart the owner's running BugVoice.

## Device checks (owner)

1. Settings › General › Updates at build 330 against the live feed (306): note
   reads "Up to date. The newest release is 0.1.0-build.306.", button "Check again".
2. Publish a newer build to the feed (or lower `CFBundleVersion` in a dev build):
   the menu shows "BugVoice … is available"; Open lands on the release page.
3. Switch off: the menu row goes; relaunch shows none. Switch on: row returns.
4. Wi-Fi off, Check again: "could not reach the update feed", button "Retry".
5. Light and dark, at the larger text sizes: the card's row and toggle title fit.
