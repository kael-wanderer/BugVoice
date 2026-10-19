# Shortcuts support execution log

Date: 2026-10-19. Branch: `feat/shortcuts`.
Spec: `docs/superpowers/specs/2026-10-19-shortcuts-design.md`.
Plan: `docs/superpowers/plans/2026-10-19-shortcuts.md`.

## Built

1. VoiceCore parameter checks, exact error copy, language mapping, folder lookup,
   open action item formatting, title filtering and limits; failing tests first.
2. Text-only `CommandPipeline.rewrite`, using the Dictation model, command prompt,
   sanitizer and timeout; failing tests first.
3. Bootstrap bridge and per-upload language override (not persisted on relaunch).
4. Six menu-bar-only App Intents and three App Shortcuts with four phrases.
5. Bundle metadata extraction, Settings footnote and documentation.

Neither superpowers execution skill was installed; executed directly in task order.
No dependency added. No app, Shortcuts or synthetic input was run.

## Implementation choices

- `.command(.outputTooLong)` returns only the title, matching the spec and required
  test. The plan's blanket instruction to append `CommandFailure.detail` would add
  “nothing was changed” and conflict with that exact copy.
- The existing transcript exporter is named `MeetingExporter`, not the plan's
  `MeetingExport`.
- New note passes `NoteFrontMatter(folderID:tags: [])` directly: with no tags to
  normalize, sharing MCP's private labels helper would add no behavior.
- Transcription refreshes the meeting list when a ready job's manifest is not yet
  present: Upload marks ready before its final library reload.
- Copied temporary input remains available after success, timeout or cancellation
  so the existing upload recovery path can retain its source. Failed submission
  removes the temporary copy. System temporary-directory cleanup owns retention.

## Automated verification

- Task 1 red: `ShortcutsActions` not found; green: six parameterized/grouped
  test functions pass, then full suite passes.
- Task 2 red: `CommandPipeline` has no member `rewrite`; green: eight new rewrite
  tests and the full suite pass.
- Tasks 3 and 4: `swift build` and `swift test` exit 0.
- Full suite: 1,177 VoiceCore / 125 suites, 30 MCPKit / 2 suites,
  114 BugVoiceMac / 20 suites; **1,321 tests total**.
- `git diff --check` and `bash -n Scripts/build-app.sh` pass.

Task 5 Step 2, Xcode build: `Scripts/build-app.sh` exits 0. Relevant output:

```text
Starting appintentsmetadataprocessor export
Writing Metadata.appintents
Signed with: Bugler Local Dev
Built /Users/cong.bui/Kael/19-AppBuild/BugVoice/build/BugVoice.app
```

`ls build/BugVoice.app/Contents/Resources/Metadata.appintents`:

```text
extract.actionsdata
version.json
```

`codesign --verify --strict build/BugVoice.app` exits 0 with no output.

`BUGVOICE_XCODE_DEVELOPER=/nonexistent Scripts/build-app.sh` exits 0:

```text
Skipping Shortcuts metadata: Xcode not found
Signed with: Bugler Local Dev
Built /Users/cong.bui/Kael/19-AppBuild/BugVoice/build/BugVoice.app
```

The script's strict signature check also passes on this path. A normal build
is restored afterward so the owner has metadata for device checks.

Parsed `Metadata.appintents/extract.actionsdata` contains exactly these actions:

- `BugVoice.ActionItemsIntent`
- `BugVoice.NewNoteIntent`
- `BugVoice.RewriteTextIntent`
- `BugVoice.StartMeetingIntent`
- `BugVoice.StopMeetingIntent`
- `BugVoice.TranscribeFileIntent`

Its three App Shortcuts contain these four phrase templates
(`${applicationName}` resolves to BugVoice):

- `Start a meeting in ${applicationName}`
- `Start recording a meeting in ${applicationName}`
- `Stop the meeting in ${applicationName}`
- `New ${applicationName} note`

## Owner device checks — not run

- [ ] S1 After `Scripts/build-app.sh` and `Scripts/run-dev-app.sh`, the Shortcuts app lists the six BugVoice actions with the mockup's descriptions (relaunch BugVoice once if not).
- [ ] S2 Spotlight “start a meeting” shows the BugVoice App Shortcut; running it starts recording with BugVoice in the menu bar only.
- [ ] S3 Stop meeting recording returns the title; running it again errors “No meeting is recording.”
- [ ] S4 Start meeting recording with a title while one is recording errors “A meeting is already recording.”
- [ ] S5 Transcribe a short voice memo (Language Auto, Wait on) returns the transcript; the meeting appears in Meetings; Wait off returns at once.
- [ ] S6 Rewrite text “make it shorter” returns rewritten text; with no Dictation model it errors with the Settings › Models sentence.
- [ ] S7 New note with Folder “Wrok” errors “No folder named “Wrok”.”; with a real folder the note is in that folder.
- [ ] S8 Get open action items returns lines “item (owner) — meeting”, newest meeting first.
- [ ] S9 Quit BugVoice, run a BugVoice shortcut: BugVoice launches and the action runs (or the still-starting error after 10 s).
- [ ] S10 Settings › Shortcuts shows the footnote.

## Review fixes

- `build-app.sh` lists sources and const values with `find`, not `rg`, so a Mac with Xcode but without ripgrep still builds.
- Transcribe audio file: the temporary copy made when Shortcuts hands over data is removed once the upload job ends (ready, failed or cancelled).
- The Language choice is saved on the meeting, so a relaunch mid-upload or a later retranscribe keeps it.
