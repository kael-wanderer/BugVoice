# BugVoice MCP Server — Luna Execution Plan

> For Codex Luna. Every line of code is already written, compiled and tested. Your job is to apply
> nine patches in order, run the checks after each one, and stop on the first failure. Make no
> design decisions and do not edit code.

**What this builds:** the local MCP server described in `docs/superpowers/specs/2026-10-17-mcp-server-design.md`
(design plan: `docs/superpowers/plans/2026-10-17-mcp-server.md`).

**Patches:** `docs/superpowers/plans/2026-10-17-mcp-server-luna/task-01.patch` … `task-09.patch`.
Each patch is one commit (`git am` creates it with its message). They were made on `main` at
`90eb73d` and checked to apply on `70b9a02`.

## Rules

- Work only in the worktree created in Task 0. Never commit on `main`. Never push or merge.
- Do not edit any source file. If a patch, a test or the build fails, stop and report the exact
  command and its full output.
- Do not run `Scripts/run-dev-app.sh`, do not `open` any BugVoice app, and do not read or write
  `~/Library/Application Support/BugVoice`.
- Run every command from the worktree root unless a step says otherwise.

## Task 0: Create the worktree

- [ ] **Step 1:**

```bash
cd /Users/cong.bui/Kael/19-AppBuild/BugVoice
git status --short
git worktree add -b feat/mcp-server ../BugVoice-mcp main
cd ../BugVoice-mcp
git log --oneline -1
```

Expected: `git status --short` shows nothing except `?? .vscode/`; the worktree is created; the
last line shows the newest `docs:` commit on `main`.

- [ ] **Step 2: Baseline tests.**

```bash
swift test
```

Expected: every `Test run with … passed`. If not, stop and report: the failure is not yours.

From here on, every task runs inside `/Users/cong.bui/Kael/19-AppBuild/BugVoice-mcp`. The patch
files exist there because they are committed on `main`.

---

### Task 1: feat(core): MCP protocol, tool list and argument checks

Files (A = new, M = changed):

```
A	Sources/VoiceCore/MCP/JSONValue.swift
A	Sources/VoiceCore/MCP/MCPProtocol.swift
A	Sources/VoiceCore/MCP/MCPTools.swift
A	Tests/VoiceCoreTests/MCPProtocolTests.swift
A	Tests/VoiceCoreTests/MCPToolsTests.swift
```

- [ ] **Step 1: Apply the patch.** Run exactly:

```bash
cd /Users/cong.bui/Kael/19-AppBuild/BugVoice-mcp
git am --3way docs/superpowers/plans/2026-10-17-mcp-server-luna/task-01.patch
```

Expected: `Applying: feat(core): MCP protocol, tool list and argument checks` and exit status 0. If it fails, run `git am --abort`, stop, and report the full output. Do not edit code to make it apply.

- [ ] **Step 2: Run the tests.**

```bash
swift test
```

Expected: every `Test run with … passed` line (two before Task 3, three from Task 3 on). If anything fails, stop and report the failing test names and output. Do not change code.

- [ ] **Step 3: Check the commit.** `git log --oneline -1` shows `feat(core): MCP protocol, tool list and argument checks`. `git am` already made the commit; do not commit again.

Diff summary:

```
Sources/VoiceCore/MCP/JSONValue.swift       |  80 ++++++
 Sources/VoiceCore/MCP/MCPProtocol.swift     | 100 ++++++++
 Sources/VoiceCore/MCP/MCPTools.swift        | 379 ++++++++++++++++++++++++++++
 Tests/VoiceCoreTests/MCPProtocolTests.swift |  63 +++++
 Tests/VoiceCoreTests/MCPToolsTests.swift    |  81 ++++++
 5 files changed, 703 insertions(+)
```

---

### Task 2: feat(core): MCP results, agent settings and Ask search

Files (A = new, M = changed):

