# Cleanup fidelity check

Date: 2026-10-24. Status: draft for owner review.
Mockup: `docs/design/proposal-fidelity.html`.
Follows: `docs/research/2026-10-24-feature-review.md` item 2 (Cleanup
fidelity protection), picked by the owner on 2026-10-24. The owner skipped
the design questions; every choice below not stated by the owner is marked
**(my call)**.

## Why

The text model rewrites what the owner said. Most of the time that is the
point: filler words go, punctuation arrives. Sometimes it changes a fact.
A dropped "not", a 15 that becomes 50, a path with one segment missing, or
`AppModel` turned into "app model" all paste cleanly and look right, so the
owner does not notice until later. The prompt already says "keep names,
code identifiers, file paths, and numbers exactly as spoken"
(`PromptBuilder.sharedRules`), but a small local model does not always obey.

Today the only guard after the model answers is `OutputSanitizer`: it
rejects empty output, output more than twice as long, and lost snippet
placeholders. *Paste raw* (⌃⌥R) fixes a bad paste by hand, but only if
the owner spots it.

## Goal

After cleanup and before paste, compare the raw transcript with the
cleaned text on four kinds of detail. When cleanup lost or invented one,
do not paste the cleaned text silently.

Success looks like:

1. A changed number, negation, path or identifier never pastes without a
   visible warning.
2. On the owner's real dictation history, fewer than 2% of accepted
   cleanups are flagged (false alarms). Measured before release, see
   *Evaluation*.
3. The check adds under 5 ms to a dictation.

## Non-goals

- Judging meaning in general. A model that rewrites tone, reorders a
  sentence or drops an adjective is not caught. Only the four detail kinds
  below are checked.
- A second model call to verify the first. Adds latency and can be wrong in
  the same way.
- Command mode, Ask AI, meeting summaries and translations. Those rewrite
  on purpose; "translate to English" changes every word.
- Fixing the text. The check only chooses between the cleaned text and the
  raw text that already exists.

## Anti-goals

The feature fails, even if it works, when:

- It flags normal cleanup often enough that the owner turns it off. Filler
  removal, self-corrections ("at three, no, four"), spoken numbers turned
  into digits and Markdown list markers must pass.
- It slows dictation noticeably.
- It writes dictated text anywhere new. Diagnostics get the kind of detail,
  never the words.

## What gets checked

The check runs on `protected.text` (raw after Dictionary replacements,
snippets as placeholders) against the sanitized cleaned output, both
before `protected.fill`. That way Dictionary replacements and snippets are
not differences.

