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


## Insights

Run these after building with `Scripts/build-app.sh`. Keep the Result column
blank until the maintainer runs each check.

| # | Where | Do | Expect | Result |
|---|---|---|---|---|
| 73 | Insights page | Open Insights from the sidebar in light, then dark | 4 + 3 cards, heatmap with today's cell, both breakdown panels; Local badge; Details tab disabled with "Later" | |
| 74 | Period switch | Choose 30 days, then 7 days, then All time | Cards and breakdown change; heatmap dims days outside the period; Current streak unchanged | |
| 75 | Live update | With Insights open, dictate into Terminal, then VS Code | Words, Dictations, today's cell and both app bars update without reopening | |
| 76 | Notes | Dictate twice into the same note | Notes card +1, note words increase; Dictation history unchanged | |
| 77 | Meetings | Record a 1-minute meeting and stop | Meetings card +1, hours update | |
| 78 | Clear history | Settings → Storage → Dictation history → Clear… | Insights numbers unchanged | |
| 79 | Reset insights | Settings → Storage → Insights → Reset… → Reset; quit and relaunch | Everything zero; relaunch does not refill from history | |
| 80 | Window chrome | Visit every page | No title text; sidebar full height with window buttons on it; no page content under the title bar | |


## Dictionary and Style

Run these after building with `Scripts/build-app.sh`. Keep the Result column
blank until the maintainer runs each check.

| # | Where | Do | Expect | Result |
|---|---|---|---|---|
| 81 | Dictionary page | Add "OpenWhispr, Supabase" in one go | Both rows appear at the top, newest first | |
| 82 | Heard as | Add heard-as "open whisper" to OpenWhispr; dictate "open whisper is great" in TextEdit | "OpenWhispr is great" | |
| 83 | Snippet in Slack | Add snippet "my linkedin" → URL; dictate "here is my linkedin" in Slack | Cleaned Work sentence with the exact URL | |
| 84 | Multi-line snippet | Add "sign off" with two lines; dictate it in Mail | Line breaks kept | |
| 85 | Model off | Quit LM Studio; dictate "here is my linkedin" | Snippet still expanded | |
| 86 | Style page | Open Style; dictate in Slack and in Zalo | Slack under Work, Zalo under Personal; each dictation shows that tone | |
| 87 | Move app | Move Telegram to Work; dictate in Telegram; then Reset | Work tone; after Reset it is under Personal again | |
| 88 | Tone | Edit the Work tone, then Reset to default | Default text restored | |
| 89 | Migration | Quit; put a term and a `=>` line in `vocabulary.txt`; delete `dictionary.json`; launch | Word and snippet appear; file renamed `vocabulary.migrated.txt` | |
| 90 | Settings | Open Settings | No Vocabulary or Styles tab; Speech reads "Use Dictionary words as hints" | |
| 91 | Bundle IDs | For WhatsApp, Messenger, Teams, Lark, run `osascript -e 'id of app "Name"'` | IDs match `StyleRouter.defaultApps`; fix any that differ | |

## Models

Run these after building with `Scripts/build-app.sh`. Keep the Result column
blank until the maintainer runs each check.

| # | Where | Do | Expect | Result |
|---|---|---|---|---|
| 92 | Upgrade | Launch the new build over the old settings; dictate in TextEdit | Still cleaned by the same model; Models tab shows one connection, named after the old address, used by every row; the old key works without re-entering it | |
| 93 | Anthropic | Add Anthropic with a key; Test connection; set Meeting notes to it; generate a summary | Models listed; summary generated | |
| 94 | OpenAI | Add OpenAI with a key; set Dictation cleanup to a gpt model; dictate | Cleaned text, no `max_tokens` error | |
| 95 | OpenRouter | Add OpenRouter with a key; Test connection | Models listed | |
| 96 | Ollama | Add Ollama with Ollama not running; set Dictation to it; dictate | Orange dot; raw text pasted | |
| 97 | Custom address | Add an OpenAI-compatible server at `http://192.168.1.5:8000` | "Use https:// for a server that is not on this Mac."; Save disabled | |
| 98 | claude | Set Meeting notes to Claude Code; generate a summary | Summary generated; no `claude` process left in Activity Monitor | |
| 99 | codex and pi | Repeat 98 with Codex, then Pi | Summary generated each time | |
| 100 | Cancel | Start a CLI-backed summary and cancel it | The process ends within 2 s | |
| 101 | Menu bar | Switch "Dictation model" in the menu | The Dictation row in Settings → Models changes to match | |
| 102 | Keys | Launch over a build that kept keys in Keychain; allow each prompt; quit; rebuild; launch again | Prompts once per saved key, never again; `credentials.json` is `-rw-------`; Keychain Access shows no BugVoice items | |

