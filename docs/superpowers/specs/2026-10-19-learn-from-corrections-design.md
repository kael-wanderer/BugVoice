# Learn from corrections

Date: 2026-10-19. Status: draft for owner review.
Mockup: `docs/design/proposal-corrections.html`.
Follows: `docs/propose-new-features.md` item 2, picked by the owner on
2026-10-19. The owner asked for the spec and mockup without a question round,
so every choice below is **my call** unless it restates an existing BugVoice
rule.

## Why

The owner's speech in English and Vietnamese is not always clear, so some
words come out wrong in the same way every time ("Kale" for "Kael", "bun"
for "bún", a colleague's name). The owner fixes them by hand and moves on,
and the next dictation makes the same mistake. The Dictionary would fix it
for good, but adding each word is a chore nobody does in the middle of
writing. BugVoice can see the fix: it knows what it pasted, and it can read
the field back a moment later.

## Goals

1. **Notice a fix.** After a paste, when the owner changes a pasted word
   ("Kale" to "Kael"), BugVoice notices it.
2. **Suggest, never assume.** The fix becomes a suggestion in Dictionary ›
   Words. Nothing is added until the owner clicks Add.
3. **Stay out of the way.** No popup while writing. A count in the menu bar
   popover and on the Dictionary page is the only signal.
4. **Both languages.** Vietnamese diacritic fixes ("ban" to "bạn") count as
   fixes.

## Non-goals

- Learning style or tone from rewrites (a rewritten sentence is not a
  misheard word).
- Fixes in terminals. A terminal's text cannot be read back reliably
  (Ghostty exposes nothing; Terminal exposes the whole scrollback).
- Fixes made after the owner leaves the field, or more than 60 seconds
  later.
- Watching anything other than BugVoice's own pastes.

## Anti-goals

- Adding a real word as a "heard as" replacement by itself, so that every
  future "cell" becomes "sell".
- Keeping the owner's text. Only the changed words are stored.
- Reading a secure field, or slowing typing down.

## What happens

1. **After a paste** (dictation outcome Inserted, not a command, not in a
   Terminal-style app, not secure), BugVoice records the pasted text and the
   field's text around the cursor at paste time: the last 40 characters
   before the paste and the first 40 after it (anchors).
2. **Watch:** every second for up to 60 seconds BugVoice reads the same
   field's value through Accessibility (0.25 s timeout). It finds the
   pasted region between the two anchors and keeps the latest version of it.
   The watch ends early when the focused element changes, the anchors can no
   longer be found (the message was sent, the field cleared), the value is
   over 100,000 characters, or a new dictation starts. The last version
   found before that point is the one used.
3. **Compare** the pasted text with that last version word by word (longest
   common subsequence over words, punctuation trimmed from word edges). Each
   run of changed words is a candidate: 1–3 pasted words replaced by 1–3 new
   words.
4. **Keep** a candidate only when it looks like a misheard word:
   - the two sides look alike: similarity of 0.5 or more after folding case
     and diacritics (normalized Levenshtein), or they are the same once
     diacritics are folded (a Vietnamese tone fix);
   - it is not only a case change at the start of a sentence, not only
     punctuation, and not a deletion or insertion (both sides non-empty);
   - the written side is at most 40 characters;
   - the whole edit is not a rewrite: at most 3 candidates in one paste, and
     at most 40% of the pasted words changed.
5. **Suggest:** each kept candidate becomes a suggestion "Kael — heard as
   Kale", or adds 1 to the count of an existing identical suggestion.
   A pair the owner dismissed is never suggested again. A pair already in
   the Dictionary (the word with that heard-as) is ignored.

## Accepting a suggestion

- **Add** puts the written side into Dictionary › Words (or finds the
  existing word) and, when **Replace every time** is on, adds the heard side
  as one of its "heard as" entries.
- **Replace every time** is on by default, except when the heard side is a
  real word in English or Vietnamese (`NSSpellChecker` finds no misspelling
  for it in either language); then it is off and the row says "“cell” is a
  real word — added as a spelling hint only". The owner can turn it on.
- **Dismiss** removes the suggestion and remembers the pair.
- **Add all** adds every pending suggestion with its current switch.

## Where it shows

- **Dictionary › Words:** a Suggestions card above the word list, newest
  first: written word, "heard as …", app, "2 times", the switch, Add,
  Dismiss (mockup screen 2). Hidden when empty.
- **Menu bar popover:** one line under Last dictation: "2 Dictionary
  suggestions" opening Dictionary › Words (mockup screen 1). Hidden when
  empty.
- **Sidebar:** the Dictionary item shows the count as a badge.
- No HUD message, no sound, no notification.

## Settings

Settings › Speech: **Learn from corrections** switch (on by default).
Footnote: "After a paste, BugVoice reads the field back for a minute. When
you fix a word, it suggests adding it to the Dictionary. Text stays on this
Mac; only the changed words are kept." Turning it off stops watching and
keeps existing suggestions.

## Storage

`suggestions.json` in the BugVoice folder, tolerant decode:

```json
{ "schemaVersion": 1,
  "pending": [ { "id": "…", "written": "Kael", "heard": "Kale", "app": "Slack",
                 "count": 2, "lastSeen": "…", "replace": true } ],
  "dismissed": [ { "written": "great", "heard": "good" } ] }
```

- At most 50 pending (the oldest drop) and 500 dismissed.
- Added to `BackupPlan.rootFiles`.
- The text of the dictation is never written here; history already keeps
  what it keeps.

## Where the logic lives

VoiceCore (test first):

- `CorrectionRegion.find(value:before:after:)`: the edited region between
  the anchors, or nil.
- `CorrectionDiff.candidates(pasted:edited:)`: word alignment and the
  candidate runs.
- `CorrectionFilter.keep(_:pastedWordCount:)` with `similarity` and
  `foldedEqual` (case and diacritics).
- `SuggestionFile`: add or count, dismiss, accept, caps, tolerant decode;
  `SuggestionStore` actor.
- `DictionaryFile.accept(_ suggestion:)`: word plus optional heard-as.

App: `CorrectionWatcher` (the 1 s Accessibility poll, start and end rules),
the real-word check with `NSSpellChecker`, the Suggestions card, popover
line, sidebar badge, the setting.

## Limits

- 60 s watch, 1 s polls, one watch at a time.
- Anchors 40 characters each side; a field value over 100,000 characters is
  not watched.
- 1–3 words per side, 3 candidates per paste, 40% changed at most.

## UI copy

Plain English, no hedging, no emoji. Strings are in the mockup.

## Left to the builder

- The exact Levenshtein implementation and word tokenizer details beyond the
  rules above.
- How the poll is scheduled (timer or task loop).
- Card layout details within the mockup.

## Open for the owner

My calls; say if any is wrong:

1. Suggestions only, never added by themselves.
2. No popup; a count in the popover, sidebar and Dictionary.
3. Terminals are not watched.
4. Real words are added as spelling hints unless the owner turns on
   Replace every time.
5. One minute of watching, ending early when the field is left or cleared.
