# Manual checklist — Dictation core

Build: `Scripts/build-app.sh && open build/BugVoice.app`. Record pass/fail and the date.

Before you start: grant Microphone, Accessibility and Input Monitoring, quit and
relaunch once, and wait for the speech model to be ready. Until then a press
shows *Model loading · downloading N%* or *Model loading · try again in a moment*.

Automated suite at the time of writing: `swift test` — VoiceCore 181 tests,
BugVoiceMac 26 tests, all passing.

## Dictation

| # | Where | Do | Expect | Result |
|---|---|---|---|---|
| 1 | Terminal + Claude Code | Hold Right ⌥, say a multi-sentence prompt, release | HUD *Listening* → *Transcribing* → *Done (Terminal)*; text in the prompt, not submitted, no trailing period; *Cleaning* never shows | |
| 2 | iTerm | Same | Same | |
| 3 | Warp | Same | Same | |
| 4 | VS Code editor | Dictate a sentence | Style `other`, cleaned | |
| 5 | VS Code terminal panel | Dictate a command | Style `terminal` (no *Cleaning*) | |
| 6 | TextEdit | Say "um so the meeting is on friday no I mean thursday" | *Cleaning (Qwen)* then *Done (Document)*; text like "The meeting is on Thursday." | |
| 7 | Notion | Dictate with fillers and a self-correction | Cleaned paragraph, correction applied | |
| 8 | Chrome text area (docs.google.com) | Dictate a list "first… second… third…" | Markdown or bulleted list | |
| 9 | Hands-free | Double-tap Right ⌥, dictate 2 minutes into Notion, tap once | HUD with timer; full text inserted after stop | |
| 10 | Vietnamese Telex input active | Dictate Vietnamese into Notes | Diacritics intact, no doubled characters | |
| 11 | Mixed language | "Mình cần deploy cái API lên staging" | English terms kept as spoken | |
| 12 | Silence | Hold 1 s without speaking | *Nothing heard* or no HUD; nothing pasted | |
| 13 | Short press | Hold 0.2 s silently and release | Nothing pasted | |
| 14 | LM Studio off (or model name `nope`) | Dictate into TextEdit | *Raw — model unavailable* within ~3 s after transcription; raw text pasted | |
| 15 | Retry last | Menu → Retry last recording | Same text re-inserted | |

## Secure fields

| # | Where | Do | Expect | Result |
|---|---|---|---|---|
| 16 | Safari password field | Dictate | *Secure field — copied*; nothing typed | |
| 17 | Safari password field | Press ⌃⌥V (Paste last) | *Secure field — copied*; nothing typed | |
| 18 | Safari password field | Dictation page → row → Paste again | *Secure field — copied*; nothing typed | |
| 19 | After 16 | Check `~/Library/Application Support/BugVoice/last.wav`; Menu → Retry last | No `last.wav`; Retry last does nothing | |
| 20 | After 16 | Open the menu and the Dictation page | No text from the password dictation in the preview, Paste last or history | |

## Hotkey

| # | Where | Do | Expect | Result |
|---|---|---|---|---|
| 21 | Any text field | ⌥E, ⌥⇧K, ⌃⌥V while using Right ⌥ | No recording; if the hold passed 150 ms the pill shows then hides; nothing pasted or logged | |
| 22 | Any text field | Hold ⌃, press Right ⌥, release ⌃, keep holding Right ⌥ | No recording (hotkey must be held alone) | |
| 23 | Any | Hold Right ⌥ without releasing past the time cap (or lose the event tap) | Recording stops at the cap; no hot mic | |
| 24 | Menu | When the menu shows *Hotkey not active*, choose the retry action | Hotkey works again; Permissions opens if Input Monitoring is missing | |
| 25 | Settings → General | Pick F13–F19 as hotkey, dictate | Chosen key works | |

## Clipboard

| # | Where | Do | Expect | Result |
|---|---|---|---|---|
| 26 | Text | Copy text, dictate, ⌘V elsewhere | Original text pastes | |
| 27 | Image | Copy image in Preview, dictate into TextEdit, ⌘V in Notes | Image pastes | |
| 28 | Finder file | Copy a file, dictate, ⌘V in Finder | File pastes | |
| 29 | Paste not picked up | Dictate where paste is ignored | *Copied — press ⌘V*; text left on clipboard | |

## HUD

| # | Do | Expect | Result |
|---|---|---|---|
| 30 | Trigger each state: Listening, Transcribing, Cleaning (model), Done (style), Raw — model unavailable, Secure field — copied, Copied — press ⌘V, Nothing heard, Model loading | Pill width fits the text in every state; never steals focus | |
| 31 | Hands-free past 9:59 | Clock 10:00 does not clip | |

## Windows, menu, settings

| # | Do | Expect | Result |
|---|---|---|---|
| 32 | Open the main window (menu or ⌃⌥B) | Dock icon appears | |
| 33 | Close it with ⌘W, then with the red button | Dock icon disappears | |
| 34 | Click the Dock icon while visible, or relaunch from Finder | Main window reopens | |
| 35 | Open Permissions and the main window; close one, then the other | Dock icon stays until both are closed; a minimized main window keeps it | |
| 36 | Launch with a permission missing | Permissions window opens; rows update within ~1 s of granting | |
| 37 | Menu status line | Ready → Listening → (Model loading on first run); every menu item works | |
| 38 | Settings text fields | ⌘C / ⌘V / ⌘X / ⌘A work | |
| 39 | Settings → Text model: type a key, switch Provider without Return | Key saved to the previous provider | |
| 40 | Make `settings.json` read-only, change a setting | *Could not save* alert; OK dismisses | |
| 41 | Settings → Storage → Don't save | Confirmation; Cancel keeps the setting; Confirm clears history | |
| 42 | Settings → Text model → Send test sentence / Refresh | Works against LM Studio; model list loads | |
| 43 | Dictation page | Renders history; search filters; Copy copies; Delete removes the row; Paste again pastes into a text field | |
| 44 | Quit and reopen | No permission prompts (stable signature) | |

