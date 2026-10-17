# MCP server — execution and maintainer checks

Built 2026-10-17. Spec: [MCP server design](../superpowers/specs/2026-10-17-mcp-server-design.md).
Plan: [MCP server plan](../superpowers/plans/2026-10-17-mcp-server.md).
Mockup: [Settings › Agents](../design/proposal-mcp.html).

The app was **not launched**. No owner Application Support data, settings or
credentials were read or edited; socket tests use short folders under `/tmp`.
The bridge was run once from the built bundle with `initialize` and `tools/list`
only (two JSON lines, 12 tools, about 10 ms); those two never connect, so the
app did not start. Every row below is pending. Unit tests and signed builds do
not mark them passed.

## Automated evidence

| Task | Commit | `swift test` | `Scripts/build-app.sh` |
|---|---|---|---|
| 1 | `feat(core): MCP protocol, tool list and argument checks` | 824 VoiceCore / 88 suites; 84 BugVoiceMac / 16 suites | not required |
| 2 | `feat(core): MCP results, agent settings and Ask search` | 840 VoiceCore / 90 suites; 84 BugVoiceMac / 16 suites | not required |
| 3 | `feat(mcp): local socket server and client` | 840 / 90; 19 MCPKit / 1 suite; 84 / 16 | not required |
| 4 | `feat(mcp): bugvoice-mcp stdio bridge` | 840 / 90; 30 MCPKit / 2 suites; 84 / 16 | exit 0; `codesign --verify --strict` passes; stdin pipe check passes |
| 5 | `feat(app): note create and edit entry points for agents` | 840 / 90; 30 / 2; 93 BugVoiceMac / 16 | not required |
| 6 | `feat(app): MCP service with read, search, ask and summary tools` | 849 / 92; 30 / 2; 93 / 16 | exit 0 |
| 7 | `feat(app): MCP note writing and uploads` | 856 / 93; 30 / 2; 93 / 16 | exit 0 |
| 8 | `feat(app): Settings Agents tab for the MCP server` | 856 / 93; 30 / 2; 93 / 16 | exit 0 |

## Manual checks — all pending

Run on the dev build (`Scripts/run-dev-app.sh`) unless a row says otherwise. Use
a disposable test note, a disposable test meeting and a short recording made with
`say -o /tmp/bv-mcp-test.aiff "testing the people bot"`. Delete them afterwards
through the app's own Trash actions.

