# BugVoice MCP server — design

Date: 2026-10-17. Roadmap item 6, second half (Ask is the first half, merged on `main`).
Mockup: `docs/design/proposal-mcp.html` (Settings › Agents: off, on with activity, setup copied,
light and dark).

## 1. Why

The owner works in coding agents (Claude Code, Codex, Orca workers) all day. Their meetings,
notes and dictations sit in BugVoice. Today, getting a decision from last week's call into an
agent means opening BugVoice, finding it, copying text and pasting it. The owner wants agents to
reach BugVoice directly:

- read and search notes and meetings, and ask questions the way Ask AI does, with a scope (a
  folder or everything);
- create and edit notes (for example, save a plan the agent wrote);
- upload an audio or video file, have it transcribed, then ask for a summary or ask questions
  about it.

Success: in Claude Code the owner says "what did we decide about the people bot in the last two
weeks, write it into a BugVoice note", and the agent calls `ask`, then `create_note`, and the note
appears in Scratchpad with the cited lines. An agent can hand BugVoice a recording path and later
read its transcript and summary without the owner touching the app.

## 2. Scope

In scope:

- An MCP server over stdio, started by the agent: `BugVoice.app/Contents/MacOS/bugvoice-mcp`.
- Tools (section 5): `list_folders`, `list_notes`, `get_note`, `list_meetings`, `get_meeting`,
  `search`, `ask`, `create_note`, `edit_note`, `upload_audio`, `get_job`, `summarize_meeting`.
- Settings › Agents: on/off, permission switches, setup commands to copy, recent activity.

Not in scope:

- MCP resources, prompts, sampling and notifications. Tools only.
- Deleting notes, meetings or folders, or moving anything to the Trash.
- Editing meetings (transcript, speakers, title) other than saving a generated summary or action
  items.
- Audio sent to agents. Agents get text only.
- Dictation as a tool (agents cannot start the microphone or recording).
- Remote access: HTTP, a network port, or other users on the Mac.
- `bugvoice://` links from agent output back into the app (later).

Anti-goals:

- An agent edit that overwrites typing the owner has not saved yet.
- Anything reachable from another machine or another macOS user.
- Agents connecting without the owner turning MCP on.
- Dictation or recording getting slower because an agent is busy.

## 3. Privacy

MCP is off by default. Turning it on is the owner's choice to let connected agents read notes,
meetings and dictations. Those agents send what they read to their own model provider (for
Claude Code, Anthropic). The Settings card says so in plain words (mockup). BugVoice itself sends
nothing new off the Mac: `ask` and `summarize_meeting` use the Notes and Meetings models the
owner already chose.

Logs carry tool names, counts and timings only, never arguments, note text or results (same rule
as Ask).

## 4. How it runs

```
agent ──stdio (MCP, JSON-RPC 2.0)──▶ bugvoice-mcp ──Unix socket──▶ BugVoice.app (MCPService)
```

- **Bridge (`bugvoice-mcp`)**: a new executable target, Foundation and Darwin only, copied into
  `Contents/MacOS/` by `Scripts/build-app.sh` and signed with the app. It reads newline-delimited
  JSON-RPC messages on stdin and writes responses on stdout (MCP stdio transport). It answers
  `initialize`, `notifications/initialized`, `ping` and `tools/list` itself, and forwards each
  `tools/call` to the app. Nothing is written to stdout except protocol messages; diagnostics go
  to stderr.
- **Protocol version**: the bridge accepts `2025-06-18`, `2025-03-26` and `2024-11-05`. It replies
  with the client's version when it is one of these, otherwise `2025-06-18`. Server info:
  `{"name": "bugvoice", "version": <CFBundleShortVersionString>}`. Capabilities: `{"tools": {}}`.
- **Socket**: `~/Library/Application Support/BugVoice/MCP/bugvoice.sock`. The `MCP` folder is
  0700, the socket 0600. The app listens whenever it is running, MCP on or off, so the bridge can
  tell "off" from "not running"; with MCP off, every tool call gets the "MCP is off" error. On each connection the app checks
  the peer's user id (`getpeereid`) equals its own and closes the connection otherwise.
- **Dev and installed builds** share one data folder and one socket: the bridge talks to
  whichever BugVoice is running (decided: the dev build is only for testing).
- **App not running**: when the socket is missing or refuses connections, the bridge launches the app it lives in
  (`open -g -a <bundle>`; `-g` keeps it in the background) and waits up to 20 s for the socket.
  If the app is running with MCP off, every tool call returns the error "MCP is off. Turn it on in
  BugVoice Settings › Agents." `initialize` and `tools/list` still work, so the agent sees the
  tools.
- **Wire between bridge and app**: one JSON object per line, `{"id", "tool", "arguments",
  "client"}` → `{"id", "content"|"error"}`. `client` is `clientInfo.name` from `initialize`
  (for the activity list).
