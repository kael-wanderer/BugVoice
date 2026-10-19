# Proposed new features

From the app review, 2026-10-19. Not scheduled; the owner will pick from
this list later. Each one picked becomes its own sub-project: spec, mockup,
plan, implementation.

All of them keep BugVoice local-first and reuse code that already exists.

| # | Feature | What it does | Builds on |
|---|---|---|---|
| 1 | Command mode — merged 2026-10-19; see `docs/progress/command-log.md` | Select text, hold Right Option, and say "make this formal" or "translate to English". With nothing selected, say what to write. Original restores the selection. | Transforms, selection reading in `FocusInspector`, the paste path |
| 2 | Learn from corrections — merged 2026-10-19, device checks pending; [log](progress/corrections-log.md) | A few seconds after a paste, read the text field back through Accessibility. If the user corrected a word, offer to add it to the dictionary. | `FocusInspector`, `DictionaryStore` |
| 3 | Live preview while speaking | Stream text into the HUD while the user talks. The pasted result does not arrive sooner, but the wait feels shorter. | WhisperKit streaming, HUD |
| 4 | Language per app — merged 2026-10-19; see `docs/progress/language-log.md` | Hint Vietnamese in chat apps and English in Terminal or VS Code. | `StyleRouter` app groups |
| 5 | Action items across meetings — implemented on `feat/action-items`, not merged; [log](progress/action-items-log.md) | One checkable list built from every meeting's action items, each linking back to its meeting. | Meeting summaries and action items |
| 6 | Shortcuts support (App Intents) | "Start meeting recording", "Transcribe file", "New note from text". Native, offline, no new dependency. | Meetings, Upload, Notes |
| 7 | Project words for coding agents — merged 2026-10-19; see `docs/progress/project-words-log.md` | Pick repo folders; their file and symbol names become dictionary words, so names like `AppModel` come out right in the terminal. | Dictionary |
| 8 | Paste raw instead — merged 2026-10-19; see `docs/progress/language-log.md` | One key replaces the last cleaned paste with the raw transcript, for when cleanup changed the meaning. | Paste last (⌃⌥V), history raw text |

## Speed note

History timings from 12 dictations (2026-10-19): speech-to-text 1.25–2.0 s,
cleanup 0.3–0.8 s, paste about 0.04 s, so release to text is about 2 s. Speech-to-text
is now the slowest step; transcribing while the user speaks would cut it. The owner
will give feedback on speed first.