| # | Check | Expected | Result |
|---|---|---|---|
| 1 | Open Settings › Agents with MCP off (fresh settings). | State 1 of the mockup: switch off, status "Off", both permission switches greyed out, no setup or activity cards. | Pending |
| 2 | Turn MCP on with no agent connected. | Status "Listening"; setup card and "No agent has connected yet." appear (state 3). | Pending |
| 3 | After a few calls, look at Recent activity. | Rows show `HH:mm`, client, tool, "OK" or the error sentence; newest first; at most 20; no arguments or results. Light and dark modes. | Pending |
| 4 | Click Copy on the Claude Code row, then on the Codex row. | The button reads "Copied" for 2 s; the clipboard holds the command or the three TOML lines with `tool_timeout_sec = 300`; the path is the running app's `Contents/MacOS/bugvoice-mcp`. | Pending |
| 5 | Run the copied `claude mcp add` command, start Claude Code, list tools, then ask "what did we decide about the people bot in the last two weeks". | 12 BugVoice tools are listed; the agent calls `ask` and gets an answer with cards. | Pending |
| 6 | In the same Claude Code session, ask it to write the answer into a BugVoice note. | `create_note` succeeds; the note appears in the Scratchpad list; no window opens or takes focus. | Pending |
| 7 | Add the Codex lines to `~/.codex/config.toml`, start Codex and call `list_meetings`. | Tools load; a call runs; an `ask` taking over 60 s is not cut off. | Pending |
| 8 | Call `list_folders`, `list_notes {"limit":2}` and `get_note` on the test note. | Folder counts match the app; notes newest edited first; `get_note` returns `# Title`, the header line and the body. | Pending |
| 9 | Type in the test note without waiting for the save, then call `get_note`. | The header ends with "Unsaved changes included." and the body has the typed text. | Pending |
| 10 | Call `list_meetings {"from":"<a week ago>"}` and `get_meeting` on a long meeting. | Kinds `recorded`/`uploaded`, people in speaking order; transcript lines `[m:ss] Speaker: text`, English lines under translated ones; past 1,500 lines the last line names the next `from_line`. | Pending |
| 11 | Call `search {"query":"bot"}`, then with `scope` set to a folder name in another case or without diacritics. | Passages return without a Notes model call; the folder resolves; `word_search_only` appears when the Search model is off. | Pending |
| 12 | Call `ask` with `scope` `meeting:<id>` and `note:<id>`. | Answers cite only that item; the note is not changed. | Pending |
| 13 | Call `summarize_meeting` on a meeting with a summary, then with `"replace": true`. | First call returns the saved text unchanged; the second writes, saves and returns a new summary visible in Meetings. | Pending |
| 14 | Call `edit_note` with `mode` `append`, then `replace`, on the test note while it is open in the Scratchpad window. | The open editor shows the new text; ⌘Z undoes one "Agent edit" step. | Pending |
| 15 | `upload_audio` the `say` recording, then `get_job` until `ready`, then `get_meeting` on the `meeting_id`. | States move queued → reading → transcribing → (finding_speakers) → ready; the Upload page row shows "Added by <client>"; the source file is unchanged. | Pending |
| 16 | Error sentence: turn MCP off with the app running, then call any tool. | "MCP is off. Turn it on in BugVoice Settings › Agents." `tools/list` still works. | Pending |
| 17 | Error sentence: turn off "Agents can create and edit notes", call `create_note`. | "Creating and editing notes is turned off in BugVoice Settings › Agents." | Pending |
| 18 | Error sentence: turn off "Agents can upload recordings", call `upload_audio`. | "Uploading is turned off in BugVoice Settings › Agents." | Pending |
| 19 | Error sentence: quit BugVoice, rename it so it cannot open, call a tool from the bridge. | After 20 s: "BugVoice did not start. Open it and try again." | Pending |
| 20 | Error sentences: `get_note`, `get_meeting` and `get_job` with made-up ids. | "No note with id …." / "No meeting with id …." / "No upload job with id …." | Pending |
| 21 | Error sentence: `search` without `query`. | "query must be a non-empty string." and the app's activity list shows nothing for it (rejected in the bridge). | Pending |
| 22 | Error sentences: `upload_audio` with a missing path and with a `.txt` file. | "File not found: <path>." / "File type not supported: .txt. Supported: MP3, WAV, M4A, AIFF, CAF, MP4, MOV, M4V." | Pending |
| 23 | Error sentence: `ask` with no Notes model set. | "Choose a Notes model in BugVoice Settings › Models." | Pending |
| 24 | Error sentence: start Generate summary in the app, then call `summarize_meeting` with `replace` on the same meeting. | "BugVoice is already writing this meeting's summary. Try again in a minute." | Pending |
| 25 | Review Focus 1: type in the test note and immediately call `edit_note`. | "This note has unsaved changes in BugVoice. Try again after it saves."; the typed text and the file are unchanged. | Pending |
| 26 | Review Focus 1b: start Notes dictation into the test note and call `edit_note` while it runs. | "BugVoice is dictating into this note. Try again in a moment."; after the dictation lands, the same call succeeds. | Pending |
| 27 | Review Focus 2: quit BugVoice, then call a tool. | The bridge opens BugVoice once in the background (`open -g`), waits, and the call succeeds; dictation keeps working. | Pending |
| 28 | Review Focus 3: as another macOS user, connect to the socket (or check `ls -l` of `~/Library/Application Support/BugVoice/MCP`). | Folder is `drwx------`, socket `srw-------`; a foreign connection is closed. The app keeps running. | Pending |
| 29 | Review Focus 3b: `nc -U` the socket and send `nope`, then a 5 MB line. | `{"id":"","isError":true,"text":"Bad request."}`; the long line closes the connection; the app keeps running and serves new bridges. | Pending |
| 30 | Review Focus 4: `upload_audio` a long file, quit BugVoice mid-transcription, relaunch, call `get_job` with the same id. | The job is found (state `transcribing` or later) and reaches `ready`. | Pending |
| 31 | Review Focus 5: `list_notes {"folder":"lo trinh"}` with a folder named "Lộ trình", then an unknown folder name. | The folder resolves; the unknown name returns "No folder named …. Folders: …." listing real names. | Pending |
| 32 | Run the installed `/Applications/BugVoice.app` and the dev build in turn with one agent configured. | Both use the same socket; the bridge reaches whichever is running. | Pending |
| 33 | Hold Right Option and dictate while an agent's `ask` and `summarize_meeting` run. | Dictation is not slower; two `ask` calls from two agents run one after the other. | Pending |
| 34 | Run `Console.app` filtered on subsystem `com.kael.bugvoice`, category `mcp`, during a few calls. | One line per call with tool, client, seconds and ok; no arguments, note text, questions or results. | Pending |

