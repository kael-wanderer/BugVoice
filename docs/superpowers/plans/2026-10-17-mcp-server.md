# BugVoice MCP Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let coding agents on this Mac read, search, ask, write notes and upload recordings in BugVoice through a local MCP server.

**Architecture:** A small stdio executable, `bugvoice-mcp`, speaks MCP (JSON-RPC 2.0, newline-delimited) to the agent. It answers the handshake and tool list itself and forwards each tool call over a private Unix socket to the running app, where `MCPService` runs it through the same controllers the app's own buttons use. Protocol types, tool schemas, argument checking and result formatting are Foundation-only code in `VoiceCore/MCP/`; socket and bridge code is a new Foundation+Darwin target `MCPKit`.

**Tech Stack:** Swift 6.4 (tools 6.0), macOS 15, Swift Testing, Foundation, Darwin sockets, SwiftUI for Settings.

**Spec:** `docs/superpowers/specs/2026-10-17-mcp-server-design.md` (mockup `docs/design/proposal-mcp.html`). The spec is the authority; read it before any task.

## Global Constraints

- No new package dependency. JSON-RPC and sockets use Foundation and Darwin only.
- `VoiceCore` imports Foundation only. TDD for everything in `VoiceCore` and `MCPKit`: failing test first. `swift test` passes before every commit.
- `MCPKit` imports Foundation and Darwin only (no AppKit, no WhisperKit, no VoiceCore UI code). The bridge must start in under 100 ms.
- Build only with `Scripts/build-app.sh` (Bugler Local Dev signing). Never sign ad hoc.
- Socket: `~/Library/Application Support/BugVoice/MCP/bugvoice.sock`; folder 0700, socket 0600; peer uid must equal own uid (`getpeereid`).
- Protocol versions accepted: `2025-06-18`, `2025-03-26`, `2024-11-05`; reply with the client's when accepted, else `2025-06-18`. Server info `{"name": "bugvoice", "version": <CFBundleShortVersionString>}`, capabilities `{"tools": {}}`.
- Never log tool arguments, note text, transcripts, questions or results. Logs and the activity list carry tool name, client name, time, OK or the error sentence only.
- Never touch the owner's data in tests: every test uses a temp directory.
- UI copy and error sentences are copied verbatim from the spec (sections 5–7). Plain English, no hedging, no emoji.
- Commit after each task: `feat(core): …`, `feat(mcp): …`, `feat(app): …`, `docs: …`, ending with the harness co-author line.

## Review Focus

1. **An agent edit while the owner is typing in that note** must be refused and change nothing (Task 5 test `agentEditRefusedWhileDirty`).
2. **A bridge started while BugVoice is closed** must launch the app once, wait up to 20 s, then forward; if the app never appears, return "BugVoice did not start. Open it and try again." (Task 4 tests `launchesAppWhenSocketMissing`, `reportsDidNotStart`).
3. **A connection from another macOS user or with a bad line** (not JSON, over 4 MB) must be closed or answered with a JSON-RPC error without crashing the app (Task 3 tests `rejectsForeignPeer` via injected uid check, `oversizeLineClosesConnection`).
4. **`get_job` after the app restarted mid-upload** must still find the job by id through the meeting manifest (Task 2 test `manifestKeepsUploadJobFields`, Task 7 manual check).
5. **A folder given by name with different case or diacritics** ("roadmap", "Lộ trình" vs "lo trinh") must resolve the same folder; an unknown name lists the real folder names (Task 1 test `folderScopeParses`, Task 6 `MCPResolve` test).

---

### Task 1: MCP protocol, tool definitions and argument checking (VoiceCore)

**Files:**
- Create: `Sources/VoiceCore/MCP/JSONValue.swift`, `Sources/VoiceCore/MCP/MCPProtocol.swift`, `Sources/VoiceCore/MCP/MCPTools.swift`
- Test: `Tests/VoiceCoreTests/MCPProtocolTests.swift`, `Tests/VoiceCoreTests/MCPToolsTests.swift`

