# Manual checklist — Dictation core

Build: `Scripts/build-app.sh && open build/BugVoice.app`. Record pass/fail and the date.

Before you start: grant Microphone, Accessibility and Input Monitoring, quit and
relaunch once, and wait for the speech model to be ready. Until then a press
shows *Model loading · downloading N%* or *Model loading · try again in a moment*.

Automated suite at the time of writing: `swift test` — VoiceCore 127 tests in
14 suites, BugVoiceMac 17 tests in 3 suites, all passing.

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