```
M	Sources/BugVoice/UI/Scratchpad/AskAnswerView.swift
M	Sources/VoiceCore/Ask/AskPipeline.swift
A	Sources/VoiceCore/MCP/MCPActivity.swift
A	Sources/VoiceCore/MCP/MCPFormat.swift
M	Sources/VoiceCore/Meeting.swift
M	Sources/VoiceCore/Settings.swift
M	Tests/VoiceCoreTests/AskPipelineTests.swift
A	Tests/VoiceCoreTests/MCPActivityTests.swift
A	Tests/VoiceCoreTests/MCPFormatTests.swift
M	Tests/VoiceCoreTests/SettingsTests.swift
M	Tests/VoiceCoreTests/UploadManifestTests.swift
```

- [ ] **Step 1: Apply the patch.** Run exactly:

```bash
cd /Users/cong.bui/Kael/19-AppBuild/BugVoice-mcp
git am --3way docs/superpowers/plans/2026-10-17-mcp-server-luna/task-02.patch
```

Expected: `Applying: feat(core): MCP results, agent settings and Ask search` and exit status 0. If it fails, run `git am --abort`, stop, and report the full output. Do not edit code to make it apply.

- [ ] **Step 2: Run the tests.**

```bash
swift test
```

Expected: every `Test run with … passed` line (two before Task 3, three from Task 3 on). If anything fails, stop and report the failing test names and output. Do not change code.

- [ ] **Step 3: Build the app.**

```bash
Scripts/build-app.sh
```

Expected: exit status 0 and `Signed with: Bugler Local Dev`.

- [ ] **Step 4: Check the commit.** `git log --oneline -1` shows `feat(core): MCP results, agent settings and Ask search`. `git am` already made the commit; do not commit again.

Diff summary:

```
Sources/BugVoice/UI/Scratchpad/AskAnswerView.swift |   9 +-
 Sources/VoiceCore/Ask/AskPipeline.swift            | 106 +++++++++----
 Sources/VoiceCore/MCP/MCPActivity.swift            |  31 ++++
 Sources/VoiceCore/MCP/MCPFormat.swift              | 165 +++++++++++++++++++++
 Sources/VoiceCore/Meeting.swift                    |  13 +-
 Sources/VoiceCore/Settings.swift                   |  25 ++++
 Tests/VoiceCoreTests/AskPipelineTests.swift        |  30 ++++
 Tests/VoiceCoreTests/MCPActivityTests.swift        |  13 ++
 Tests/VoiceCoreTests/MCPFormatTests.swift          | 124 ++++++++++++++++
 Tests/VoiceCoreTests/SettingsTests.swift           |   8 +
 Tests/VoiceCoreTests/UploadManifestTests.swift     |  15 ++
 11 files changed, 502 insertions(+), 37 deletions(-)
```

---

### Task 3: feat(mcp): local socket server and client

Files (A = new, M = changed):

```
M	Package.swift
A	Sources/MCPKit/MCPSocketClient.swift
A	Sources/MCPKit/MCPSocketPaths.swift
A	Sources/MCPKit/MCPSocketServer.swift
A	Tests/MCPKitTests/MCPSocketTests.swift
```

- [ ] **Step 1: Apply the patch.** Run exactly:

```bash
cd /Users/cong.bui/Kael/19-AppBuild/BugVoice-mcp
git am --3way docs/superpowers/plans/2026-10-17-mcp-server-luna/task-03.patch
```

Expected: `Applying: feat(mcp): local socket server and client` and exit status 0. If it fails, run `git am --abort`, stop, and report the full output. Do not edit code to make it apply.

- [ ] **Step 2: Run the tests.**

```bash
swift test
```

Expected: every `Test run with … passed` line (two before Task 3, three from Task 3 on). If anything fails, stop and report the failing test names and output. Do not change code.

- [ ] **Step 3: Build the app.**

```bash
Scripts/build-app.sh
```

Expected: exit status 0 and `Signed with: Bugler Local Dev`.

- [ ] **Step 4: Check the commit.** `git log --oneline -1` shows `feat(mcp): local socket server and client`. `git am` already made the commit; do not commit again.

Diff summary:

```
Package.swift                          |  12 ++
 Sources/MCPKit/MCPSocketClient.swift   | 130 +++++++++++++
 Sources/MCPKit/MCPSocketPaths.swift    | 136 +++++++++++++
 Sources/MCPKit/MCPSocketServer.swift   | 224 +++++++++++++++++++++
 Tests/MCPKitTests/MCPSocketTests.swift | 344 +++++++++++++++++++++++++++++++++
 5 files changed, 846 insertions(+)
```