**Interfaces:**
- Produces:
  - `public indirect enum JSONValue: Codable, Equatable, Sendable { case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue]) }` with subscripts `[String] -> JSONValue?`, accessors `stringValue`, `intValue`, `boolValue`, `arrayValue`, `objectValue`, and `func encodedLine() -> Data` (compact JSON, sorted keys, no newline inside, `\n` appended).
  - `public struct JSONRPCMessage: Equatable, Sendable { var id: JSONValue?; var method: String?; var params: JSONValue?; var result: JSONValue?; var error: JSONRPCError? }` with `static func parse(_ line: Data) -> Result<JSONRPCMessage, JSONRPCError>` and `func encodedLine() -> Data`.
  - `public struct JSONRPCError: Error, Equatable, Sendable { var code: Int; var message: String }` with `static let parse = -32700, invalidRequest = -32600, methodNotFound = -32601, invalidParams = -32602`.
  - `public enum MCPProtocol { static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]; static func negotiate(_ requested: String?) -> String; static func initializeResult(version: String, appVersion: String) -> JSONValue; static func toolResult(text: String, isError: Bool) -> JSONValue }`
  - `public enum MCPTool: String, CaseIterable, Sendable { case listFolders = "list_folders", listNotes = "list_notes", getNote = "get_note", listMeetings = "list_meetings", getMeeting = "get_meeting", search, ask, createNote = "create_note", editNote = "edit_note", uploadAudio = "upload_audio", getJob = "get_job", summarizeMeeting = "summarize_meeting" }`
  - `public enum MCPTools { static var definitions: JSONValue /* the tools/list result */ ; static func check(_ name: String, _ arguments: JSONValue?) -> Result<MCPCall, MCPArgumentError> }`
  - `public enum MCPScopeArgument: Equatable, Sendable { case all, unfiled, folder(String), meeting(String), note(String) }` with `static func parse(_ s: String?) -> MCPScopeArgument?` (nil string → `.all`; unknown prefix → nil).
  - `public enum MCPCall: Equatable, Sendable` with one case per tool carrying typed, defaulted arguments (for example `case listNotes(folder: String?, tag: String?, text: String?, limit: Int)`, `case search(query: String, scope: MCPScopeArgument, limit: Int)`, `case editNote(id: String, body: String, mode: MCPEditMode, title: String?, folder: String?, tags: [String]?)`, `case summarizeMeeting(id: String, kind: MCPTextKind, replace: Bool)`). `MCPEditMode { replace, append }`, `MCPTextKind { summary, actionItems = "action_items" }`, `MCPMeetingPart { summary, actionItems = "action_items", myNotes = "my_notes", transcript }`.
  - `public struct MCPArgumentError: Error, Equatable, Sendable { var message: String }` — message is the spec's "`<name>` must be …." sentence.

