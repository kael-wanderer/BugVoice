# Shortcuts support (App Intents)

Date: 2026-10-19. Status: draft for owner review.
Mockup: `docs/design/proposal-shortcuts.html`.
Follows: `docs/propose-new-features.md` item 6, picked by the owner on
2026-10-19. The owner asked for the spec and mockup without a question round,
so every choice below is **my call** unless it restates an existing BugVoice
rule.

## Why

BugVoice already does the useful pieces (record meetings, transcribe files,
clean and rewrite text, keep notes and action items), but only from its own
windows and the MCP server. The Shortcuts app is how macOS chains these
things: "transcribe the voice memo I just saved, tidy it, put it in a note",
a meeting started from a Focus or a calendar automation, a menu bar button
that rewrites the clipboard. App Intents expose BugVoice actions there, in
Spotlight and to Siri, natively and offline, with no new dependency.

## Goals

1. Six BugVoice actions in the Shortcuts app.
2. Three of them also as App Shortcuts (Spotlight and Siri phrases, no setup).
3. Every action runs while BugVoice stays in the menu bar; none opens a
   window unless it says so.
4. Same rules as the rest of BugVoice: local unless the owner configured a
   remote model or server, never into a secure field.

## Non-goals

- Dictation by Shortcuts (hold-to-talk is a keyboard gesture).
- Editing or deleting notes and meetings, folder management.
- Widgets, Control Center controls, Focus filters.
- iOS. BugVoice is macOS only.

## Anti-goals

- An action that silently does nothing: every failure is a Shortcuts error
  with a plain sentence.
- Breaking the build on a Mac without Xcode: the metadata step is skipped
  with a warning, the app still builds (without Shortcuts actions).

## The actions

| Action | Parameters | Result | Notes |
|---|---|---|---|
| **Start meeting recording** | Title (text, optional) | Meeting title | Same as the menu bar's Start meeting. Error when a meeting is already recording: "A meeting is already recording." |
| **Stop meeting recording** | none | Meeting title | Error when none: "No meeting is recording." Transcription continues as usual after stop. |
| **Transcribe audio file** | File (audio), Language (Auto / English / Vietnamese, default Auto), Wait for transcript (default on) | Transcript text, or the meeting title when not waiting | Goes through Upload, so the recording becomes a meeting like any upload. Waiting reports progress and stops waiting after 30 minutes with an error that says the transcript will keep going in BugVoice. Same file types and size limits as Upload. |
| **Rewrite text** | Text, Instruction (text) | Rewritten text | The command mode rewrite (`CommandPrompt` + `CommandOutput.sanitize`) with the Dictation cleanup model, 30 s timeout. Errors: "Command mode needs a text model — choose one in Settings › Models", "Command failed — model unavailable", "The model's answer was too long". Over 8,000 characters: "Text too long — 8,000 characters at most". |
| **New note** | Text, Title (optional), Folder (optional, by name) | Note title | Creates a Scratchpad note like MCP `create_note`. Unknown folder: "No folder named “Wrok”." (the name given). |
| **Get open action items** | Meeting (optional, by title), Limit (default 50) | List of text ("Send the build to QA (Kael) — Weekly mobile sync") | From the Action items board, open items only, newest meeting first. |

App Shortcuts (Spotlight and Siri, available right after install):

- "Start a meeting in BugVoice" / "Start recording a meeting in BugVoice"
- "Stop the meeting in BugVoice"
- "New BugVoice note"

Action descriptions in the Shortcuts library are in the mockup (screen 1).

## How it is built

- Intents live in the app target (`Sources/BugVoice/Intents/`), one file per
  intent plus `BugVoiceShortcuts.swift` (`AppShortcutsProvider`). They call
  the same `AppModel` functions as the menu bar and MCP; no logic is
  duplicated in the intents.
- `perform()` is `@MainActor`; it waits for `AppModel` bootstrap when
  BugVoice was just launched by Shortcuts (up to 10 s, else "BugVoice is
  still starting. Try again in a moment.").
- Pure parts in VoiceCore (test first): the parameter checks and result text
  (`ShortcutsActions`: language mapping, folder lookup by name, the action
  item line format, limit bounds 1–200, the 8,000-character rule, error
  copy).
- **Build:** `Scripts/build-app.sh` runs `xcrun appintentsmetadataprocessor`
  after `swift build`, with the module's source list and the
  `*.swiftconstvalues` files SwiftPM already emits
  (`.build/out/Intermediates.noindex/BugVoice.build/<config>/BugVoice-p.build/Objects-normal/arm64`),
  and copies `Metadata.appintents` into `Contents/Resources/`. Verified by a
  spike on 2026-10-19: the processor produced `extract.actionsdata` listing
  the intent and its App Shortcut phrase. When `xcrun` cannot find the
  processor (no Xcode), the script prints "Skipping Shortcuts metadata:
  Xcode not found" and continues.
- Discovery by the Shortcuts app after a build is a device check (S1); if
  macOS caches the old metadata, relaunching BugVoice re-registers it.

## Settings

No new setting. Settings › Shortcuts gets a footnote: "BugVoice actions are
also in the Shortcuts app: start and stop meetings, transcribe files,
rewrite text, new notes and open action items."

## UI copy

Plain English, no hedging, no emoji. Strings are in the mockup and the table
above.

## Left to the builder

- Intent type names and parameter summaries' exact wording within the mockup.
- How waiting for a transcript observes progress (polling the upload job or
  observing the model).
- The SF Symbols for App Shortcuts (mockup suggests `record.circle`,
  `stop.circle`, `note.text.badge.plus`).

## Open for the owner

My calls; say if any is wrong:

1. These six actions; dictation is not one of them.
2. Transcribe audio file creates a meeting (through Upload) and waits up to
   30 minutes by default.
3. Rewrite text reuses command mode's prompt and model.
4. Three App Shortcuts phrases: start meeting, stop meeting, new note.
5. No setting to turn the actions off.