---

### Task 4: feat(mcp): bugvoice-mcp stdio bridge

Files (A = new, M = changed):

```
M	Package.swift
M	Scripts/build-app.sh
A	Sources/BugVoiceMCP/main.swift
A	Sources/MCPKit/MCPBridge.swift
A	Tests/MCPKitTests/MCPBridgeTests.swift
```

- [ ] **Step 1: Apply the patch.** Run exactly:

```bash
cd /Users/cong.bui/Kael/19-AppBuild/BugVoice-mcp
git am --3way docs/superpowers/plans/2026-10-17-mcp-server-luna/task-04.patch
```

Expected: `Applying: feat(mcp): bugvoice-mcp stdio bridge` and exit status 0. If it fails, run `git am --abort`, stop, and report the full output. Do not edit code to make it apply.

- [ ] **Step 2: Run the tests.**

```bash
swift test
```

Expected: every `Test run with … passed` line (two before Task 3, three from Task 3 on). If anything fails, stop and report the failing test names and output. Do not change code.

- [ ] **Step 3: Build the app.**

```bash
Scripts/build-app.sh
```

Expected: exit status 0 and `Signed with: Bugler Local Dev`.

- [ ] **Step 4: Check the commit.** `git log --oneline -1` shows `feat(mcp): bugvoice-mcp stdio bridge`. `git am` already made the commit; do not commit again.

Diff summary:

```
Package.swift                          |   8 ++
 Scripts/build-app.sh                   |   6 ++
 Sources/BugVoiceMCP/main.swift         |  56 ++++++++++
 Sources/MCPKit/MCPBridge.swift         | 138 ++++++++++++++++++++++++
 Tests/MCPKitTests/MCPBridgeTests.swift | 192 +++++++++++++++++++++++++++++++++
 5 files changed, 400 insertions(+)
```

---

### Task 5: feat(app): note create and edit entry points for agents

Files (A = new, M = changed):

```
M	Sources/BugVoice/DictationController.swift
M	Sources/BugVoiceMac/NotesController.swift
M	Tests/BugVoiceMacTests/NotesControllerTests.swift
```

- [ ] **Step 1: Apply the patch.** Run exactly:

```bash
cd /Users/cong.bui/Kael/19-AppBuild/BugVoice-mcp
git am --3way docs/superpowers/plans/2026-10-17-mcp-server-luna/task-05.patch
```

Expected: `Applying: feat(app): note create and edit entry points for agents` and exit status 0. If it fails, run `git am --abort`, stop, and report the full output. Do not edit code to make it apply.

- [ ] **Step 2: Run the tests.**

```bash
swift test
```

Expected: every `Test run with … passed` line (two before Task 3, three from Task 3 on). If anything fails, stop and report the failing test names and output. Do not change code.

- [ ] **Step 3: Build the app.**

```bash
Scripts/build-app.sh
```

Expected: exit status 0 and `Signed with: Bugler Local Dev`.

- [ ] **Step 4: Check the commit.** `git log --oneline -1` shows `feat(app): note create and edit entry points for agents`. `git am` already made the commit; do not commit again.

Diff summary:

```
Sources/BugVoice/DictationController.swift        |  12 +-
 Sources/BugVoiceMac/NotesController.swift         | 132 +++++++++++++++++-
 Tests/BugVoiceMacTests/NotesControllerTests.swift | 161 ++++++++++++++++++++++
 3 files changed, 298 insertions(+), 7 deletions(-)
```

---

### Task 6: feat(app): MCP service with read, search, ask and summary tools

Files (A = new, M = changed):

```
M	Package.swift
M	Sources/BugVoice/AppModel+Scratchpad.swift
M	Sources/BugVoice/AppModel.swift
M	Sources/BugVoice/BugVoiceApp.swift
A	Sources/BugVoice/MCPService.swift
M	Sources/BugVoiceMac/NotesController.swift
A	Sources/VoiceCore/MCP/MCPReplyLimit.swift
A	Sources/VoiceCore/MCP/MCPResolve.swift
A	Tests/VoiceCoreTests/MCPReplyLimitTests.swift
A	Tests/VoiceCoreTests/MCPResolveTests.swift
```

