# Spanish for dictation and notes

Date: 2026-10-23. Status: draft for owner review.
Mockup: `docs/design/proposal-spanish.html`.
Changes a non-goal of `2026-10-19-language-and-fix-last-design.md`
("dictation stays two languages"), at the owner's request on 2026-10-23.

## Why

The owner asked for Spanish in meetings, dictation and notes. Meetings and
uploads already transcribe Spanish (`MeetingLanguages.choices` is English,
Vietnamese, Spanish). Dictation does not: every picker, the language key,
the per-app list and "Redo in the other language" know only English and
Vietnamese. With Language on Auto, Whisper may already detect Spanish, but
there is no way to ask for Spanish on purpose, no way to fix a dictation
that came out in the wrong language, and cleanup is not told it is Spanish.

Notes need no separate work: the Scratchpad microphone, the note editor and
the meeting window's My notes all dictate through `DictationController` and
`DictationPipeline`, so they get whatever dictation supports.

## Goals

1. **Choose your dictation languages.** Settings › Speech gets "Dictation
   languages": English, Vietnamese, Spanish, each a checkbox. Default
   English and Vietnamese, so nothing changes until Spanish is ticked. At
   least one stays ticked.
2. **Spanish everywhere a dictation language is picked**, when ticked: the
   Language switch in Settings, the menu bar popover switch, Dictation
   options › Language, the per-app list, the language key cycle, the HUD
   language label (`ES`) and the menu bar badge (`ES`).
3. **Spanish cleanup.** A Spanish dictation tells the cleanup model the
   speaker spoke Spanish, names Spanish filler words and self-corrections,
   and (with "Keep English words" on) keeps English words in English.
4. **Redo in another language** works with three languages and still does
   the English/Vietnamese swap first.
5. **Apple Shortcuts.** "Transcribe audio file" offers Spanish (uploads
   already transcribe it).

## Non-goals

- A Spanish interface. The app's text stays English.
- Limiting Auto detection to the ticked languages. Auto keeps today's
  behaviour (Whisper detects freely, then the per-app list). Worth doing
  later if Auto picks wrong languages; meetings already have the code
  (`MeetingTranscription.bestLanguage`).
- Spanish in the Vietnamese-specific Whisper hint (`Vocabulary.mixedExample`).
- Changes to meetings, uploads or translation; they already handle Spanish.
- Languages beyond English, Vietnamese and Spanish.

## Anti-goals

- Any visible change for someone who never ticks Spanish: same pickers,
  same key cycle, same redo behaviour.
- A per-app rule or the sticky switch silently pointing at a language the
  user has unticked.
- A redo order that makes the common English/Vietnamese fix take two
  presses.

## Design

### Dictation languages setting

`SpeechSettings.dictationLanguages: [SpeechLanguage]`, default `[.en, .vi]`.
Normalised like `MeetingLanguages.normalized`: drops `.auto` and repeats,
keeps the fixed order English, Vietnamese, Spanish, and falls back to the
default when empty. Decoding a settings file without the key gives the
default.

UI: a row of three checkboxes at the top of the Language card in
Settings › Speech, above the Language picker. The last ticked box is
disabled (same as Settings › Meetings). Footnote: "Languages you speak when
you dictate. Each one appears in the language switch, the language key and
the per-app list."

When a language is unticked:

- `speech.language` (the sticky switch) set to it becomes Auto.
- Per-app rules for it stay in the list and keep working; their picker
  shows the rule's language even though it is unticked (my call: deleting
  a rule the user set up on purpose is worse than one stale entry, and
  ticking the language again restores the full set). The anti-goal is met
  because the row still names the language it uses.

### Pickers

Every dictation language picker lists Auto (where it has Auto today) and
then the ticked languages in the fixed order. Labels: Settings uses
English / Vietnamese / Spanish; the popover switch and badges use
EN / VI / ES. The Settings footnotes that list "Auto, English,
Vietnamese" are built from the ticked languages.

`SpeechSettings` decoding accepts `es` for `language` and for app rules
(today rules with anything but en/vi are dropped).

### Language key

`LanguageKeyCycler(start:languages:)`: Auto → each ticked language in order
→ Auto. With the default languages this is today's Auto → EN → VI → Auto.
A start language that is not ticked starts the cycle at Auto.

### Cleanup and command prompts

`PromptBuilder` adds, for `.es`: "The speaker spoke Spanish. Remove Spanish
filler words (eh, este, o sea, pues) and apply self-corrections such as
"no, perdón" or "quiero decir" by keeping only the corrected version."
With "Keep English words" on, Spanish adds "Keep words the speaker said in
English in English." (the existing rule is about Vietnamese spelling, so
Spanish gets its own line). `CommandPrompt` gets the same keep-English
line for Spanish. The toggle reads "Keep English words in Vietnamese and
Spanish" while Spanish is ticked, and keeps today's label otherwise. No change for `.en`, `.vi` or `.auto` prompts.

### Redo in another language

`FixLast.redoLanguage(original:tried:languages:)` replaces
`otherLanguage(of:)`:

- `original` is the language the dictation first came out in (Whisper's
  detected code, may be any language or nil), `tried` the languages
  already used by redo for this dictation, `languages` the ticked ones.
- Candidates are the ticked languages minus the original and minus tried,
  in priority order English, Vietnamese, Spanish. Return the first.
- With none left, return the original (if ticked) so the next press goes
  back to where it started, and reset `tried`.

With English and Vietnamese ticked this is today's swap. With all three:
English → Vietnamese → Spanish → English; Vietnamese → English → Spanish →
Vietnamese; Spanish → English → Vietnamese → Spanish.

`DictationController` keeps `original` and `tried` for the last dictation
and clears them when a new dictation or command runs. The popover's
language button and its tooltip name the language the next press uses.

### Apple Shortcuts

`ShortcutsLanguage` and the Transcribe audio file intent's language
parameter gain Spanish → `[.es]`.

### HUD and menu bar

`DictationController.hudLanguage`, `CommandController`'s label and the
menu bar badge map `.es` to `ES`.

## Testing

TDD in `VoiceCore`:

- `SpeechSettings`: default, normalisation, decoding old files, decoding
  `es` rules and `language`, unticking resets the switch.
- `LanguageKeyCycler`: default cycle unchanged; with Spanish; start
  language not ticked.
- `FixLast.redoLanguage`: two-language swap; every three-language chain
  above; original outside the set (e.g. `pt`, nil); wrap-around.
- `PromptBuilder` and `CommandPrompt`: Spanish lines present for `.es`,
  absent for other languages.
- `ShortcutsLanguage.spanish`.

Speech check without pasting: synthesise Spanish with `say -v Mónica` and
run `BugVoiceBench` with `--languages auto,es` to confirm WhisperKit
returns Spanish text.

## Device checks (owner)

1. Settings › Speech: tick Spanish; ES appears in the switch, popover,
   Dictation options and per-app pickers.
2. Popover switch on ES: dictate Spanish into Notes; Spanish text, fillers
   removed.
3. Language key: Auto → EN → VI → ES → Auto, HUD shows each.
4. Scratchpad microphone and meeting My notes with the switch on ES.
5. Speak Spanish with the switch on Auto; press ⌃⌥L until Spanish if it
   came out wrong; order matches the table above.
6. Untick Spanish while the switch is on ES: switch goes to Auto; an
   existing Spanish per-app rule still shows Spanish.
7. Shortcuts app: Transcribe audio file offers Spanish.

## Left to the builder

File layout, view code, test names, exact footnote wording beyond what is
quoted here.