## Meetings

Run these after building with `Scripts/build-app.sh`. Keep the Result column
blank until the maintainer runs each check.

| # | Where | Do | Expect | Result |
|---|---|---|---|---|
| 45 | Permissions | Open Permissions and inspect System Audio Recording | Row says “Requested when the first meeting starts”; no Screen Recording prompt or preflight | |
| 46 | First meeting | Start a meeting and approve System Audio Recording | OS permission prompt appears; mic and system tracks start; dictation permissions are unchanged | |
| 47 | Meeting audio | Speak, then play audio in another app; compare You and Others meters and tracks | Mic appears on You, app playback appears on Others, and BugVoice's own sounds stay out of Others | |
| 48 | Meeting audio | Run once without headphones, then repeat with headphones | Note any Others speech repeated on You; headphones reduce mic echo. Echo is a known risk. | |
| 49 | Recorder panel | Start from the menu, press ⌃⌥M, then click Pause/Mark/Resume/Stop | Panel floats above apps and never takes typing focus; timer and meters update; marks follow active meeting time | |
| 50 | Meetings page | Start and stop a meeting from the Meetings page | Recording begins and the final transcript appears in the selected meeting | |
| 51 | Concurrent dictation | Dictate while a meeting is recording | Dictation hotkey, HUD, transcription and paste work; dictation waits for at most one meeting chunk | |
| 52 | Pause and resume | Pause, wait 30 seconds, mark, resume, then stop | Paused gap is excluded from duration and timeline; marks remain at active meeting offsets | |
| 53 | Sleep and quit | Record, pause or sleep the Mac, then quit BugVoice during a meeting | Committed audio remains in `.capture`; next launch marks the meeting Interrupted and offers Recover recording | |
| 54 | Crash recovery | Force quit BugVoice during recording, relaunch, recover the meeting | Checkpointed mic/system audio is retained; recovery transcribes and finalizes; failed finalization keeps journals | |
| 55 | Transcription | Record English, Vietnamese, and mixed speech; inspect per-chunk language | Auto timestamps remain usable; empty Vietnamese auto chunks retry with `vi` and VAD window times; no prompt appears mid-meeting | |
| 56 | Transcription | Stop a long meeting and watch the library status | Status advances as “Transcribing N%”; final pass uses bounded chunks and replaces interim text | |
| 57 | Summary and action items | Generate both tabs with the configured text model, then cancel a long generation | Parts and merge progress are visible; cancel stops between model calls; generated text is saved | |
| 58 | Timeline and player | Play audio, scrub waveform, click rows, skip ±15 seconds, change speed | Playback seeks accurately; current row highlights only during playback | |
| 59 | Export | Export Markdown, SRT, and audio to a chosen folder | Each file opens and contains the meeting's title, timestamps, transcript, or mixed audio | |
| 60 | Meeting actions | Rename, delete one meeting, and inspect a second meeting | Rename persists; confirmed deletion removes only the selected meeting and its files | |
| 61 | Settings → Meetings | Set Never, then 30/90/365 day deletion and change summary budgets | Values persist after relaunch; only expired Ready meetings are removed; generation limits clamp safely | |
| 62 | Settings → Storage | Inspect Meetings size during a recording and after finalization; Show in Finder | Allocated size includes `.capture` journals while recording and final audio after finalization | |

## Notes

Run these after building with `Scripts/build-app.sh`. Keep the Result column
blank until the maintainer runs each check.

| # | Where | Do | Expect | Result |
|---|---|---|---|---|
| 63 | Notes page | Open Notes, create notes, search by title and body, select another note | Split list/editor works; search is literal and case/diacritic insensitive; selected note is clear | |
| 64 | Notes files | Open a user-added `.md` with no leading `# ` heading, then an empty `.md` | Filename supplies the title; whole original file is the body; opening does not rewrite either file | |
| 65 | Note title and save | Rename to an existing title, type in the body, wait 500 ms, then quit and reopen | Rename commits on Return/focus out with a collision-safe filename; body survives save and relaunch | |
| 66 | External edits | Change a clean note outside BugVoice, then repeat after editing it in BugVoice; activate/select/save | Clean change reloads; dirty change says “Changed outside BugVoice” and offers Reload or Keep mine | |
| 67 | Notes dictation | Put the caret or a selection in the editor, hold Right Option, speak, and release | Text replaces the captured selection or inserts at the caret; no pasteboard, history, or `last.wav` change | |
| 68 | Focus loss and changed note | Start Notes dictation, move focus to another app, then repeat after changing the captured note | First run inserts into the captured note; changed note receives text at the body end; no paste occurs elsewhere | |
| 69 | Deleted captured note | Start Notes dictation, delete its captured note before transcription finishes | Result is discarded with a plain-English message; no other note or paste target receives text | |
| 70 | Undo | Dictate into a visible note, then into a note whose editor is off screen; reopen and undo | Each insertion is one undo step; off-screen insertion can be undone after reopening | |
| 71 | Notes controls | Use the mic button, ⌃⌥N, Copy as Markdown, Export, and confirmed Trash | Listening bar appears; shortcut opens a new note; copy/export contain canonical Markdown; Trash affects only the confirmed note | |
| 72 | Notes storage and quit | Inspect Notes size/count and Show in Finder; quit with dirty Notes and with an active Meeting | Notes size/count are shown; pending notes save before quit; meeting Stop and keep / Cancel flow still works | |