- [ ] **Step 1: Apply the patch.** Run exactly:

```bash
cd /Users/cong.bui/Kael/19-AppBuild/BugVoice-mcp
git am --3way docs/superpowers/plans/2026-10-17-mcp-server-luna/task-06.patch
```

Expected: `Applying: feat(app): MCP service with read, search, ask and summary tools` and exit status 0. If it fails, run `git am --abort`, stop, and report the full output. Do not edit code to make it apply.

- [ ] **Step 2: Run the tests.**

```bash
swift test
```

Expected: every `Test run with … passed` line (two before Task 3, three from Task 3 on). If anything fails, stop and report the failing test names and output. Do not change code.

- [ ] **Step 3: Build the app.**

```bash
Scripts/build-app.sh
```

Expected: exit status 0 and `Signed with: Bugler Local Dev`.

- [ ] **Step 4: Check the commit.** `git log --oneline -1` shows `feat(app): MCP service with read, search, ask and summary tools`. `git am` already made the commit; do not commit again.

Diff summary:

```
Package.swift                                 |   2 +-
 Sources/BugVoice/AppModel+Scratchpad.swift    |  19 +-
 Sources/BugVoice/AppModel.swift               |   9 +
 Sources/BugVoice/BugVoiceApp.swift            |   4 +
 Sources/BugVoice/MCPService.swift             | 359 ++++++++++++++++++++++++++
 Sources/BugVoiceMac/NotesController.swift     |   7 +
 Sources/VoiceCore/MCP/MCPReplyLimit.swift     |  54 ++++
 Sources/VoiceCore/MCP/MCPResolve.swift        |  26 ++
 Tests/VoiceCoreTests/MCPReplyLimitTests.swift |  58 +++++
 Tests/VoiceCoreTests/MCPResolveTests.swift    |  36 +++
 10 files changed, 569 insertions(+), 5 deletions(-)
```

---

### Task 7: feat(app): MCP note writing and uploads

Files (A = new, M = changed):

```
M	Sources/BugVoice/MCPService.swift
M	Sources/BugVoice/UI/UploadPage.swift
M	Sources/BugVoice/UploadController.swift
M	Sources/VoiceCore/AppPaths.swift
A	Sources/VoiceCore/MCP/AgentUploadStore.swift
M	Sources/VoiceCore/UploadQueue.swift
A	Tests/VoiceCoreTests/AgentUploadStoreTests.swift
M	Tests/VoiceCoreTests/UploadQueueTests.swift
```

- [ ] **Step 1: Apply the patch.** Run exactly:

```bash
cd /Users/cong.bui/Kael/19-AppBuild/BugVoice-mcp
git am --3way docs/superpowers/plans/2026-10-17-mcp-server-luna/task-07.patch
```

Expected: `Applying: feat(app): MCP note writing and uploads` and exit status 0. If it fails, run `git am --abort`, stop, and report the full output. Do not edit code to make it apply.

- [ ] **Step 2: Run the tests.**

```bash
swift test
```

Expected: every `Test run with … passed` line (two before Task 3, three from Task 3 on). If anything fails, stop and report the failing test names and output. Do not change code.

- [ ] **Step 3: Build the app.**

```bash
Scripts/build-app.sh
```

Expected: exit status 0 and `Signed with: Bugler Local Dev`.

- [ ] **Step 4: Check the commit.** `git log --oneline -1` shows `feat(app): MCP note writing and uploads`. `git am` already made the commit; do not commit again.

Diff summary:

```
Sources/BugVoice/MCPService.swift                | 128 ++++++++++++++++++++-
 Sources/BugVoice/UI/UploadPage.swift             |   9 +-
 Sources/BugVoice/UploadController.swift          | 135 ++++++++++++++++++++++-
 Sources/VoiceCore/AppPaths.swift                 |   5 +
 Sources/VoiceCore/MCP/AgentUploadStore.swift     | 133 ++++++++++++++++++++++
 Sources/VoiceCore/UploadQueue.swift              |  10 +-
 Tests/VoiceCoreTests/AgentUploadStoreTests.swift | 107 ++++++++++++++++++
 Tests/VoiceCoreTests/UploadQueueTests.swift      |  15 +++
 8 files changed, 529 insertions(+), 13 deletions(-)
```

