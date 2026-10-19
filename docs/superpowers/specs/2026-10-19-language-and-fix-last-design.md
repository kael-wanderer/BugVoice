# Language per app and fix last paste

Date: 2026-10-19. Status: draft for owner review.
Mockup: `docs/design/proposal-language.html`.
Follows: `docs/propose-new-features.md` items 4 (Language per app) and 8
(Paste raw instead), picked by the owner on 2026-10-19.

## Why

The owner dictates in three places:

- **Coding agents** (Orca, Ghostty, VS Code terminal): English only.
- **Claude desktop and ChatGPT web**: Vietnamese.
- **Notion and Obsidian** (daily log, drafts of Facebook posts): both.
  English for work entries, Vietnamese for personal ones.

Their speech in both languages is sometimes unclear. Today speech-to-text
guesses the language on every dictation (Speech › Language is Auto), so a
mumbled English sentence can come out as Vietnamese words, or the other way
round, and cleanup then polishes the wrong text. When they speak Vietnamese
they keep some words in English (neuron, module, API); Vietnamese
transcription turns those into Vietnamese spellings (nơ-ron, mô-đun) and
the meaning gets lost.

The owner asked for every way to set the language: per app, before
speaking, and after the paste. Each one can be switched off in Settings.

## Goals

1. **Per-app language.** A list of apps and websites, each with English or
   Vietnamese. Apps not in the list use Auto.
2. **Language switch.** A sticky Auto / English / Vietnamese switch in the
   menu bar popover. English or Vietnamese applies everywhere until set back
   to Auto.
3. **Language key.** While recording, tapping Shift changes the language for
   that dictation only. The HUD shows the language.
4. **English words in Vietnamese.** Vietnamese and Auto dictations keep
   English words in English.
5. **Paste raw.** One shortcut replaces the last paste with what
   speech-to-text heard, without cleanup.
6. **Redo in the other language.** One shortcut transcribes the last
   recording again in the other language and replaces the last paste.

## Non-goals

- Languages other than English and Vietnamese for dictation (meetings
  already handle Spanish; dictation stays two languages).
- Translation. A Vietnamese dictation never becomes English or the reverse.
- Per-app language for meetings or uploads.
- Detecting language per sentence inside one dictation.
- Undo for a replacement (the shortcut can be pressed again; see below).

## Anti-goals

- A replacement that deletes text the user typed after the paste.
- A per-app rule that silently wins over a language the user picked on
  purpose (switch or key).
- The language key cancelling the recording (today any other key held
  while recording cancels it).
- English words coming out in Vietnamese spelling in a Vietnamese
  dictation because of this feature's hint.

## Which language a dictation uses

From strongest to weakest:

1. **Language key** taps during this recording.
2. **Language switch** set to English or Vietnamese.
3. **Per-app list**, when the switch is Auto: first match on the website
   (browser page address, matched like the style website rules: host equal
   or a subdomain), then on the app's bundle ID. The VS Code / Cursor
   terminal panel is matched as its own entry, "VS Code terminal", so the
   editor itself can stay Auto.
4. **Auto**: speech-to-text detects it, as today.

The language switch and the existing Settings › Speech › Language picker are
the same setting (`speech.language`); the popover is a second place to
change it.

## Per-app list

Settings › Speech gains a **Language per app** card (mockup, screen 1).

- Rows: app icon and name (or website host), language picker
  (English / Vietnamese), remove button.
- **Add app…** lists running apps plus a file panel for `/Applications`.
  **Add website…** takes a host such as `chatgpt.com`.
- Defaults on first launch with this build (my call, from the owner's
  answers):

  | Entry | Language |
  |---|---|
  | Orca (`com.stablyai.orca`) | English |
  | Ghostty, Terminal, iTerm2, Warp | English |
  | VS Code terminal, Cursor terminal | English |
  | Claude (`com.anthropic.claudefordesktop`) | Vietnamese |
  | `chatgpt.com` | Vietnamese |

  The defaults are written into settings once, so the owner can edit or
  remove each one. Notion and Obsidian are not in the list (Auto).
- The card notes: "Apps not listed use Auto. The language switch overrides
  this list."
- Settings stores `speech.appLanguages`: list of `{ kind: app|website|terminalPanel,
  id, language }`. Unknown entries are dropped on load one by one, like
  style overrides.

## Language switch (popover)

- A segmented control **Auto · EN · VI** under the popover's action
  tiles (mockup, screen 2). Today the language is two clicks away in
  Dictation options › Language; that submenu stays.
- Shown when Settings › Speech › **Show language switch in menu** is on
  (default on).
- While the switch is EN or VI, the menu bar icon shows a small `EN` / `VI`
  badge so a forgotten setting is visible (my call).

## Language key

- Setting: Settings › Speech › **Language key while recording**: Off,
  Shift (default), Option.
- Only taps count, and only while a recording is running (hold or hands
  free). A tap is the key going down and up with no other key between.
- Each tap moves to the next language: Auto → EN → VI → Auto. The first tap
  starts from the language the dictation would use without the key
  (per-app or switch), so in Orca (English) the first tap gives VI.
- The HUD's listening pill shows the language at all times: `Auto`, `EN`
  or `VI`, and flashes once when a tap changes it (mockup, screen 3).
- The language key does not cancel the recording. Any other key still
  cancels a held recording, as today.
- The chosen language applies to this dictation only; the next one starts
  again from the rules above.
- Holding Shift before pressing the hotkey still does not start a
  recording (chord rule unchanged).

## English words in Vietnamese