## Upload audio/video

Run after building with `Scripts/build-app.sh`. Results stay blank until run on device.

| # | Where | Do | Expect | Result |
|---|---|---|---|---|
| 103 | Sidebar / Upload | Open Upload and click the speech model link | Upload follows Meetings; empty drop copy matches mockup; Settings › Speech opens | |
| 104 | Upload | Browse, then drop several supported files over different parts of the page; cancel a draft | Multiple selection allowed; cards show name, Audio/Video, duration and size; draft Cancel creates no folder | |
| 105 | Upload | Transcribe MP3, WAV, M4A, AIFF, CAF, MP4, MOV and M4V fixtures | Reading file… then Transcribing locally…; each becomes ready with the configured speech engine | |
| 106 | Upload / sidebar | Queue three files, leave page and close/reopen main window | FIFO, one active job; Waiting / Transcribing N% / Open in Meetings; ring follows current phase; work continues | |
| 107 | Upload / Meetings | Open ready result and Clear finished | Uploaded badge in row and title; metadata says from original name; clearing queue keeps meeting | |
| 108 | Meeting detail | Play, scrub, change speed and click transcript lines | Correct audio and seek/highlight timing; every row says Speaker | |
| 109 | Meeting detail | Generate Summary and Action items with Meeting notes model; export Markdown, SRT and audio | No automatic generation; configured model used; Speaker in text exports; audio export is audio.m4a | |
| 110 | Finder / Storage | Inspect saved upload and original file | Only audio.m4a retained as audio; no mic/system files or completed capture journal; original bytes/location unchanged; Meetings storage includes upload | |
| 111 | Upload / Meetings | Start meeting during upload transcription; pause, resume and stop meeting; submit another upload while recording | Meeting starts; upload yields between chunks, stays held through pause/final pass, then resumes; new upload waits | |
| 112 | Upload / dictation | Dictate while upload transcribes | Dictation has priority; upload continues between requests; with WhisperKit, import makes no network request; no capture permission request | |
| 113 | Upload | Cancel during reading, transcription and while waiting | Workers stop; corresponding meeting folder removed; original untouched; next job advances | |
| 114 | Quit / relaunch | Quit once during reading and once during transcription | Reading staging discarded; transcription resumes from durable work without mic/system capture or source file | |
| 115 | Upload / Meetings | Induce recognition failure, then Retry transcript | Exact retained-audio error; audio plays/exports; retry uses same meeting and the kept journal; journal removed once ready | |
| 116 | Upload | Try unsupported/DRM file and simulate disk full | Exact unreadable/disk-full sentence; partial folders removed; next queued file runs | |
| 117 | Meetings / Settings / Insights | Search uploaded title and transcript, apply Delete ready meetings after, compare Insights | Search finds both; uploads expire counted from import time, not media date; active uploads kept; upload minutes/counts do not change Insights | |
| 118 | Upload | Import fixtures with metadata date, filesystem date only and neither usable date | Date fallback order correct; title drops extension; duration comes from asset | |
| 119 | Upload / Activity Monitor | Run the five review-focus inputs below; sleep/wake during a long job | Expected errors or ready result; bounded buffers; no dictation time cap; wake resumes upload | |
| 120 | Upload | Upload a music-only MP3 | No Russian/Japanese subtitle credits or "Music" lines in the transcript | |
| 121 | Upload | Upload 6 or more files; page with Newer/Older; press Clear history | 5 per page, newest first; Clear history empties finished rows and every meeting stays in Meetings | |
| 122 | Meetings | Right-click a meeting row; choose Delete…; confirm. Check More beside the title is a compact button | Meeting is gone from list and disk; right-click offers no Delete while recording | |
| 123 | Meetings | Right-click a meeting row; choose Rename…; save. Click a row on its badge, status, time or last line | New title shows in list and details; clicking anywhere on the card selects it | |
| 124 | Notes | Dictate twice at the end of a note | The second dictation starts after a space, never glued to the last word | |
| 125 | Notes / Dictation | With a local 27B model and a 3 s limit, dictate about 45 words into a note and into Notion | Both are cleaned (punctuation, no fillers), not raw; short dictations stay as fast as before | |
| 126 | Meetings / Notes | Folder menu → New folder… "Project A"; Manage folders… rename it "Project Atlas"; try "unfiled" and a duplicate | Folder appears on both pages; rename keeps its items; reserved and duplicate names show the message | |
| 127 | Meetings | Filter by a folder, then add a tag chip; search "#tag" | List shows only matching meetings; counts in the menu match | |
| 128 | Meetings / Notes | Right-click a row → Move to folder › another folder | Row leaves the filtered list and appears under the new folder | |
| 129 | Meetings / Notes | In the labels box type "#onb", pick an existing tag, then create a new one; add an 11th tag | Autocomplete lists existing tags first; 11th tag shows the limit message | |
| 130 | Upload | Drop 2 files; set Save to and tags on the first; Apply to all; Transcribe | Both meetings are in that folder with those tags; next upload defaults to it with "Last used" | |
| 131 | Meetings | With some tags in use, generate a Summary | Up to 3 purple suggested chips; clicking adds the tag; ✕ clears them; nothing added without a click | |
| 132 | Meetings / Notes | Delete a folder that has items | Items show under Unfiled; no files deleted; page filter falls back to All | |
| 133 | Notes | Tag and file a note, then open its .md file in TextEdit or Obsidian | File starts with --- folder/tags --- then # Title; other apps' keys kept after an edit | |
| 134 | Meetings | While recording, change the meeting's folder and tags; stop | Labels kept after transcription finishes | |
| 135 | Notes | Open a note that has text (fresh launch, then select another note and back) | Body text shows in the editor and wraps at the window width (BV-0006) | |
| 136 | Scratchpad | Open 3 notes from the list; quit and relaunch; rename one, quit and relaunch | Same tabs and active tab after each launch; blue dot on open rows; sidebar and menu say Scratchpad | |
| 137 | Scratchpad | Close the active middle tab, then the last, then the only one | Right neighbor activates, then the left one, then "Select a note"; notes are saved, not deleted | |
| 138 | Scratchpad | Delete a note that is open in a tab | Its tab closes; the next tab is shown | |
| 139 | Scratchpad | Type `# H`, `**b**`, `_i_`, `~~s~~`, `` `c` ``, `[t](https://a.b)`, `- [x] done`, `> q` and a fenced block | Headings sized, marks grey, link blue, done task struck, code monospaced on a tint; text unchanged on disk | |
| 140 | Scratchpad | Select a word; press ⌘B, ⌘B, ⌘I, Strikethrough, Code, ⌘K; press ⌘Z after each | Wraps then unwraps; link selects https://; each ⌘Z undoes exactly one command | |
| 141 | Scratchpad | Select 3 lines (one blank); press Numbered, then Numbered again; Checklist on an empty line; H1 on a bullet | 1. 2. skipping the blank, then removed; "- [ ] " added; bullet replaced by "# " | |
| 142 | Scratchpad | Switch to Doc; click a task box; click a link; switch back | Rendered view; box toggles [ ]/[x] in the file; link opens in the browser; choice remembered after relaunch | |
| 143 | Scratchpad | Select a Vietnamese paragraph with a typo; Transforms → Polish (⌘1); Replace; ⌘Z | Working… then preview with word diff and model name; Replace swaps the text; one ⌘Z restores it; still Vietnamese | |
| 144 | Scratchpad | Run More concise with no selection; type in the note before it finishes | Preview says "The note changed. Run the transform again."; Replace and Insert below disabled | |
| 145 | Scratchpad | Bullet points (⌘4) on a paragraph; Insert below | Blank line, then the list after the paragraph's last line; original kept | |
| 146 | Scratchpad | Ask a question (⌘J) about a fact in the note and one not in it; Insert below | Short answer under "From this note:"; missing fact says so in one sentence; answer appended at the end | |
| 147 | Scratchpad | Set the Notes model to none; run Polish. Select over 12,000 characters; run Polish | "Choose a Notes model in Settings → Models." / "Select less text. Transforms handle up to 12,000 characters." | |
| 148 | Scratchpad | Copy as → Markdown, Plain text, Email; paste each into TextEdit | Markdown has # title; Plain text has no marks and links as text (url); Email rewrite pasted; notice "Copied as Email"; note unchanged | |
| 149 | Meetings | On a meeting with a summary: Send to Scratchpad; More → Send to Scratchpad → Transcript | Notice "Sent to Scratchpad as “<title> · Summary”"; stays on Meetings; notes have the meeting's folder and tags; transcript lines read m:ss Speaker: text | |
| 150 | Scratchpad | In Doc view press Dictate and speak; then hold Right Option in Markdown view mid-paragraph | Switches to Markdown and adds the text at the end; second dictation lands at the caret | |
| 151 | Scratchpad window | With Slack (or any app) in front, press ⌃⌥N | Window floats over Slack with a new note, caret in the body; Slack keeps its window; typing goes to the note | |
| 152 | Scratchpad window | With another app in front, open the window from the menu; click into the body and type; press ⌘Z and ⌘⇧Z | Text lands in the note, not the other app; ⌘Z removes it, ⌘⇧Z puts it back | |
| 153 | Scratchpad window | Turn Keep on top off and click another app; turn it on; open a full-screen app and press ⌃⌥N | Off: the window goes behind; on: it stays over other apps, also over the full-screen app | |
| 154 | Scratchpad window | Press Smaller, then Larger; Hide notes, then Show notes; quit and relaunch | 440 pt wide with no list, then the old width; list hides and shows; size, list and bar choice kept after relaunch | |
| 155 | Scratchpad window | Formatting bar: H1, H2, B, I, U, S, code, bullets, numbers, checklist, quote, indent, link; Tab and Shift-Tab on a list line | Each changes the Markdown as in the mockup; underline is `<u>…</u>`; Tab indents a list line two spaces, Shift-Tab undoes it; Tab on a plain line types a tab | |
| 156 | Scratchpad window | Table button: hover to 3 × 4 and click; type in cells; switch to Doc | The picker reads "3 × 4"; a 3-column, 4-row Markdown table is inserted; Doc view shows a grid with a bold header | |
| 157 | Scratchpad window | Open two notes; switch tabs; press ⌘⇧C and paste into Notes (Apple), Gmail and Terminal | The shown note is copied: formatted in Notes and Gmail (headings, lists, table, links), plain text in Terminal | |
| 158 | Scratchpad window | Select one paragraph and Copy; Copy ▾ → Copy as Markdown, Copy as plain text, Export… | Only the selection is copied; Markdown has the `# ` title; plain text has no marks; Export saves a .md file | |
| 159 | Scratchpad window | Open from Slack, type, press ⌘↩ | Text copied, window closes, Slack is in front; ⌘V pastes it | |
| 160 | Scratchpad window | Click into the note while another app is in front, hold Right Option and speak; press Dictate and speak | Text lands in the note at the caret, cleaned with the Notes model; the Listening bar shows; the other app gets nothing | |
| 161 | Scratchpad window | AI bar: Polish (⌘1) on a Vietnamese paragraph; Undo in the notice; More professional (⌘2), More casual (⌘3), Run again | Text replaced directly and selected; notice "Polished · N words" with Undo; Undo restores; Run again redoes the last chip on the original text; still Vietnamese | |
| 162 | Scratchpad window | History (clock) after two changes; choose the older entry; ⌘Z | Entries "Before Polish · time · N words", newest first; choosing one puts that version back; ⌘Z returns to the text before | |
| 163 | Scratchpad window | Box: "make it shorter" (Return); then "who is mentioned?" | First is applied to the note with notice "Changed"; second shows a reply with Copy, Insert below, Dismiss; the note is unchanged | |
| 164 | Scratchpad window | Set the Notes model to none; press Polish | "Choose a Notes model in Settings → Models."; the note is unchanged | |
| 165 | Scratchpad window | ⌘N, type nothing, ⌘W; ⌘N, type, ⌘W | Empty note goes to the Trash; the note with text stays | |
| 166 | Scratchpad page | Hover a card; Pin; change Sort; type in Search; Refresh; click a card | Edit, Pin, Trash show on hover; pinned card moves first with a pin; sort and search filter the cards; click opens the note in the window | |
| 167 | Scratchpad page | Move a card to the Trash; check `~/.Trash` | Confirmation, then the note leaves the page and its file is in the Trash | |
| 168 | Meetings / Upload | Send to Scratchpad, then open the window | Notice as before; the new note is in the window's list | |
| 169 | Meeting audio | Record a meeting while a browser tab plays a video | Others meter turns green while the video plays; `system.m4a` is as long as `mic.m4a`; video speech appears as Others | |
| 170 | Settings › Meetings | Open Languages; turn Spanish on, then turn every language off | English and Vietnamese on by default; the last language cannot be turned off; choice persists after relaunch | |
| 171 | Recorder panel | During a meeting open the language chip (EN · VI) and choose English only; pause with "ah… e" fillers; stop | Chip shows EN; no Portuguese or other-language lines; filler-only lines are not in the transcript; final transcript uses the same choice | |

Review-focus inputs: zero-length file; 48 kHz stereo or 5.1; video track only;
source removed/moved while reading; three-hour-or-longer file. A reader already
holding an open file may complete after its pathname disappears; a read failure
must never produce truncated ready audio.