## Implementation choices not fixed by the plan

- Tool errors use a small `MCPFailure` type (`message`) in VoiceCore where the
  plan wrote `Result<…, String>`, because `String` is not an `Error`.
  `MCPFormat.askResult` takes the corpus counts as extra arguments so `searched`
  can be filled.
- Argument errors read "`<name>` must be …." without backticks, for example
  "query must be a non-empty string.". Limits above the maximum are clamped;
  below 1 is an error. An empty `parts` list means all parts. `list_meetings`
  dates take `YYYY-MM-DD` (local day; `to` includes the whole day) or full ISO 8601.
- Transcript times use the app's `m:ss` (`[1:23]`), `h:mm:ss` from one hour.
- `search` returns `{"passages": [...], "word_search_only": true?}`; `item_kind`
  is `meeting`, `upload`, `note` or `dictation`; dictation passages carry no speaker.
- The bridge answers requests concurrently (a ping is answered during an `ask`)
  and, after a dropped connection, retries a call once only when the request was
  never written or the tool only reads (`list_*`, `get_*`, `search`, `ask`).
  `create_note`, `edit_note`, `upload_audio` and `summarize_meeting` are never sent
  twice: a connection lost after the write reads "BugVoice closed the connection
  before answering. Check BugVoice before you try again."; a second failure reads
  "BugVoice closed the connection. Try again."
- Every reply is kept under 3,500,000 UTF-8 bytes: list tools drop rows from the
  end, `get_note` is cut at a line and ends "More: this note is longer than an
  agent reply can hold. Open it in BugVoice.", other tools end "More: this reply
  is longer than an agent reply can hold. Open it in BugVoice."
- The socket server does not remove a socket that answers: a second BugVoice shows
  "Could not start: another BugVoice is answering agents." and leaves the first
  one serving; `stop()` removes the socket only if it is still the one it made.
- Agent uploads are saved in `MCP/agent-uploads.json` (0600) on submit and on each
  state change. At launch, `queued` (and cut-short `reading`) jobs whose file is
  still there are queued again under the same id; a missing file fails with "File
  not found: <path>.". Finished entries are dropped after 7 days. `get_job` checks
  the queue, then this file, then saved meetings.
- `ask` and `summarize_meeting` check that MCP is still on after waiting their turn.
- `summarize_meeting` reports "BugVoice is already writing this meeting's summary."
  only when the app is writing that meeting's text; other stops read "Could not
  write the summary. Try again." The 5-minute limit returns on time even if the
  model does not stop.
- Dictation captures are counted per note in `NotesController` and released by
  `DictationController` when the run is inserted, cancelled or fails to start.
- Appending to an empty note stores only the new text.
- Extra sentences: "This meeting has no transcript yet.", "Writing the summary took
  longer than 5 minutes. Try again.", "Could not save the agent upload list: <reason>", "BugVoice is still starting. Try again in a
  moment." (Upload queue not yet accepting), "question must be at most 1000 characters.".
- A retried agent upload keeps its job id unless the failed job is still listed
  in the queue, in which case the retry gets a new id.
- `MCPService` stops the socket in `applicationWillTerminate`.
