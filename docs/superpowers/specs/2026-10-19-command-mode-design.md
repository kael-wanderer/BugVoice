# Command mode

Date: 2026-10-19. Status: draft for owner review.
Mockup: `docs/design/proposal-command.html`.
Follows: `docs/propose-new-features.md` item 1, picked by the owner on
2026-10-19. The owner skipped the question round, so every choice below is
**my call** unless it restates an existing BugVoice rule.

## Why

Dictation only adds text. To change text already written (fix a draft
Facebook post in Notion, make a Slack reply more polite, translate a
paragraph for ChatGPT) the owner has to copy it into a chat, ask, and paste
the answer back. Command mode does that in place: select the text, hold a
key, say what to do, release. The selection is replaced.

## Goals

1. **Rewrite a selection by voice.** Select text in any app, hold the
   command key, speak an instruction in English or Vietnamese ("make this
   more formal", "dịch sang tiếng Anh", "turn this into bullet points"),
   release. The text model rewrites the selection and BugVoice pastes the
   result over it.
2. **Write new text by voice.** With nothing selected, the instruction is a
   request ("write a short reply saying I'll join at three") and the result
   is pasted at the cursor.
3. **Put the original back.** Every command can be undone with the app's own
   ⌘Z, and from BugVoice with Paste raw (⌃⌥R), which for a command means
   "put the original back".
4. **Same safety as dictation.** Never into a secure field, never off the Mac
   unless the user configured a remote text model.

## Non-goals

- A command palette, saved commands or a chat window. The instruction is
  spoken each time.
- Acting on the app (clicking, sending, running commands). Command mode only
  produces text.
- Reading text that is not selected (the whole document, the screen).
- A preview step before the paste. The replacement is undoable instead
  (decided to keep the flow one gesture; revisit if wrong results are
  common).
- Commands inside BugVoice's own note editor: its AI bar already covers
  this.

## Anti-goals

- Pasting a rewrite over a selection the user changed while the model was
  working.
- Model chatter in the result ("Sure! Here is the formal version: …").
- A command that cannot be taken back.
- Losing the user's clipboard because of the selection fallback.

## The gesture

- **Command key** (Settings › General, under Hotkey): Right Option (default),
  Right Command, Off. The list leaves out whichever key is the dictation
  hotkey. Hold to talk, release to run, exactly like the dictation hotkey;
  no hands-free double tap.
- Holding the command key while another modifier is down does not start
  (same chord rule as the hotkey), so Right Option still works for typing
  special characters with another key.
- The language key (Shift tap) and per-app language rules apply to the
  spoken instruction the same way as to dictation.
- Escape while the model is working cancels the command; nothing is pasted.

## What happens

1. **On press:** BugVoice reads the focus as dictation does and captures the
   selection:
   - First through Accessibility (`FocusSnapshot.selectedText`).
   - If Accessibility gives no selection (terminals, many Electron apps),
     it posts ⌘C (marked as BugVoice's own event), waits up to 300 ms for the
     clipboard to change, takes the text, and puts the previous clipboard
     back. If the clipboard does not change, there is no selection.
   - A secure field: the HUD says "Secure field — command not run" and the
     recording does not start.
2. **While holding:** the HUD shows a command pill: "Command" plus the
   selection size ("142 characters") or "New text" when nothing is selected,
   the app name, and the language label (mockup, screen 1).
3. **On release:** the instruction is transcribed with the dictation
   transcriber (no Dictionary replacements on the instruction; Dictionary
   words still go to the model as spellings).
4. **Rewrite:** one text model request (the Dictation cleanup model from
   Settings › Models) with:
   - System: "You edit text for the user. Apply the instruction to the text
     inside <text> tags. Output only the resulting text: no preamble, no
     quotes, no tags, no explanation. Keep the text's language unless the
     instruction asks to translate. Keep names, code, paths, numbers and
     Markdown formatting unless the instruction says otherwise." Plus the
     style rules of the app's style as context, the keep-English-words rule
     when it applies, and the Dictionary spellings.
   - User: "<instruction>…</instruction>\n<text>…</text>". With no
     selection: "<instruction>…</instruction>" and the system prompt's
     "Write the text the instruction asks for" variant, with the text before
     the cursor (500 characters) as context.
   - Timeout: 30 s (a rewrite is longer than a cleanup). The HUD shows
     "Rewriting (model)" with the app name.
5. **Result check:** the output goes through the existing sanitizer (think
   blocks, tags, empty), plus: a leading line ending in ":" that announces
   the answer ("Here is the formal version:") is dropped; surrounding quotes
   are dropped when the selection had none. An output longer than 4 × the
   selection + 2,000 characters is rejected ("The model's answer was too
   long").
6. **Paste:**
   - BugVoice re-reads the focus. If the same app and element are focused
     and, when Accessibility could read it, the selection is unchanged, it
     pastes the result through the existing paste path. Pasting over a
     selection replaces it in every normal text field, so no Backspaces are
     sent.
   - If the focus or selection changed, or the app is in the Terminal style
     (pasting in a terminal inserts at the prompt instead of replacing), the
     result is copied and the HUD says "Copied — press ⌘V" with the reason.
7. **Done:** HUD "Rewritten · ⌘Z to undo" (with selection) or "Written"
   (new text), word count, 1.2 s.

## Limits

- Selection up to 8,000 characters. Longer: HUD "Selection too long —
  8,000 characters at most", nothing runs.
- No text model configured (provider None): HUD "Command mode needs a text
  model — choose one in Settings › Models".
- Model error or timeout: HUD "Command failed — model unavailable", nothing
  pasted, the selection stays.

## Put the original back

- A command is the last dictation for Paste last, Paste raw and the
  popover's Last dictation card. The card reads "Last command · Notion ·
  “make this more formal”" with **Copy** and **Original** (mockup, screen 3).
- Paste raw (⌃⌥R) and **Original** after a command put the original
  selection back: same replacement guard as fix-last (same field, nothing
  typed since, under 2 minutes), but because a rewrite is often multi-line,
  for a command the guard selects the pasted text instead of sending
  Backspaces: Shift+Left once per character of the result. If the result
  has more than 2,000 characters, or the guard refuses, the original is
  copied ("Copied — press ⌘V").
- Redo in the other language (⌃⌥L) does nothing after a command ("Nothing
  to fix").

## History and insights

- A command is a history entry with `command` set to the instruction text,
  `raw` = the original selection (empty for new text), `inserted` = the
  result. The Dictation list shows it with a **Command** tag and the
  instruction above the result (mockup, screen 4).
- Commands do not count toward words dictated in Insights.
- Secure-field and cancelled commands are not recorded.

## Settings

Settings › General:

- **Command key** picker (Right Option / Right Command / Off).
- Footnote: "Select text, hold the command key and say what to change.
  With nothing selected, say what to write."

Settings › Shortcuts gains a fixed row "Command: hold Right Option".

`settings.json`: `commandKey` (`rightOption`, `rightCommand`, `off`),
tolerant decode, default `rightOption`. If the stored command key equals the
dictation hotkey, the command key is treated as Off.

## Where the logic lives

VoiceCore (test first):

- `CommandKey` setting and the conflict rule.
- `KeyEventMapper` / a second `HoldGestureDetector` instance for the command
  key (hold only).
- `CommandPrompt`: system and user prompt for rewrite and write-new.
- `CommandOutputSanitizer`: the extra result checks.
- `CommandPipeline`: transcribe instruction → prompt → model → sanitize →
  decision (paste / copy with reason), with fakes like `DictationPipeline`'s
  tests.
- `ReplacementGuard` extension: select-back count for a command result.
- `HistoryEntry.command`.

App: selection capture with the ⌘C fallback and clipboard restore, HUD
states, the paste/copy decision with a fresh focus read, Escape to cancel,
popover card, history tag, settings rows.

## UI copy

Plain English, no hedging, no emoji. Strings are in the mockup.

## Left to the builder

- How the ⌘C fallback waits for the clipboard (poll interval).
- Shift+Left pacing for Original (same batching as Backspaces).
- Exact HUD layout within the existing pill.

## Open for the owner

My calls; say if any is wrong:

1. Right Option as the command key, hold only.
2. No selection writes new text at the cursor.
3. No preview; ⌘Z or Original undoes.
4. Terminal apps get the result copied, not pasted.
5. The dictation cleanup model runs commands, with a 30 s timeout.
6. 8,000-character selection limit.
