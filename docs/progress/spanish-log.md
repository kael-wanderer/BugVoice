# Spanish dictation execution log

Date: 2026-10-23. Branch: `feat/spanish-dictation`.
Spec: `docs/superpowers/specs/2026-10-23-spanish-dictation-design.md`.
Plan: `docs/superpowers/plans/2026-10-23-spanish-dictation.md`.
Mockup: `docs/design/proposal-spanish.html`.

Meetings already offered Spanish. This branch adds it to dictation, and through
dictation to Scratchpad and note dictation. The setting defaults to English and
Vietnamese, so nothing changes until Spanish is ticked.

## Built

1. `882529a` Settings › Speech › Dictation languages (`SpeechSettings.dictationLanguages`,
   default English + Vietnamese). Unticking the language the switch is on resets the
   switch to Auto. Per-app rules for an unticked language keep working.
2. `02d3651` The language key cycles Auto, then each ticked language in English,
   Vietnamese, Spanish order.
3. `1437825` Fix last paste (redo) walks the ticked languages: English and Vietnamese
   swap first, Spanish comes after them.
4. `e8b37c5` Spanish cleanup rule (fillers such as eh, este, o sea, pues; self-corrections
   such as "no, perdón") and a keep-English rule for Spanish. Shortcuts gets Spanish.
5. `37c7251`, `5dfe78b`, `bba6bb9` App wiring: the popover switch, the Dictation options
   submenu, the menu bar badge, the HUD, the language key, redo, the per-app pickers and
   Shortcuts. Spanish Whisper credits ("Subtítulos realizados por la comunidad de
   Amara.org", "Gracias por ver") are filtered like the English ones. The key footnote
   lists the languages in the order the key cycles them.
6. `fb09a4e` The bench usage text lists Spanish.

No dependency added.

## Tests

`swift test`: **1,217 VoiceCore, 30 MCPKit, 114 BugVoiceMac**, all passing.
`Scripts/build-app.sh` succeeds, signed with Bugler Local Dev; no new warnings.

## Spanish speech check

`say -v Mónica "Mañana enviamos el prototipo y revisamos la accesibilidad."`, 16 kHz
mono WAV, `swift run -c release bugvoice-bench --languages auto,es --no-llm`:

| Clip | Lang | Audio s | STT s | WER | Transcript |
|---|---|---|---|---|---|
| es-1.wav | auto | 3.2 | 1.28 | 0.00 | Mañana enviamos el prototipo y revisamos la accesibilidad. |
| es-1.wav | es | 3.2 | 1.27 | 0.00 | Mañana enviamos el prototipo y revisamos la accesibilidad. |

Synthetic speech, not a human voice. Cleanup with a local model was not run.

## App check (second display, no dictation)

- Settings › Speech with Spanish unticked: checkboxes English and Vietnamese ticked, Language
  Auto · Vietnamese · English, footnotes as on `main`.
- Spanish ticked: Language gains Spanish, "English, Vietnamese or Spanish applies everywhere",
  key footnote "Auto, English, Vietnamese, Spanish", title "Keep English words in Vietnamese
  and Spanish".
- Popover switch: Auto · EN · VI unticked, Auto · EN · VI · ES ticked.
- Spanish unticked again afterwards; `settings.json` speech is back to `[en, vi]`, Auto.

The first ticked screenshot showed the key footnote in Settings order (Vietnamese before
English) while the key cycles English first; fixed in `bba6bb9` and checked again.

## Final review

Fresh reviewer on the whole branch: no Critical or Important. Re-graded and fixed:

- The Auto footnote read "Vietnamese or English applies everywhere" for someone who never
  ticks Spanish (main: "English or Vietnamese"). Now `DictationLanguages.orList` in cycle
  order; test `orListReadsInCycleOrder` RED→GREEN.
- The redo button's tooltip now names the language ("Redo in Spanish (⌃⌥L)"), as the spec says.
- A Spanish per-app rule with Spanish unticked is now also checked through `LanguageResolver`.

## Rulings

1. Test added: a switch set to an unticked language falls back to Auto. Cost if wrong: none.
2. `MenuLastDictation` takes a `redoLanguage` parameter so the view stays model-free. Cost: one parameter.
3. The Spanish keep-English line was reworded; the planned text was a substring of the Vietnamese
   line. Cost: one sentence of prompt wording.
4. The language key shows an unticked per-app start language instead of Auto; the first tap goes
   to Auto. Cost: HUD label in a rare case.
5. Settings › Speech Language picker and Dictation options keep Vietnamese before English. Cost:
   those lists read in a different order from the key.
6. Spanish Whisper credits are filtered. Cost: a real dictation of exactly "Gracias por ver" is dropped.
7. The key footnote lists languages in cycle order. Cost: one footnote.

## Deferred minors

- New per-app rules start on English (apps) or Vietnamese (websites) even when that language is unticked.
- A failed redo still moves the redo order to the next language.
- With one ticked language, the redo button re-runs that same language.
- An older build reading the new settings drops Spanish per-app rules and `dictationLanguages`.
- "Keep English words in Vietnamese and Spanish" names Vietnamese even when it is unticked.
- `LanguageKeyCycler.init(start:languages:)` defaults `languages`; a caller that omits it ignores the ticked set.

## Device checks (owner)

- [ ] 1. Settings › Speech: tick Spanish; ES appears in the switch, popover, Dictation
  options and per-app pickers.
- [ ] 2. Popover switch on ES: dictate Spanish into Notes; Spanish text, fillers removed.
- [ ] 3. Language key: Auto → EN → VI → ES → Auto, HUD shows each.
- [ ] 4. Scratchpad microphone and meeting My notes with the switch on ES.
- [ ] 5. Speak Spanish with the switch on Auto; press ⌃⌥L until Spanish if it came out
  wrong; the order is English and Vietnamese first, then Spanish.
- [ ] 6. Untick Spanish while the switch is on ES: switch goes to Auto; an existing
  Spanish per-app rule still shows Spanish.
- [ ] 7. Shortcuts app: Transcribe audio file offers Spanish.
