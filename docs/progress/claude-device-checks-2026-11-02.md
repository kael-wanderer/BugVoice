# Claude device checks — 2026-11-02

Run by Claude on the owner's Mac while the owner was away, on the installed
`/Applications/BugVoice.app` build 376. These are Claude checks, not
owner-verified evidence (see HANDOFF's definition).

Method: speech came from `say` voices (English Samantha, Vietnamese Linh, Spanish
Eddy) played through the FREQUENCY 2.0 speakers into the Jabra SPEAK 410 mic. The
hotkey was a synthetic Right Control hold (CGEvent). Test targets: TextEdit, a
local Chrome page with password and text fields, Ghostty (`cat` window), Slack's
Find-a-DM search box, Notion quick search. Screens were read with `orca computer`,
an AXDescription dump, and `screencapture`. The data folder, clipboard, volume,
keyboard-navigation setting and the Ghostty per-app rule were restored afterwards.

**Cleanup model blocker (first run):** oMLX answered 401 to the key BugVoice stores (4 chars).
Readiness card: "Qwen: The key was refused." Checks that need a model ran against
a local fake OpenAI-compatible server on 127.0.0.1:8011, which echoes the
dictation with scripted edits (e.g. drop "not") and an optional delay. That tests
BugVoice's logic, not model quality. After the owner restarted oMLX the key
worked (200) and checks 4, 6, 10 and 11 ran against the real model.

## Review checks

| # | Result | Evidence |
|---|---|---|
| 1 | Pass | Started in Chrome password field, focus moved to a text field at release: both fields empty, text on clipboard, no history row. |
| 2 | Pass (Chrome → TextEdit, not Notion → Slack) | HUD "Copied — press ⌘V · another app came to the front"; TextEdit unchanged. |
| 3 | Pass | Engine on OpenAI-compatible server (localhost:8000, refused key): both failures under Needs attention, "The recording is kept until …"; switched to WhisperKit, Retry: text on clipboard, row gone. |
| 4 | Pass | Real model (oMLX Qwen3.8-27B), people-bot meeting: generated 8 items, checked "Share the slide…", Regenerate reworded the list; the checked item stayed, struck through, "Done 2 Nov", "From an earlier version of this list". Quality: first list was mostly demo topics, not tasks (7 of 8). |
| 5 | Pass | "input device" → Speech tab. "retention" lists Delete meetings automatically (Meetings) first and Keep dictation history (Storage) second. |
| 6 | Pass (dot colour partial) | oMLX stopped: "Qwen: Could not connect to the server." with Check again, dot orange (not red). After the owner restarted oMLX: all four rows green, "Qwen, server reachable". |
| 7 | Pass | HUD "Cancelled · nothing was pasted · Retry last runs it again"; TextEdit, history, clipboard unchanged; popover Retry pasted the sentence. |
| 8 | Pass | `kill -9` during Cleaning; relaunch: "BugVoice quit before this dictation finished."; Retry copied the text. Row title says "Transcription failed" though the kill was during cleanup. |
| 9 | Pass | Failed Vietnamese dictation, engine fixed, Retry in Vietnamese: "Chiều nay chúng ta họp với nhóm thiết kế lúc 3 giờ." on clipboard. |
| 10 | Pass, minor slips | 22-min people-bot meeting, all four templates. General and Technical design: facts match. Stand-up: "Next" stretches the closing remark into a plan. Interview: frames the demo as a candidate; invents a meaning for `/log` ("logs actions", from a misheard "lock"). No invented owners or dates; follow-ups say "Unspecified". |
| 11 | Partial | Edit: line 1:09 "octa" → "Okta account": saved, "Edited" label, original kept. Revert to original: original back, label gone. Export: save panel cannot be driven (keys do not reach it), code exports `displayText`. **Ask failed 3 of 3** ("Ask could not read the model's answer. Try again."): all notes and meetings (108 passages, read 40) and this meeting only (43, read 40), ~40 s each, log `outcome=failed.unreadable`. Same rules prompt sent directly to oMLX (small, 14k tokens, thinking on and off) returns valid JSON, so the cause is in the app's real passages or reply; needs the raw reply logged. |
| 12 | Pass with one intermittent issue | Same field pasted in Chrome (4 of 5), Ghostty, Slack search, Notion search, TextEdit. Different field: Chrome A→B, Slack (Tab after release), Ghostty split-pane switch all copied with "the cursor moved to another field". **Intermittent:** 2 same-field runs copied instead of pasting (Chrome right after a page reload; TextEdit once, `copiedFieldChanged`). Not reproducible on demand (0 of 6 retries). Likely cause: `FocusInspector.focusedElement()` read system-wide at hotkey down catches a transient element right after an app/page focus change, so `CFEqual` fails at paste time. |

## Fidelity (fake model)

| # | Result | Evidence |
|---|---|---|
| F1 | Pass | Whisper already writes 15; cleanup writing "fifteen" raised no issue. |
| F2 | Pass | Raw pasted; HUD "Raw — cleanup dropped “not” · ⌃⌥R pastes the cleaned text". |
| F3 | Pass via popover | Popover "Cleaned" swapped in the cleaned text in place; "Raw" swapped back. (Synthetic ⌃⌥R cannot reach the Carbon shortcut.) |
| F4 | Pass | "Paste cleaned text and warn": cleaned pasted, HUD "Check — cleanup dropped “not” · ⌃⌥R pastes raw". |
| F5 | Pass | Off: plain "Done (Document)", history row still tagged "check". |
| F6 | Pass | "at three, no, I mean four" → "at 4", no issue. |
| F7 | Pass | "3 giờ" ↔ "ba giờ" either way, no issue. |
| F8 | Pass | Tag tooltip "Cleanup changed / dropped “not”"; swap button on a raw row pasted the cleaned version into TextEdit. |

## Spanish

| # | Result | Evidence |
|---|---|---|
| 1 | Pass | ES in Settings switch, popover switch, per-app picker. |
| 2 | Pass (transcription only) | ES switch: Spanish text, language es. Filler removal not testable: the owner has cleanup off (`cleanupEnabled=false`, history `rawReason: cleanupOff`). A second Eddy clip through the speakers came out garbled. |
| 3 | Pass | Shift taps while recording: HUD EN → VI → ES → Auto. |
| 4 | Not run | Scratchpad mic / meeting My notes. |
| 5 | Pass | Auto detected es. Popover redo offers English, then Vietnamese. |
| 6 | Pass | Untick Spanish with switch on ES: switch → Auto; Ghostty rule still shows Spanish. |
| 7 | Not run | Shortcuts app action. |

## Usability

| # | Result | Evidence |
|---|---|---|
| U1 | Pass after relaunch | With Keyboard navigation on (BugVoice relaunched), Tab reaches sidebar, tabs and every General and Models control in reading order with a focus ring. Without a relaunch Tab only toggled the search field. |
| U2 | Partial | History rows, Retry, swap buttons read their names; status reads "Reachable · 1 model". **Unlabeled:** Models tab pop-ups (connection, Thinking, time limit) and model-name text fields have no AX label, so VoiceOver reads only the value. Retry-language menu button still has AXDescription "go down". |

## Updates and backup

| # | Result | Evidence |
|---|---|---|
| Updates 1 | Pass | "Up to date. The newest release is 0.1.0-build.343." (feed is at 343). |
| Updates 6 | Pass | App menu and popover Tools › Check for Updates… both open Settings › General with the result. |
| Updates 2–5 | Not run | Need a newer feed build, Wi‑Fi off, theme sweep. |
| B2 | Pass | Save into the data folder: "Choose a folder outside the BugVoice data folder.", no file written. |
| B3 | Pass | Word typed into a new note right before Back up now is in `data/Notes/untitled-14.md` of the archive; no credentials file in it. |
| B4 | Not run | 8 MB backup finishes before Cancel can be pressed. |
| B10 | Pass | Meeting recording, Restore… → file → "Restore and relaunch": "A meeting is recording. Stop the meeting first." (the confirmation sheet still appears first). |

## Other findings

- Retry-language menu in Needs attention renders as a wide empty bar with only a chevron (no label), stretching across the row.
- After a fresh launch, if the first dictation is cancelled, the popover has no Retry (Retry shows only when a last result exists), although the HUD says "Retry last runs it again".
- After Retry of a cancelled dictation, the popover still shows the previous dictation as "Last dictation".
- History rows with a fidelity tag indent their text further than other rows.
- Orca screenshots of a background BugVoice window miss the search results overlay; `screencapture -l <window>` shows it.
- Meeting text generation leaves its progress bar ("Combining results", full) on screen after the text is saved: `MeetingsPage.swift` `generate(_:)` resets `generationProgress` only at the start, never on success.
- Saving a transcript line without changing it marks it "Edited" (editedText equals text).
- Scratchpad Ask: "Run again" after an Ask failure does nothing for Ask (no ask log line).

## Fixes after the run (uncommitted)

- **Ask "could not read the model's answer":** reproduced through the MCP `ask` tool with a logging proxy. Qwen3.8-27B on oMLX replied with one stray closing bracket after the JSON object (`...]}}`, `...]}]`) and listed citations as bare strings (`["P1.7"]`). `AskAnswerPrompt.parse` (and `AskQueryPrompt.parse`) now read the first balanced JSON object (`ModelJSON.object`) and accept bare-string citations. After the fix, both questions that failed were answered with citations.
- **Progress bar stuck after generation:** `MeetingsPage.generate(_:)` now hides the bar when the run ends and drops progress updates from an ended run. Checked in the dev build: the bar showed during Regenerate and was gone afterwards.

## Findings fixed (branch fix/device-check-bugs)

- Review 12 intermittent copy: the field check now also matches app, role, subrole and screen frame when the accessibility reference changes (`FocusFingerprint`). Not reproduced on demand, so owner check: same-field dictations in Chrome right after a page reload should paste. The log line "field check: new reference …" shows when the fallback decided.
- Review 6 dot colour: not a bug. The readiness spec makes a connection error amber; the handoff checklist now says amber.
- Saving an unchanged transcript line no longer marks it Edited; typing the original back clears the edit.
- A dictation recovered after a quit is titled "Dictation did not finish", not "Transcription failed".
- Retry-language menu: sized to its icon, VoiceOver reads "Choose a retry language".
- History rows: one first-column width, tags on their own line, so text lines up.
- Models tab and Search card pickers and model-name fields have VoiceOver names.
- Menu: after a cancelled first dictation, "Retry cancelled dictation" appears.
- Not changed: "Last dictation stale after Retry" (the code records the retried result; most likely read before the retry finished) and Scratchpad "Run again" after Ask (it repeats the last rewrite, by design).

## Rerun on build 388 (2026-11-03)

Installed build 388 (`8f55801`) to /Applications. Pastes went into a local test page in Chrome on the second display; nothing was pasted into the owner's apps.

| Check | Result | Evidence |
|---|---|---|
| Retry cancelled dictation | Pass | Fresh launch, Esc during Transcribing (`outcome=cancelled`), popover shows "Retry cancelled dictation"; pressing it pasted the clip into Chrome (`outcome=inserted`). With a last result the row is "Retry", which also pasted. |
| Chrome same-field paste after reload | Pass | Reload before dictating: 3/3 pasted. Reload during recording: 3/3 pasted, log "field check: new reference, same app, role and frame; treated as the same field". Clicking a second field during recording: 3/3 copied (`copiedFieldChanged`); same-field controls pasted. |
| Scratchpad Ask | Pass | "What did the people bot demo show, and what needs to happen next?" answered in 30 s with citations (`ask outcome=answered`, cited=4). |
| Markdown export of an edited line | Pass | Edited the first people-bot line, More › Export › Markdown: the file has the edited text, not the original. Edit reverted afterwards; exported file deleted. |
| Regenerate action items, Interview on a real meeting | Postponed | Owner postponed the remaining tests. |
| Spanish 4 and 7, Updates 2–5, Backup B4 | Postponed | Same. |

Notes:

- TextEdit (running 11 h) took no synthetic keystrokes, BugVoice's or a test tool's, so the checks moved to Chrome. While it lasted, keys typed with Chrome frontmost landed in BugVoice's search field; after quitting and relaunching BugVoice it did not happen again, even after the same popover, Esc and Retry steps. Most likely left over from an AX press on BugVoice's menu bar item during setup. Not reproduced; not treated as a bug.
- In one run of four same-field dictations into Chrome, two logged `inserted` (Chrome asked for the clipboard data) but their text is not in the field or in any other Chrome window. Later runs placed every paste. Not reproduced.
- Esc while recording (not processing) discards the clip without a log line or Retry row; by design, the Retry row follows Esc during Transcribing or Cleaning.

## Real-meeting prompt checks (2026-11-03, build 389, oMLX Qwen3.8-27B)

Run through the app (Meetings › Action items / Summary), not the eval script.

| Check | Result | Evidence |
|---|---|---|
| Action items, people-bot demo (22 min) | Pass | One item: "Share the slide with the diagram", the only task stated in the meeting. 30 s. |
| Action items, 3:44 meeting (questions and fragments, no tasks) | Pass | "No action items in this meeting." 10 s. |
| Interview template, people-bot demo | Pass | "Candidate: Not an interview."; strengths and concerns N/A; topics and follow-ups match the transcript (20-minute expiry, 10-minute reminder, lock, hijack option, one session at a time, employee details shown). Commands are written as `/deactivate [email]`, a format the speaker did not spell out. 70 s. |
| Spanish 4 | Not run | Spanish is not ticked in the owner's dictation languages; Spanish played through the speakers transcribed badly before. |

The generated action item and Interview summary stay on the people-bot meeting; the action item also appears on the Action items page.

## Updates 2–5 against the live feed (2026-11-03, installed build 389, feed 0.1.0-build.390)

The feed's download matches `build/BugVoice-0.1.0-390.dmg` (SHA-256 `04853ec4…bdde6`).

| # | Result | Evidence |
|---|---|---|
| 2 | Pass | Check for Updates…: "BugVoice 0.1.0-build.390 is available. Open shows its release page in your browser.", button "Open 0.1.0-build.390". Menu popover row "BugVoice 0.1.0-build.390 is available" with Open. |
| 3 | Pass | Switch off: `updateNotify` false, menu row gone, still gone after a relaunch. Switch on: row back. |
| 4 | Not run | Turning Wi-Fi off would cut the owner's network while they were at the Mac. |
| 5 | Pass | Light and dark at 160% text: Updates card rows, button and switch title fit. Restored to light, 100%. |

Findings:

- The feed's `release_url` is a direct DMG download, not a release page, so Open starts a download while the copy says "Open shows its release page in your browser." Either point the feed at a page or change the copy.
- At 160% text the sidebar wraps "Dictionary" onto two lines next to its badge.

## Skipped by the owner (2026-11-03)

- Updates 4 (Wi-Fi off): turning Wi-Fi off would end the remote session.
- Spanish 4 and 7: the owner does not speak Spanish; Spanish played through the speakers transcribes badly.
- Backup B4 (cancel during backup): an 8 MB backup finishes before Cancel can be pressed. Cancellation shares the cleanup path covered by `failedZipLeavesNoFile`, and Restore rejects a partial file. Revisit when backups take noticeable time.

## Rerun on dev build 394 (2026-11-05, owner away)

Dev build `build/BugVoice.app` 394 (same code as `main` 758e9a1), real cleanup
model oMLX Qwen3.8-27B. Pastes went into a throwaway Chrome instance (own
`--user-data-dir`) on the second display. Every hotkey hold ran only after a guard
confirmed that window was frontmost and nobody had touched the keyboard or
mouse since the previous run. Settings were restored byte-for-byte from a backup;
clipboard unchanged.

| Check | Result | Evidence |
|---|---|---|
| Fidelity history replay | Pass | 51 entries decoded, 17 checked, 0 flagged (all four kinds 0). |
| F1 (real model) | Pass | "The timeout is fifteen seconds." → "The timeout is 15 seconds.", no issue. |
| F6 (real model, Work style) | Pass | "at three, no, I mean four" → "Let's meet at 4.", no issue. In style Other the correction is not applied ("at three. No, I mean four."): Other's default rules do not ask for it. |
| F7 (real model) | Pass | "họp lúc ba giờ" → "họp lúc 3 giờ", no issue. |
| F2, F4 (real model) | Not forceable | Qwen kept "not" even with a custom Work rule "Always remove the word not", so no issue fires. App logic already passed against the fake model. |
| Same-field paste in Chrome | Pass, 18 of 18 | 12 consecutive same-field dictations (cleanup off) plus the 6 above: every one logged `inserted` and every text is in the field (screenshot). The two missing pastes from build 388 did not recur. |
| U2 labels (Models tab) | Pass | Every picker and model-name field has a name ("Dictation cleanup model", "… thinking", "Dictation time limit", "Embedding model name"…). Only unlabeled buttons are scroll arrows and window controls. |

Findings:

- **Installed app would not launch:** syspolicyd "Terminating process due to
  Gatekeeper rejection". `/Applications/BugVoice.app` (build 390) carried
  `com.apple.quarantine` from the DMG downloaded in Chrome on 2026-11-03 17:38. Every
  update installed from a downloaded DMG will do this (no Developer ID). Cleared with
  `xattr -cr /Applications/BugVoice.app` at the owner's request; app launches.
  Possible follow-up: the update note could tell the owner to run that command.
- With cleanup off, back-to-back dictations into one field are glued without a space
  ("number onesame field…"), and raw Whisper text sometimes lacks capitals and the
  final period.
- The 18 test dictations were removed from history afterwards at the owner's request.