Limits and defaults (from the spec): `list_notes`/`list_meetings` limit default 50, max 200; `search` limit default 20, max 40; `get_meeting` `from_line` default 1, `parts` default all four; `summarize_meeting` `replace` default false. Upload extensions: `mp3, wav, m4a, aiff, aif, caf, mp4, mov, m4v` (case-insensitive); `path` must be absolute.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func negotiatesVersions() {
    #expect(MCPProtocol.negotiate("2025-03-26") == "2025-03-26")
    #expect(MCPProtocol.negotiate("1999-01-01") == "2025-06-18")
    #expect(MCPProtocol.negotiate(nil) == "2025-06-18")
}
@Test func initializeResultShape() {
    let r = MCPProtocol.initializeResult(version: "2025-06-18", appVersion: "1.3")
    #expect(r["protocolVersion"] == .string("2025-06-18"))
    #expect(r["serverInfo"]?["name"] == .string("bugvoice"))
    #expect(r["capabilities"]?["tools"] == .object([:]))
}
@Test func parsesRequestAndRejectsGarbage() {
    let ok = JSONRPCMessage.parse(Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8))
    #expect((try? ok.get())?.method == "ping")
    guard case .failure(let e) = JSONRPCMessage.parse(Data("nope".utf8)) else { Issue.record("parsed"); return }
    #expect(e.code == JSONRPCError.parse)
}
@Test func encodedLineIsOneLine() {
    let d = JSONValue.object(["a": .string("x\ny")]).encodedLine()
    let s = String(decoding: d, as: UTF8.self)
    #expect(s.hasSuffix("\n") && s.dropLast().contains("\n") == false)
}
@Test func toolListHasAllTwelve() {
    let names = MCPTools.definitions["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
    #expect(Set(names) == Set(MCPTool.allCases.map(\.rawValue)))
    for t in MCPTools.definitions["tools"]?.arrayValue ?? [] {
        #expect(t["inputSchema"]?["type"] == .string("object"))
        #expect((t["description"]?.stringValue ?? "").isEmpty == false)
    }
}
@Test func folderScopeParses() {
    #expect(MCPScopeArgument.parse(nil) == .all)
    #expect(MCPScopeArgument.parse("folder:Lộ trình") == .folder("Lộ trình"))
    #expect(MCPScopeArgument.parse("meeting:abc") == .meeting("abc"))
    #expect(MCPScopeArgument.parse("unfiled") == .unfiled)
    #expect(MCPScopeArgument.parse("everything") == nil)
}
@Test func checkAppliesDefaultsAndLimits() {
    #expect(try MCPTools.check("search", .object(["query": .string("bot")])).get() == .search(query: "bot", scope: .all, limit: 20))
    #expect(try MCPTools.check("list_notes", .object(["limit": .number(500)])).get() == .listNotes(folder: nil, tag: nil, text: nil, limit: 200))
}
@Test func checkRejectsBadArguments() {
    #expect(throws: MCPArgumentError.self) { try MCPTools.check("search", .object([:])).get() }
    #expect(throws: MCPArgumentError.self) { try MCPTools.check("upload_audio", .object(["path": .string("rel/a.mp3")])).get() }
    #expect(throws: MCPArgumentError.self) { try MCPTools.check("upload_audio", .object(["path": .string("/tmp/a.txt")])).get() }
    #expect(throws: MCPArgumentError.self) { try MCPTools.check("edit_note", .object(["id": .string("n"), "body": .string("x"), "mode": .string("merge")])).get() }
    #expect(throws: MCPArgumentError.self) { try MCPTools.check("ask", .object(["question": .string("q"), "scope": .string("everything")])).get() }
}
```

Also: `checkUnknownToolFails` (`check("delete_note", nil)` → failure with message "Unknown tool: delete_note."), `uploadExtensionCaseInsensitive` ("/x/A.MP4" passes).

- [ ] **Step 2: Run, expect compile failure** — `swift test --filter 'MCPProtocol|MCPTools'`
- [ ] **Step 3: Implement the three files.** `JSONValue` decodes numbers as `Double`; `intValue` returns `Int(exactly:)`. Tool descriptions: one short plain sentence each; scope description lists the five forms from spec section 5.
- [ ] **Step 4: Run, expect PASS; then full `swift test`.**
- [ ] **Step 5: Commit** `feat(core): MCP protocol, tool list and argument checks`

---

### Task 2: Result formatting, settings, activity, manifest fields and Ask search (VoiceCore)

**Files:**
- Create: `Sources/VoiceCore/MCP/MCPFormat.swift`, `Sources/VoiceCore/MCP/MCPActivity.swift`
- Modify: `Sources/VoiceCore/Settings.swift` (add `AgentSettings`), `Sources/VoiceCore/Meeting.swift` (`MeetingManifest` fields and decoding), `Sources/VoiceCore/Ask/AskPipeline.swift` (public `search`)
- Test: `Tests/VoiceCoreTests/MCPFormatTests.swift`, `Tests/VoiceCoreTests/MCPActivityTests.swift`, existing `SettingsTests`, `MeetingTests` (or the file that tests manifest decoding), `AskPipelineTests`

**Interfaces:**
- Produces:
  - `public struct AgentSettings: Codable, Equatable, Sendable { var mcpEnabled = false; var allowNoteEdits = true; var allowUploads = true }`; `AppSettings.agents = AgentSettings()`, decoded tolerantly like the other sections.
  - `MeetingManifest.uploadJobID: UUID?` and `MeetingManifest.addedBy: String?` (both default nil, tolerant decode, encoded only when non-nil).
  - `public struct MCPActivityEntry: Equatable, Sendable { var time: Date; var client: String; var tool: String; var error: String? }` and `public struct MCPActivity: Sendable { static let limit = 20; mutating func record(_ e: MCPActivityEntry); var entries: [MCPActivityEntry] /* newest first */ }`.
  - `public enum MCPFormat`:
    - `static let transcriptPage = 1500`
    - `static func note(title: String, folder: String?, tags: [String], modified: Date, body: String, unsaved: Bool) -> String` — `# Title`, then `Folder: … · Tags: … · Modified: <ISO 8601>`; when `unsaved`, append " · Unsaved changes included."; blank line; body.
    - `static func meeting(_ m: MeetingManifest, folder: String?, parts: Set<MCPMeetingPart>, fromLine: Int) -> String` — sections `## Summary`, `## Action items`, `## My notes`, `## Transcript`; transcript lines `[mm:ss] Speaker: text` (hours as `[h:mm:ss]` when ≥ 1 h), translation (when non-empty) on the next line as `    English: …`; at most `transcriptPage` lines from `fromLine`; when cut, last line `More: call get_meeting with from_line <next>.`
    - `static func json(_ value: JSONValue) -> String` (pretty, sorted keys).
    - `static func askResult(_ outcome: AskOutcome) -> Result<JSONValue, String>` — `.answered` → spec's `{answer, cards[...], searched, word_search_only?}`; `.nothingFound` → `{nothing_found: true}` (plus `word_search_only` when set); `.failed` → `.failure(<Ask spec section 9 sentence>)` (reuse the app's existing strings by moving them into `AskFailure.message` if they live in the app today).
    - ISO 8601 with local offset everywhere (`ISO8601DateFormatter` with `.withInternetDateTime`, `timeZone = .current`).
  - `AskPipeline.search(query: String, corpus: AskCorpus, limit: Int) async throws -> AskSearchResult` where `public struct AskSearchResult: Equatable, Sendable { var passages: [AskPassage]; var wordSearchOnly: WordOnlyReason? }`. Uses `AskQueryPrompt.fallback(question:)` terms (no model call), the same word ranking, meaning ranking (half-coverage rule, 0.3 floor, embed time limit) and RRF fusion as `run`, then `prefix(limit)`. Factor the shared ranking out of `execute` into one private helper so `run` and `search` cannot drift.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func agentSettingsDefaultsAndTolerantDecode() throws {
    #expect(AppSettings().agents == AgentSettings(mcpEnabled: false, allowNoteEdits: true, allowUploads: true))
    let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"agents":{"mcpEnabled":true}}"#.utf8))
    #expect(s.agents.mcpEnabled && s.agents.allowUploads)
}
@Test func manifestKeepsUploadJobFields() throws { /* encode a manifest with uploadJobID and addedBy, decode, expect equal; decode an old manifest JSON without them, expect nil */ }
@Test func activityKeepsNewestTwenty() {
    var a = MCPActivity()
    for i in 0..<25 { a.record(.init(time: Date(timeIntervalSince1970: Double(i)), client: "c", tool: "ask", error: nil)) }
    #expect(a.entries.count == 20)
    #expect(a.entries.first?.time == Date(timeIntervalSince1970: 24))
}
@Test func meetingTranscriptPagesAt1500() { /* manifest with 1600 segments → contains "[0:00]"-style first line, 1500 transcript lines, last line "More: call get_meeting with from_line 1501."; fromLine 1501 → 100 lines and no "More:" */ }
@Test func meetingLineFormat() { /* segment at 83 s, speaker "Luna", text "hi", translation "chào"→ "[01:23] Luna: hi" then "    English: chào"; translation "" → no English line */ }
@Test func noteMarksUnsaved() { #expect(MCPFormat.note(title: "T", folder: nil, tags: [], modified: .init(timeIntervalSince1970: 0), body: "b", unsaved: true).contains("Unsaved changes included.")) }
@Test func askResultShapes() { /* answered → cards[0].citations[0].quote equals the AskCitation quote; nothingFound(.noModel) → {nothing_found: true, word_search_only: true}; failed(.tooSlow) → failure text */ }
```

In `AskPipelineTests`: `searchNeedsNoModelCall` (StubModel records zero requests; result passages ranked like `run`'s word ranking), `searchRespectsLimit`, `searchWordOnlyWithoutEmbedder` (`wordSearchOnly == .noModel`).

- [ ] **Step 2: Run, expect failures.**
- [ ] **Step 3: Implement.** Pick the timestamp format so `[mm:ss]` below one hour matches the app's transcript view.
- [ ] **Step 4: Full `swift test` passes.**
- [ ] **Step 5: Commit** `feat(core): MCP results, agent settings and Ask search`

---

### Task 3: Unix socket server and client (MCPKit)

**Files:**
- Modify: `Package.swift` — add `.target(name: "MCPKit", path: "Sources/MCPKit")`, `.testTarget(name: "MCPKitTests", dependencies: ["MCPKit", "VoiceCore"], path: "Tests/MCPKitTests")`. `MCPKit` depends on `VoiceCore` only.
- Create: `Sources/MCPKit/MCPSocketPaths.swift`, `Sources/MCPKit/MCPSocketServer.swift`, `Sources/MCPKit/MCPSocketClient.swift`
- Test: `Tests/MCPKitTests/MCPSocketTests.swift`

**Interfaces:**
- Produces:
  - `public struct MCPSocketPaths: Sendable { let folder: URL; var socket: URL { folder/"bugvoice.sock" }; static func standard() -> MCPSocketPaths /* AppPaths.standard().root/"MCP" */ }`
  - Wire messages (also used by Tasks 4 and 6): `public struct MCPWireRequest: Codable, Equatable, Sendable { var id: String; var tool: String; var arguments: JSONValue?; var client: String }`, `public struct MCPWireResponse: Codable, Equatable, Sendable { var id: String; var text: String; var isError: Bool }`. One JSON object per line.
  - `public final class MCPSocketServer: Sendable` — `init(paths: MCPSocketPaths, maxConnections: Int = 4, peerCheck: @escaping @Sendable (Int32) -> Bool = MCPSocketServer.sameUser, handler: @escaping @Sendable (MCPWireRequest) async -> MCPWireResponse)`; `func start() throws`; `func stop()`. `start` creates the folder with 0700 (and chmods an existing one to 0700), removes a stale socket file, binds, chmods the socket to 0600, listens. Each accepted connection: run `peerCheck(fd)` (default compares `getpeereid` uid to `getuid()`), refuse a 5th concurrent connection (close it), read lines up to 4 MB (longer → close), decode each line as `MCPWireRequest`, answer each request on the same connection; requests on one connection may be answered out of order (matched by `id`). A line that does not decode gets `MCPWireResponse(id: "", text: "Bad request.", isError: true)`.
  - `public final class MCPSocketClient: Sendable` — `static func connect(paths: MCPSocketPaths) throws -> MCPSocketClient` (throws `MCPSocketError.notListening` when the file is missing or connect fails); `func send(_ r: MCPWireRequest) async throws -> MCPWireResponse`; `func close()`.
  - `public enum MCPSocketError: Error, Equatable { case notListening, closed, pathTooLong }` (sun_path is 104 bytes; long temp paths must fail clearly).

- [ ] **Step 1: Write the failing tests** (all in a temp folder short enough for `sun_path`, for example `/tmp/bv-<8 hex>/`)

```swift
@Test func roundTrip() async throws { /* server echoes tool name; client send → response.text == "ask" */ }
@Test func permissions() throws { /* after start: folder mode 0o700, socket mode 0o600 */ }
@Test func staleSocketReplaced() throws { /* create a plain file at socket path; start succeeds */ }
@Test func rejectsForeignPeer() async throws { /* peerCheck returns false → client send throws .closed */ }
@Test func fifthConnectionRefused() async throws { /* 4 clients connected and idle; 5th send throws .closed; after closing one, a new client works */ }
@Test func oversizeLineClosesConnection() async throws { /* write 5 MB without newline over a raw socket → server closes; server still serves a new client */ }
@Test func badLineGetsError() async throws { /* raw write "nope\n" → response isError, text "Bad request." */ }
@Test func clientNotListening() { #expect(throws: MCPSocketError.notListening) { try MCPSocketClient.connect(paths: tempPaths) } }
@Test func stopRemovesSocket() throws { /* stop → socket file gone */ }
```

- [ ] **Step 2: Run, expect failures.** `swift test --filter MCPSocket`
- [ ] **Step 3: Implement** with `socket(AF_UNIX, SOCK_STREAM)`, a `DispatchSource` read source per connection (or one detached thread per connection using blocking `read`); handler calls run in `Task`s. No locks held across `await`.
- [ ] **Step 4: PASS, then full `swift test`.**
- [ ] **Step 5: Commit** `feat(mcp): local socket server and client`

---

### Task 4: The `bugvoice-mcp` bridge

**Files:**
- Modify: `Package.swift` — `.executable(name: "bugvoice-mcp", targets: ["BugVoiceMCP"])`, `.executableTarget(name: "BugVoiceMCP", dependencies: ["MCPKit", "VoiceCore"], path: "Sources/BugVoiceMCP")`
- Create: `Sources/MCPKit/MCPBridge.swift`, `Sources/BugVoiceMCP/main.swift`
- Modify: `Scripts/build-app.sh` — copy `$BIN/bugvoice-mcp` to `$CONTENTS/MacOS/bugvoice-mcp` before signing (the bundle signature must cover it; sign it with the same identity first if `codesign` of the bundle does not)
- Test: `Tests/MCPKitTests/MCPBridgeTests.swift`

**Interfaces:**
- Consumes: Task 1 (`JSONRPCMessage`, `MCPProtocol`, `MCPTools`), Task 3 (`MCPSocketClient`, wire types).
- Produces: `public final class MCPBridge` — `init(paths: MCPSocketPaths, appVersion: String, launchApp: @escaping @Sendable () -> Void, waitSeconds: Double = 20, output: @escaping @Sendable (Data) -> Void)`; `func handle(line: Data) async` (one stdin line in, zero or one stdout line out via `output`). `main.swift` reads stdin lines, calls `handle`, writes `output` to stdout and flushes; on EOF exits 0. `launchApp` runs `/usr/bin/open -g -a <bundle>` where `<bundle>` is three levels up from the executable (`.../BugVoice.app`). `appVersion` comes from that bundle's `Info.plist` (`CFBundleShortVersionString`), "0" if unreadable.

Behaviour:
- `initialize` → `initializeResult(version: negotiate(params.protocolVersion))`; remember `params.clientInfo.name` (default "agent").
- `notifications/initialized` and any notification → no output.
- `ping` → `{}` result.
- `tools/list` → `MCPTools.definitions`.
- `tools/call` → `MCPTools.check`; argument error → tool result `isError: true` with its message, nothing forwarded. Otherwise connect (reuse one client per bridge; reconnect once if closed); on `.notListening` call `launchApp()` once per bridge process, then retry connect every 250 ms up to `waitSeconds`; still failing → tool result error "BugVoice did not start. Open it and try again." Forward `MCPWireRequest(id: <uuid>, tool:, arguments:, client:)`; map the response to `MCPProtocol.toolResult(text:isError:)`.
- Unknown method with an id → JSON-RPC error `methodNotFound`. Bad line → JSON-RPC error `parse` with `id: null`.
- Nothing but protocol lines on stdout; diagnostics (counts only) on stderr.

- [ ] **Step 1: Write the failing tests** (fake `MCPSocketServer` from Task 3 in a temp folder; `output` collects lines)

```swift
@Test func handshake() async { /* initialize with "2025-03-26" → result.protocolVersion "2025-03-26"; then notifications/initialized → no output */ }
@Test func toolsListWorksWithoutApp() async { /* no server running → tools/list still returns 12 tools; launchApp not called */ }
@Test func forwardsToolCall() async { /* server returns text "ok" → result.content[0].text "ok", isError false; server saw client name from initialize */ }
@Test func argumentErrorNotForwarded() async { /* search without query → isError true, server saw nothing */ }
@Test func launchesAppWhenSocketMissing() async { /* no server; launchApp starts the server after 0.5 s → call succeeds; launchApp called exactly once */ }
@Test func reportsDidNotStart() async { /* no server, waitSeconds 0.5, launchApp does nothing → text "BugVoice did not start. Open it and try again." */ }
@Test func unknownMethod() async { /* "resources/list" with id → error code -32601 */ }
@Test func garbageLine() async { /* "nope" → error code -32700, id null */ }
```

- [ ] **Step 2: Run, expect failures.**
- [ ] **Step 3: Implement `MCPBridge`, `main.swift`, and the `build-app.sh` copy.**
- [ ] **Step 4: PASS; full `swift test`; `Scripts/build-app.sh` exits 0 and `codesign --verify --strict build/BugVoice.app` passes; `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"t"}}}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | build/BugVoice.app/Contents/MacOS/bugvoice-mcp` prints two JSON lines, the second listing 12 tools.**
- [ ] **Step 5: Commit** `feat(mcp): bugvoice-mcp stdio bridge`

---

### Task 5: Note entry points for agents (BugVoiceMac)

**Files:**
- Modify: `Sources/BugVoiceMac/NotesController.swift`
- Test: `Tests/BugVoiceMacTests/NotesControllerTests.swift`

**Interfaces:**
- Produces:
  - `public func createForAgent(title: String, body: String, frontMatter: NoteFrontMatter) async throws -> NoteDocument` — writes the note through the store and refreshes the list; does not select it, does not save or change the selected note, does not open any window.
  - `public enum AgentEditRefusal: Error, Equatable { case unsaved, dictating }` with `message`: "This note has unsaved changes in BugVoice. Try again after it saves." / "BugVoice is dictating into this note. Try again in a moment."
  - `public func agentEdit(id: NoteID, body: String, append: Bool, title: String?, labels: (folderID: FolderID?, tags: [String])?) async throws -> NoteDocument` — refuses with `.unsaved` when the loaded state is dirty, its title draft differs from the saved title, or an external change is waiting; with `.dictating` when a dictation capture targets this note. Otherwise saves (append = existing body + "\n\n" + text, trimming one trailing newline from the existing body first), updates an attached editor's text, and registers one undo step named "Agent edit" when an undo manager exists. Unloaded notes are edited on disk through the store.

- [ ] **Step 1: Write the failing tests** (use the file's existing temp-store helpers)

```swift
@Test func createForAgentKeepsSelection() async throws { /* select note A, createForAgent B → selected id still A, B in list, A unchanged on disk */ }
@Test func agentEditReplaceAndAppend() async throws { /* replace → body "x"; append "y" to "x\n" → "x\n\ny" */ }
@Test func agentEditRefusedWhileDirty() async throws { /* updateBody(id, "typing") without flush → throws .unsaved; disk body unchanged; in-memory "typing" unchanged */ }
@Test func agentEditRefusedWhileTitleDraft() async throws { /* updateTitleDraft differs → .unsaved */ }
@Test func agentEditRefusedWhileDictating() async throws { /* captureAtStart targeting the note → .dictating */ }
@Test func agentEditUndoName() async throws { /* loaded note with undo manager → undoActionName == "Agent edit" after edit */ }
@Test func agentEditUnloadedNote() async throws { /* note never loaded → edit lands on disk */ }
```

- [ ] **Step 2: Run, expect failures.** `swift test --filter NotesController`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: PASS; full `swift test`.**
- [ ] **Step 5: Commit** `feat(app): note create and edit entry points for agents`

---

### Task 6: `MCPService` — server lifecycle, reads, search, ask, summary (app)

**Files:**
- Create: `Sources/BugVoice/MCPService.swift`, `Sources/VoiceCore/MCP/MCPResolve.swift`
- Modify: `Sources/BugVoice/AppModel.swift` (own one `MCPService`, start at launch, stop at quit), `Package.swift` (`BugVoice` depends on `MCPKit`)
- Test: `Tests/VoiceCoreTests/MCPResolveTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3; `SearchIndexer.corpus(scope:)`; `AppModel.askAcross` construction pieces; `AppModel.generateMeetingText(id:kind:progress:)` (it saves the text itself and throws `CancellationError` when that meeting's text is already being generated).
- Produces:
  - VoiceCore `public enum MCPResolve { static func folder(_ nameOrID: String, in folders: [LibraryFolder]) -> Result<FolderID, String>; static func scope(_ s: MCPScopeArgument, folders: [LibraryFolder]) -> Result<AskScope, String> }` — id match first, then folded (`AskText.fold`) name match; failure text "No folder named <name>. Folders: <names joined by ", ">." (or "No folders yet." when empty). `.note(id)` → `AskScope.note`, used read-only.
  - `@MainActor final class MCPService` with `init(model: AppModel)`, `func start()` (starts `MCPSocketServer` always; status "Listening" / "Could not start: <reason>"), `func stop()`, `private(set) var activity: MCPActivity`, `private(set) var status: String`, and `func handle(_ r: MCPWireRequest) async -> MCPWireResponse`.
- `handle`:
  - MCP off → "MCP is off. Turn it on in BugVoice Settings › Agents."
  - Re-check arguments with `MCPTools.check` (the socket is a trust boundary too).
  - Reads: `list_folders` (counts of notes and meetings per folder), `list_notes` (from the notes list, newest modified first, `text` filter folded on title), `get_note` (unsaved editor text when loaded and dirty, `unsaved: true`), `list_meetings` (`kind` from `source`, `people` = distinct speaker labels in first-appearance order, `has_summary` = non-empty), `get_meeting` (`MCPFormat.meeting`).
  - `search`: `AskPipeline.search` with `searchIndexer.corpus(scope:)`; JSON per spec.
  - `ask`: same pipeline construction as `askAcross` (Notes model, embedder, context size), empty history, `MCPFormat.askResult`. No Notes model → "Choose a Notes model in BugVoice Settings › Models."
  - `summarize_meeting`: existing text and `replace == false` → return it; else `generateMeetingText` with a 300 s limit; `CancellationError` → "BugVoice is already writing this meeting's summary. Try again in a minute."
  - `ask` and `summarize_meeting` go through one serial queue (an actor with a FIFO of continuations), reads do not.
  - Record every call in `activity` (tool, client, error sentence or nil). Log one line per call to `Logger(subsystem: "com.kael.bugvoice", category: "mcp")` with tool, client, seconds, ok — `.public` only for those.
  - Write and upload tools return "Not available yet." until Task 7 (removed there).

- [ ] **Step 1: Write the failing `MCPResolve` tests**

```swift
@Test func folderByIDThenFoldedName() {
    let f = [LibraryFolder(id: FolderID(rawValue: "f1"), name: "Lộ trình"), LibraryFolder(id: FolderID(rawValue: "f2"), name: "Work")]
    #expect(try MCPResolve.folder("f2", in: f).get() == FolderID(rawValue: "f2"))
    #expect(try MCPResolve.folder("lo trinh", in: f).get() == FolderID(rawValue: "f1"))
    #expect(try MCPResolve.folder("WORK", in: f).get() == FolderID(rawValue: "f2"))
}
@Test func unknownFolderListsNames() {
    guard case .failure(let m) = MCPResolve.folder("Roadmap", in: [LibraryFolder(id: FolderID(rawValue: "f"), name: "Work")]) else { Issue.record("found"); return }
    #expect(m == "No folder named Roadmap. Folders: Work.")
}
@Test func scopeMapping() { /* .unfiled → .folder(nil); .meeting("m") → .meeting(MeetingID("m")); .all → .all */ }
```

(Use `LibraryFolder`'s real initializer.)

- [ ] **Step 2: Run, expect failures.**
- [ ] **Step 3: Implement `MCPResolve`, then `MCPService` and the `AppModel` wiring.**
- [ ] **Step 4: Full `swift test` passes; `Scripts/build-app.sh` exits 0.**
- [ ] **Step 5: Device smoke (dev app, MCP turned on by temporarily setting `agents.mcpEnabled` through Task 8's switch or a debug default):** pipe `initialize`, `tools/call list_meetings {"limit":2}` and `tools/call search {"query":"bot"}` into `build/BugVoice.app/Contents/MacOS/bugvoice-mcp`; expect JSON results. If Task 8 is not done, note the smoke as pending in the report instead of editing the owner's `settings.json`. Restore with `open /Applications/BugVoice.app` after.
- [ ] **Step 6: Commit** `feat(app): MCP service with read, search, ask and summary tools`

---

### Task 7: Write and upload tools (app)

**Files:**
- Modify: `Sources/BugVoice/MCPService.swift`, `Sources/BugVoice/UploadController.swift`, the Upload page view that shows queue rows (`Sources/BugVoice/UI/UploadPage.swift` or the file that renders `UploadJob` rows)
- Modify: `Sources/VoiceCore/UploadQueue.swift` (`UploadJob.addedBy: String?`) with a test in its existing test file

**Interfaces:**
- Consumes: Task 5 entry points, Task 2 manifest fields and settings.
- Produces:
  - `UploadController.submitForAgent(url: URL, title: String?, labels: ItemLabels, client: String) async throws -> UUID` — same validation and queueing as `choose` + `submit`, without touching the owner's drafts; the job's id is returned; the manifest written for this job carries `uploadJobID` = that id and `addedBy` = client; recovery (`appendRecovery`/`restore`) rebuilds such jobs with the saved `uploadJobID` instead of a new UUID.
  - `UploadController.jobStatus(id: UUID) -> UploadJob?` — queue first, then manifests (`uploadJobID`): a ready manifest maps to state `ready` with `meetingID`, failed to `failed` with `transcriptionError`.
- `MCPService` additions:
  - `create_note` / `edit_note`: write switch off → "Creating and editing notes is turned off in BugVoice Settings › Agents."; folder by `MCPResolve.folder`; `AgentEditRefusal.message` returned as the error.
  - `upload_audio`: upload switch off → "Uploading is turned off in BugVoice Settings › Agents."; missing file → "File not found: <path>."; unsupported → "File type not supported: .<ext>. Supported: MP3, WAV, M4A, AIFF, CAF, MP4, MOV, M4V."
  - `get_job`: states `queued/reading/transcribing/finding_speakers/ready/failed/cancelled` (`finding_speakers` while the job is ready in the queue but speaker finding for its meeting is still running); unknown → "No upload job with id <id>."
  - Upload queue row shows "Added by <client>" under the file name when `addedBy` is set.

- [ ] **Step 1: Failing VoiceCore test** `uploadJobCarriesAddedBy` (the queue keeps `addedBy` through state events).
- [ ] **Step 2: Run, expect failure; implement; PASS; full `swift test`.**
- [ ] **Step 3: Implement the app side.** `Scripts/build-app.sh` exits 0.
- [ ] **Step 4: Device smoke** with a short test file made by `say -o /tmp/bv-mcp-test.aiff "testing the people bot"`: `upload_audio` → `get_job` until `ready` → `get_meeting` shows the text → `create_note` then `edit_note` append on that test note. Afterwards delete only the test meeting and test note through the app's own Trash actions, and restore `open /Applications/BugVoice.app`.
- [ ] **Step 5: Commit** `feat(app): MCP note writing and uploads`

---

### Task 8: Settings › Agents

**Files:**
- Create: `Sources/BugVoice/UI/Settings/AgentsSettings.swift`
- Modify: `Sources/BugVoice/UI/Settings/SettingsView.swift` (`SettingsTab.agents`, tab title "Agents" placed after Models)

**Interfaces:**
- Consumes: `AppSettings.agents`, `MCPService.status`, `MCPService.activity`.
- Produces: the tab exactly as the mockup's states 1–3: MCP server switch with the spec's sentence and status line; the two permission switches (disabled while MCP is off); "Set up an agent" with Claude Code and Codex rows, each a Copy button that copies the text and shows "Copied" for 2 s; the Codex text includes `tool_timeout_sec = 300`; `<path>` is `Bundle.main.bundleURL/Contents/MacOS`; "Recent activity" table (time `HH:mm`, client, tool, "OK" or the error sentence) or "No agent has connected yet."

- [ ] **Step 1: Implement the view** (no VoiceCore change, so no new unit test).
- [ ] **Step 2: `Scripts/build-app.sh` exits 0; run the dev app with `Scripts/run-dev-app.sh`; capture the Settings window (`screencapture -l <window id>`) in Off and On states and compare with `docs/design/proposal-mcp.html`; restore `open /Applications/BugVoice.app`.**
- [ ] **Step 3: Run the Task 6 smoke now if it was pending, using the switch.**
- [ ] **Step 4: Commit** `feat(app): Settings Agents tab for the MCP server`

---

### Task 9: Docs and manual checks

**Files:**
- Create: `docs/progress/mcp-log.md` — numbered manual checks (start at 1) covering: each Settings state; Claude Code setup with the copied command and a real `ask`; Codex setup; each tool once; every error sentence in spec section 7; the five Review Focus items; dev and installed build sharing one socket; MCP off with the app running; app quit then a tool call (app launches in the background).
- Modify: `docs/progress/HANDOFF.md`, `docs/ROADMAP.md` (item 6: MCP server built, device checks pending), `AGENTS.md` key documents (plan and log).

- [ ] **Step 1: Write the files.**
- [ ] **Step 2: Commit** `docs: MCP server checks and status`