| Kind | What counts | Lost | Invented |
|---|---|---|---|
| Number | Digit runs, with decimals, `%`, `:` times, thousands separators. Normalized to a value: `1,500` = `1500`, `3:00` = `3`, `15%` = `15`. | A value in raw missing from cleaned. | A value in cleaned not in raw. |
| Negation | English: not, no, never, n't, none, nothing, nobody, neither, nor, without. Vietnamese: không, chưa, chẳng, đừng, chả. Spanish: no, nunca, nada, nadie, ni, sin, tampoco. | Fewer in cleaned than in raw. | Not checked: added negations are rare and adding "no" is how self-corrections read. |
| Path | Token containing `/` or `\` with a word character on each side, a leading `~/` or `./`, or `name.ext` where ext is 1–5 letters (`Info.plist`, `last.wav`). | Raw token missing from cleaned, compared exactly. | Not checked. |
| Identifier | camelCase or PascalCase with an inner capital (`AppModel`), contains `_`, starts with `--` or `-x`, or wrapped in backticks. | Raw token missing from cleaned, compared exactly (backticks ignored). | Not checked: the project words rule asks the model to turn "app model" into `AppModel`. |

### Allowed differences (not flagged)

1. **Spoken numbers.** Cleaned has `5` where raw has "five", "năm" or
   "cinco". The checker maps number words 0–100 plus hundred, thousand,
   million (English, Vietnamese, Spanish) to values before comparing. A
   cleaned value that matches a spoken number in raw is not invented. A
   Vietnamese word that is also a number ("năm" = five or year) counts as a
   number only when cleaned has the matching digit. **(my call)**
2. **Self-corrections.** If raw contains a correction marker, details
   before the marker in that sentence may be dropped. Markers: "no, I mean",
   "I mean", "sorry", "actually", "à không", "à nhầm", "ý là", "no, perdón",
   "quiero decir". The negation in "no, I mean" / "à không" / "no, perdón"
   is part of the marker and not counted. **(my call)**
3. **List markers.** `1.`, `2)` or `-` at the start of a line in cleaned
   are not numbers. Document and Work styles format lists.
4. **Ordinals.** "first" ↔ `1st`, "thứ hai" ↔ `2nd`, "primero" ↔ `1.º`
   are the same value.
5. **Case of identifiers.** Not allowed: `appModel` vs `AppModel` is a
   difference. Identifiers are code.

When in doubt, the checker does not flag. A false alarm costs a pasted
raw text the owner did not need; a miss costs the same as today.

## What happens when the check fails

New `RawReason.detailChanged`. The result keeps both texts and a list of
issues: `[FidelityIssue]`, each with a kind (number, negation, path,
identifier), a direction (lost or invented) and the raw/cleaned token
(token kept in memory and history only, never in Diagnostics).

A new setting chooses the action. **(my call: default is Paste raw)**

| Setting | What pastes | HUD |
|---|---|---|
| Paste raw text (default) | `uncleanedText`, as if cleanup was off | Warning, 4 s: "Raw — cleanup changed a number" / "…dropped "not"" / "…changed a path" / "…changed a name". Second line: "⌃⌥R pastes the cleaned text". |
| Paste cleaned text and warn | cleaned text | Warning, 4 s: "Check — cleanup changed a number". Second line: "⌃⌥R pastes raw". |
| Off | cleaned text | Normal done pill. Issues are still recorded in history. |

The HUD title names the first issue by kind; with more than one issue it
says "changed 2 details". The key in the second line is the configured
*Paste raw* shortcut letter, not hard-coded.

### Swapping after the paste

*Paste raw* already replaces the last cleaned paste with raw text. When
the last result was a fidelity fallback (raw pasted, cleaned kept), the
same key pastes the cleaned text instead and the HUD says "Replaced with
cleaned text". Pressing it again swaps back. **(my call)** Same safety
rules as today's Paste raw: only when the field still holds the last
paste (`replacementDecision`), never in a secure field.

The menu bar popover's *Raw* button reads "Cleaned" (tooltip "Paste
cleaned (⌃⌥R)") when the last paste was a fidelity fallback.

### History

The history row shows a small tag: "raw · detail" (fallback) or "check"
(cleaned pasted with warning), in the warning color, next to the existing
"raw" tag. Hovering it lists the issues: "15 → 50", "dropped "not"",
"lost `Sources/App.swift`". Clicking the row's new swap button pastes
the other version, like *Paste again*.

`HistoryEntry` gains `fidelityIssues: [FidelityIssue]?` (optional, so
older history files still decode) and keeps `cleaned` for a fallback even
though raw was pasted.

### Where the setting lives

Style page, above the style pills, one row for every style:

> **When cleanup changes a number, path, name or "not"** — Paste raw text ▾
> BugVoice compares the cleaned text with what you said. Command mode and
> Ask AI are not checked.

Styles with cleanup off are never checked (nothing to compare).

Settings key: `styles.fidelityAction`, values `raw`, `warn`, `off`.
Global search gets an entry pointing at it.

## Scope in code

- `VoiceCore/FidelityCheck.swift` (new): pure function
  `FidelityCheck.issues(raw:cleaned:language:) -> [FidelityIssue]`, with
  the tokenizer, number-word tables and correction markers. Foundation
  only.
- `OutputSanitizer.swift`: add `detailChanged` to `RawReason`.
- `DictationPipeline.run`: after `.accepted(let cleaned) where
  protected.isIntact(cleaned)`, always run the check and store the issues
  on the result; the setting only decides what pastes. On `raw`, keep
  `cleaned` but paste `uncleanedText`.
- `DictationResult` / `HistoryEntry`: `fidelityIssues`, and a
  fallback keeps `cleaned`.
- Notes mode dictation goes through the same pipeline and is checked; the
  note editor gets the raw text on fallback. No swap key in Notes (the
  editor has its own undo). **(my call)**
- `HUDState`: new warning titles; `DictationController.pasteRaw`: swap
  direction for a fallback.
- `DictationHistoryView`, popover button label, Style page row,
  `GlobalSearch` entry.
- `Diagnostics`: `raw=detailChanged kinds=number,negation`, no tokens.

## Evaluation

Before release, three measurements, logged in
`docs/progress/fidelity-log.md`:

1. **Unit corpus** in `Tests/VoiceCoreTests/FidelityCheckTests.swift`:
   at least 60 raw/cleaned pairs across English, Vietnamese, Spanish and
   mixed, half that must pass (filler removal, spoken numbers, self
   corrections, list formatting, project-word joins, Spanish "no" as
   filler) and half that must flag (each kind, lost and invented). Written
   first, TDD.
2. **History replay**: a test-target tool reads the owner's local
   `history.jsonl`, runs the check on every entry with both `raw` and
   `cleaned`, and prints counts per kind plus the flagged pairs to the
   terminal only. Target: under 2% of entries flagged; every flagged pair
   reviewed by hand and listed in the log as true or false alarm (kind
   only, no text, in the committed log). Not run in CI.
3. **Timing**: check time for a 200-word dictation, under 5 ms.

If history replay shows more than 2% false alarms, tune the allowed
differences before shipping, or change the default to *Paste cleaned text
and warn*.

## Device checks

F1–F8 for the owner, in `docs/progress/fidelity-log.md`:

1. Say "the timeout is fifteen seconds" in Notion; pasted with 15, no warning.
2. Cleanup forced to drop "not" (custom Work tone: "remove the word not"); raw pastes, HUD names "not".
3. ⌃⌥R after F2 swaps in the cleaned text; again swaps back.
4. Setting on *Paste cleaned and warn*: F2 pastes cleaned with "Check" pill.
5. Setting Off: no warning, history still shows the tag.
6. "At three, no, I mean four" in Work style; pastes "at 4", no warning.
7. Vietnamese with a number: "họp lúc ba giờ" → "họp lúc 3 giờ", no warning.
8. History row tag hover lists the issue; swap button pastes the other version.

## Left to the builder

- Exact tokenizer and number-word tables, as long as the corpus passes.
- Wording of HUD second lines within the patterns above.
- Whether the history replay tool is a test with an env flag or a small
  script target.