Two hints, both on by default, one setting: Settings › Speech › **Keep
English words in Vietnamese** (default on).

1. **Speech-to-text hint.** For Vietnamese dictations with WhisperKit
   (language set by key, switch or per-app), a short mixed example sentence
   goes first in the prompt, before the Dictionary words:
   "Mình đang sửa cái module này, check lại API với neuron layer nhé."
   Whisper copies the style of its prompt, so English words stay English
   more often. English and Auto dictations get no example: in Auto the
   prompt comes before Whisper picks the language, and a Vietnamese example
   would pull English speech towards Vietnamese. The prompt keeps its
   existing token budget; Dictionary words are cut first if it is full,
   never the example (my call).
2. **Cleanup rule.** Added to the cleanup system prompt for Vietnamese and
   Auto dictations: "Keep words the speaker said in English in English.
   Never rewrite them in Vietnamese spelling (nơ-ron, mô-đun)."

The Dictionary (already sent to both speech-to-text and cleanup) stays the
way to pin specific words; the card under the setting says "Add words you
always say in English to the Dictionary."

When the dictation language is known (key, switch or per-app), cleanup is
also told it: "The speaker spoke English." / "… Vietnamese."

## Fix last paste

Two new global shortcuts in Settings › Shortcuts, next to Paste last
(⌃⌥V), same letter rules as the existing ones:

| Shortcut | Default | Does |
|---|---|---|
| Paste raw | ⌃⌥R | Replaces the last paste with the raw transcript (no cleanup). |
| Redo in other language | ⌃⌥L | Transcribes `last.wav` again in the other language, cleans it with the same style, replaces the last paste. |

Both also appear in the popover's Last dictation card as **Raw** and
**Vietnamese** / **English** (the other language), next to Copy and Retry
(mockup, screen 2). Retry keeps its current behavior (runs `last.wav` again
and pastes at the cursor without replacing).

**Other language.** The language the last dictation came out in (from the
transcript's detected or forced language): English becomes Vietnamese,
anything else (Vietnamese, or a wrong guess such as Chinese) becomes
English. Pressing ⌃⌥L again flips back.

**Replacing.** BugVoice remembers the last insertion: the inserted text, the
app's process, the focused element, and the time. A replacement:

1. Deletes the inserted text by sending one Backspace per character
   (grapheme cluster) of the inserted text, then pastes the new text
   through the existing paste path (secure-field check included).
2. Runs only when all of these hold:
   - the same app is frontmost and the same element has focus;
   - no key was typed since the paste (the hotkey event tap already sees
     key-downs; BugVoice's own shortcuts and modifier keys do not count);
   - the paste was less than 2 minutes ago;
   - the last dictation was inserted at the cursor (not into a BugVoice
     note, not copied from a secure field);
   - the inserted text has no line break and at most 500 characters.
     Terminal coding agents such as Claude Code collapse a long or
     multi-line paste into one "[Pasted text]" block that a single
     Backspace removes, so counted Backspaces would go on to delete the
     user's own text.
3. Otherwise nothing is deleted: the new text is copied to the clipboard
   and the HUD says "Copied — press ⌘V" with the detail "text changed since
   the paste".
4. After a replacement the remembered insertion becomes the new text, so
   ⌃⌥R then ⌃⌥L, or ⌃⌥L twice, each replace the previous result.
5. A note insertion (dictation into the BugVoice editor) is replaced inside
   the note through the editor, under the same "no typing since" rule (my
   call: same behavior, no keystrokes needed there).

**When there is nothing to fix:** no last dictation, `last.wav` missing
(⌃⌥L), or a dictation is running: the HUD shows "Nothing to fix" for 1.2 s.

**Paste raw when cleanup was off** (Terminal style by default): raw and
cleaned text are the same; the HUD says "Already raw".

**History.** A replacement updates the last history entry: `inserted` becomes
the new text, and a `replacedBy` field records `raw` or `otherLanguage` (my
call). Paste last then pastes the replacement.

**HUD.** "Replaced with raw text" or "Replaced — Vietnamese" / "Replaced —
English" with word count, 1.2 s (mockup, screen 3).

## Where the logic lives

VoiceCore (Foundation only, test first):

- `LanguageResolver`: settings, focus snapshot, key override → language.
  The precedence above, website before app, terminal panel entry.
- `AppLanguageRule` model and its tolerant decoding; first-launch defaults.
- `LanguageKeyCycler`: start language and taps → language.
- `KeyEventMapper` / `HoldGestureDetector`: a language key tap while
  recording is its own input and does not cancel.
- `PromptBuilder`: the cleanup rule and "the speaker spoke …" line.
- Speech prompt assembly: example sentence first, then Dictionary words,
  within the budget.
- `ReplacementGuard`: last insertion record plus events → replace or copy.
- History entry update for a replacement.

App side: the popover switch and badge, the Settings cards, HUD language
label, sending Backspaces, re-running `last.wav` through the pipeline with a
forced language.

## UI copy

Plain English, no hedging, no emoji. Strings are in the mockup.

## Left to the builder

- Backspace pacing (send all at once or in small batches) as long as long
  replacements stay under about 300 ms for 500 characters.
- How Add app… lists apps.
- Exact badge drawing on the menu bar icon.

## Open for the owner

My calls; say if any is wrong:

1. Default per-app entries in the table above.
2. Menu bar badge while the switch is EN or VI.
3. Shift as the default language key; Auto → EN → VI cycle.
4. ⌃⌥R and ⌃⌥L as the default shortcuts.
5. Replacement refuses (copies instead) if anything was typed since the
   paste or after 2 minutes.