- **Shared code**: tool definitions (names, descriptions, JSON input schemas), argument checking
  and result formatting live in `VoiceCore/MCP/` (Foundation only, TDD). The bridge and the app
  both use them. The app-side work (`MCPService` in `Sources/BugVoice`) goes through the same
  code paths as the app's own buttons: `NotesController`, `UploadController`, `SearchIndexer`,
  `AppModel.askAcross`, `AppModel.generateMeetingText`.
- **Concurrency**: up to 4 bridge connections at once. `ask` and `summarize_meeting` run one at a
  time across all connections (queued, each with its own time limit); reads run in parallel.
- **Dictation first**: tool calls never pause dictation or recording. `ask`, `summarize_meeting`
  and indexing already yield as Ask does; `upload_audio` uses the Upload queue, which already
  waits for a meeting to end.

## 5. Tools

All ids are the app's own (`NoteID`, `MeetingID`, `FolderID` raw values). Dates are ISO 8601 with
the local offset. Results are one `text` content item holding JSON (agents read it as text),
except `get_note` and `get_meeting`, which return readable Markdown. Errors are tool results with
`isError: true` and one plain sentence.

### Scope

`search` and `ask` take `scope`, a string:

| Value | Means | Same as Ask scope |
|---|---|---|
| `all` (default) | every note, meeting, upload and dictation | All notes and meetings |
| `folder:<id or name>` | notes and meetings in that folder (name matched case-insensitively) | This folder |
| `unfiled` | notes and meetings with no folder | Unfiled notes and meetings |
| `meeting:<id>` | one meeting or upload | A meeting… |
| `note:<id>` | one note | This note (read-only here: never CHANGE) |

An unknown folder name or id: "No folder named Roadmap. Folders: Work, Personal." (lists names).

### Read

| Tool | Arguments | Returns |
|---|---|---|
| `list_folders` | — | `[{id, name, notes, meetings}]` |
| `list_notes` | `folder?`, `tag?`, `text?` (title contains, folded), `limit?` (default 50, max 200) | newest modified first: `[{id, title, folder, tags, modified, words}]` |
| `get_note` | `id` | Markdown: `# Title`, a line with folder, tags, modified, then the body as saved on disk. When the open editor has unsaved changes, those are included and the header says "Unsaved changes included." |
| `list_meetings` | `folder?`, `tag?`, `from?`, `to?` (dates), `text?`, `limit?` (50, max 200) | newest first: `[{id, title, started, duration_seconds, kind: recorded/uploaded, people, has_summary, has_action_items, state}]` |
| `get_meeting` | `id`, `parts?` (any of `summary`, `action_items`, `my_notes`, `transcript`; default all), `from_line?` (default 1) | Markdown: title, date, people; Summary; Action items; My notes; Transcript as `[mm:ss] Speaker: text` lines, with the English translation under a line when one is saved. At most 1,500 transcript lines per call; when cut, the last line says "More: call get_meeting with from_line 1501." |
| `search` | `query`, `scope?`, `limit?` (default 20, max 40) | passages ranked as Ask ranks them (word search plus meaning search when the index is usable; no model call): `[{item_id, item_kind, title, date, start?, end?, speaker?, text}]`, plus `word_search_only: true` when meaning search was not used |
| `ask` | `question`, `scope?` | runs the Ask pipeline: `{answer, cards: [{item_id, item_kind, title, date, people, citations: [{start?, end?, speaker?, quote}]}], searched: {meetings, notes, dictations}, word_search_only?}` or `{nothing_found: true}`. Time limit 120 s, as in the app. History is empty (each call stands alone). |

`search` uses `AskQueryPrompt.fallback` terms (question words, stop words removed) and the
embedding of the query; it is fast and needs no Notes model. `ask` needs the Notes model; when
none is set: "Choose a Notes model in BugVoice Settings › Models."

### Write (Settings switch "Agents can create and edit notes")

| Tool | Arguments | Returns |
|---|---|---|
| `create_note` | `title`, `body` (Markdown), `folder?` (id or name), `tags?` | `{id, title}`. The note appears in the Scratchpad list; the window is not opened or focused. |
| `edit_note` | `id`, `body`, `mode` (`replace` or `append`), `title?`, `folder?`, `tags?` | `{id, modified}`. `append` adds a blank line and the text at the end. |

`edit_note` is refused, with nothing changed, when:

- the note has unsaved changes in the editor: "This note has unsaved changes in BugVoice. Try
  again after it saves." (`NotesController` state is dirty, a title draft differs, or an external
  change is waiting);
- dictation is inserting into that note right now: "BugVoice is dictating into this note. Try
  again in a moment."

A successful edit saves through `NotesController`, so an open editor reloads the new text and its
undo history gets one "Agent edit" step.

### Upload (Settings switch "Agents can upload recordings")