---

### Task 8: feat(app): Settings Agents tab for the MCP server

Files (A = new, M = changed):

```
A	Sources/BugVoice/UI/Settings/AgentsSettings.swift
M	Sources/BugVoice/UI/Settings/SettingsView.swift
```

- [ ] **Step 1: Apply the patch.** Run exactly:

```bash
cd /Users/cong.bui/Kael/19-AppBuild/BugVoice-mcp
git am --3way docs/superpowers/plans/2026-10-17-mcp-server-luna/task-08.patch
```

Expected: `Applying: feat(app): Settings Agents tab for the MCP server` and exit status 0. If it fails, run `git am --abort`, stop, and report the full output. Do not edit code to make it apply.

- [ ] **Step 2: Run the tests.**

```bash
swift test
```

Expected: every `Test run with … passed` line (two before Task 3, three from Task 3 on). If anything fails, stop and report the failing test names and output. Do not change code.

- [ ] **Step 3: Build the app.**

```bash
Scripts/build-app.sh
```

Expected: exit status 0 and `Signed with: Bugler Local Dev`.

- [ ] **Step 4: Check the commit.** `git log --oneline -1` shows `feat(app): Settings Agents tab for the MCP server`. `git am` already made the commit; do not commit again.

Diff summary:

```
Sources/BugVoice/UI/Settings/AgentsSettings.swift | 147 ++++++++++++++++++++++
 Sources/BugVoice/UI/Settings/SettingsView.swift   |   4 +-
 2 files changed, 150 insertions(+), 1 deletion(-)
```

---

### Task 9: docs: MCP server checks and status

Files (A = new, M = changed):

```
M	AGENTS.md
M	docs/ROADMAP.md
M	docs/progress/HANDOFF.md
A	docs/progress/mcp-log.md
```

- [ ] **Step 1: Apply the patch.** Run exactly:

```bash
cd /Users/cong.bui/Kael/19-AppBuild/BugVoice-mcp
git am --3way docs/superpowers/plans/2026-10-17-mcp-server-luna/task-09.patch
```

Expected: `Applying: docs: MCP server checks and status` and exit status 0. If it fails, run `git am --abort`, stop, and report the full output. Do not edit code to make it apply.

- [ ] **Step 2: Run the tests.**

```bash
swift test
```

Expected: every `Test run with … passed` line (two before Task 3, three from Task 3 on). If anything fails, stop and report the failing test names and output. Do not change code.

- [ ] **Step 3: Check the commit.** `git log --oneline -1` shows `docs: MCP server checks and status`. `git am` already made the commit; do not commit again.

Diff summary:

```
AGENTS.md                |   2 +
 docs/ROADMAP.md          |   5 +-
 docs/progress/HANDOFF.md |  12 +++++
 docs/progress/mcp-log.md | 116 +++++++++++++++++++++++++++++++++++++++++++++++
 4 files changed, 133 insertions(+), 2 deletions(-)
```

---
## Task 10: Final checks and report

- [ ] **Step 1:**

```bash
swift test
Scripts/build-app.sh
codesign --verify --strict build/BugVoice.app && echo signed-ok
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"luna"}}}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | build/BugVoice.app/Contents/MacOS/bugvoice-mcp
git log --oneline main..HEAD
```

Expected:
- tests: `Test run with 856 tests … passed`, `Test run with 30 tests … passed`, `Test run with 93 tests … passed`;
- build exit 0 and `signed-ok`;
- the pipe prints two JSON lines: the first has `"protocolVersion":"2025-06-18"`, the second lists 12 tools (`list_folders` … `summarize_meeting`); it must not launch BugVoice;
- `git log` shows exactly 9 commits, Task 1 first.

- [ ] **Step 2: Report** to the maintainer: the 9 commit SHAs and subjects, the three test totals,
the build result, and any step that did not match its Expected line. The device checks in
`docs/progress/mcp-log.md` are for the maintainer; do not run them.