| Tool | Arguments | Returns |
|---|---|---|
| `upload_audio` | `path` (absolute), `title?`, `folder?`, `tags?` | `{job_id}`. Checks: file exists, is readable, extension is one the Upload page accepts (MP3, WAV, M4A, AIFF, CAF, MP4, MOV, M4V). Adds the file to the Upload queue as the Upload page's Transcribe button does; the queue copies what it needs, the original file is never changed or deleted. |
| `get_job` | `job_id` (survives a BugVoice restart: see below) | `{state: queued/reading/transcribing/finding_speakers/ready/failed/cancelled, progress: 0–1?, meeting_id?, error?}` |
| `summarize_meeting` | `id`, `kind` (`summary` or `action_items`), `replace?` (default false) | When the meeting already has that text and `replace` is false, returns it unchanged. Otherwise generates with the Meetings model, saves it on the meeting (as "Generate summary" does) and returns the text. Allowed whenever MCP is on, with no write switch: it only adds generated text the owner can regenerate. |

Uploads by agents show in the Upload page like any other, with "Added by <client>" under the file
name.

Job ids survive a restart (the bridge may relaunch the app between `upload_audio` and `get_job`):
the job id is saved on the upload's `MeetingManifest` together with the client name (two new
optional fields), and recovery after a relaunch keeps both. `get_job` finds a job by that id.

`summarize_meeting` waits for the result (no job), with a 300 s limit. When the app is already
writing that meeting's summary or action items, it returns "BugVoice is already writing this
meeting's summary. Try again in a minute."

`create_note` uses a new `NotesController` entry point that saves the note without selecting it
or touching the owner's open note.

## 6. Settings › Agents

A new Settings tab, "Agents", after Models (mockup). Contents:

- **MCP server** switch. Below it: "Lets coding agents on this Mac, such as Claude Code and Codex,
  read and search your notes, meetings and dictations. Agents send what they read to their own
  model provider."
- **Agents can create and edit notes** switch (default on).
- **Agents can upload recordings** switch (default on).
- **Set up an agent**: two rows, each with the command and a Copy button.
  - Claude Code: `claude mcp add bugvoice -- <path>/bugvoice-mcp`
  - Codex: the lines for `~/.codex/config.toml`:
    ```
    [mcp_servers.bugvoice]
    command = "<path>/bugvoice-mcp"
    tool_timeout_sec = 300
    ```
    (Codex stops a tool call after 60 s by default; `ask` can take up to 120 s and
    `summarize_meeting` up to 300 s.)
  - `<path>` is the running app's `Contents/MacOS`, so it is correct for `/Applications` and for
    the dev build.
- **Recent activity**: the last 20 calls since launch: time, client name, tool, OK or the error
  sentence. No arguments or results. Kept in memory only. Empty: "No agent has connected yet."
- Status line under the switch: "Listening" / "Off" / "Could not start: <reason>".

Turning MCP off keeps the socket but refuses tool calls; connected bridges get the "MCP is off"
error.

## 7. Errors (plain sentences, returned as tool errors)

| Case | Text |
|---|---|
| MCP off | MCP is off. Turn it on in BugVoice Settings › Agents. |
| Write switch off | Creating and editing notes is turned off in BugVoice Settings › Agents. |
| Upload switch off | Uploading is turned off in BugVoice Settings › Agents. |
| App did not start in 20 s | BugVoice did not start. Open it and try again. |
| Unknown id | No note with id …. / No meeting with id …. / No upload job with id …. |
| Bad argument | `<name>` must be …. (from the schema check, before reaching the app) |
| File problems | File not found: …. / File type not supported: .xyz. Supported: … |
| Ask failures | the Ask failure texts from the Ask spec section 9 |
| Connection lost after a write was sent (not retried) | BugVoice closed the connection before answering. Check BugVoice before you try again. |
| Reply over the size limit (3,500,000 bytes) | `get_note`: More: this note is longer than an agent reply can hold. Open it in BugVoice. Other tools: More: this reply is longer than an agent reply can hold. Open it in BugVoice. |
| Summary failed | Could not write the summary. Try again. |
| Summary over 300 s | Writing the summary took longer than 5 minutes. Try again. |
| Another BugVoice already listens (Settings status) | Could not start: another BugVoice is answering agents. |

Agent uploads waiting in the queue are saved in `MCP/agent-uploads.json` (0600) so `get_job` survives
a restart before the job starts; finished entries older than 7 days are dropped. If that file
cannot be written, the app shows "Could not save the agent upload list: <reason>". Read-only tools
are retried once after a lost connection; write tools are retried only when the request was never
sent.

## 8. Constraints

- No new package dependency. JSON-RPC and the socket are written with Foundation and Darwin.
- `VoiceCore` stays Foundation-only; TDD for everything added there.
- The bridge is small: no WhisperKit, no app frameworks; it must start in under 100 ms.
- Build with `Scripts/build-app.sh` (adds the bridge to the bundle and signs it with the
  `Bugler Local Dev` identity).
- UI copy: plain English, no hedging words, no emoji.

## 9. Left to the builder

- How `MCPService` maps tools onto existing controllers (small public entry points may be added,
  for example a programmatic Upload submit that skips the drafts UI).
- The socket server's threading, as long as tool work runs on the app's actors as the buttons do.
- Exact JSON schema wording for tool descriptions (short, plain, one sentence each).
- Tests: VoiceCore protocol and schema tests; a bridge test that runs the binary with stdin/stdout
  pipes against a fake socket server; app-side tests where `BugVoiceMacTests` can reach.
