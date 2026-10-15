# Models per Feature — Design

Date: 2026-10-15. Roadmap item 3 (`docs/ROADMAP.md`).
Mockup: `docs/design/proposal-models.html`.
Prior art: BugMind's connections + "Use for" settings
(`~/Kael/19-AppBuild/BugMind/src/lib/aiSettings.ts`,
`docs/system-design/ai/providers-and-keys.md`, CLI flags in
`src-tauri/src/local_agent.rs`).

## 1. Goal

Settings → **Models** replaces Settings → Text model:

- **Connections**: any number of model servers, each with its own address, default model and its own Keychain key. Kinds: LM Studio, Ollama, MLX server (local), Anthropic, OpenAI, OpenRouter (cloud), custom OpenAI-compatible or Anthropic-compatible server. Apple Intelligence is listed when available.
- **Use for**: one row per feature that picks its engine — Dictation cleanup, Notes dictation, Meeting notes.
- **Coding CLIs**: `claude`, `codex`, `pi`, run as subprocesses with their own logins, offered for Meeting notes only.

Success: dictation keeps using local Qwen in LM Studio with no change after upgrade; meeting summaries can use Anthropic with a key, or `claude` with its own login; LM Studio and OpenAI keep separate keys.

### Out of scope

- Gemini (API or CLI).
- Streaming answers; vision; image models.
- Per-style models (Style page keeps one dictation model).
- Rows for features that do not exist yet (Ask AI, file upload). They add rows later.

## 2. Concepts

| | Connection | Coding CLI | Apple Intelligence |
|---|---|---|---|
| What | HTTP server + default model + key | `claude` / `codex` / `pi` subprocess | On-device model (macOS 26) |
| Key | Keychain, account `connection-<id>` | None in BugVoice (CLI's own login) | None |
| Allowed for | Every feature | Meeting notes only | Every feature |
| Latency | 0.3–3 s | Several seconds per call | ~1 s |

## 3. Data

### 3.1 Settings

`AppSettings.textModel` is replaced by `AppSettings.models: ModelSettings` (key `models` in `settings.json`):

```json
"models": {
  "connections": [
    { "id": "lmstudio-1", "name": "LM Studio", "kind": "openAICompatible",
      "baseURL": "http://localhost:1234", "model": "qwen3.8-27b-mlx" },
    { "id": "anthropic-1", "name": "Anthropic", "kind": "anthropic",
      "baseURL": "https://api.anthropic.com", "model": "claude-sonnet-5-5" }
  ],
  "dictation": { "engine": { "connection": "lmstudio-1" }, "model": "", "disableThinking": true, "effort": "" },
  "notes": null,
  "meetings": { "engine": { "cli": "claude" }, "model": "", "disableThinking": false, "effort": "medium" },
  "dictationTimeoutSeconds": 3
}
```

- `ModelConnection`: `id` (lowercase letters, digits, `-`; unique; never starts with `cli-`), `name`, `kind`, `baseURL`, `model`.
- `ConnectionKind`: `openAICompatible`, `anthropicCompatible`, `openAI`, `anthropic`, `openRouter`.
- `ModelEngine`: `connection(id)`, `cli(CLITool)`, `appleIntelligence`, `none`. `CLITool`: `claude`, `codex`, `pi`.
- `ModelUse`: `engine`, `model` (empty = connection default; ignored for Apple Intelligence), `disableThinking` (API engines), `effort` (CLI engines; empty = CLI default).
- `notes: ModelUse?` — nil means "Same as Dictation".
- `dictationTimeoutSeconds`: 3, 5 or 8 (was `textModel.timeoutSeconds`); applies to Dictation and Notes dictation.
- Tolerant decoding, like every other settings type: an unreadable connection drops only itself; at most 20 connections; duplicate ids keep the first.
- A `cli` engine on the Dictation or Notes row decodes as `none` (CLIs are too slow there).

Fixed addresses (the stored `baseURL` is ignored for these kinds):

| Kind | Address used |
|---|---|
| `openAI` | `https://api.openai.com` |
| `anthropic` | `https://api.anthropic.com` |
| `openRouter` | `https://openrouter.ai/api` |

Presets for new connections:

| Menu item | Kind | Address | Key field |
|---|---|---|---|
| LM Studio | openAICompatible | `http://localhost:1234` | hidden |
| Ollama | openAICompatible | `http://localhost:11434` | hidden |
| MLX server | openAICompatible | `http://localhost:8080` | hidden |
| Anthropic | anthropic | fixed | shown |
| OpenAI | openAI | fixed | shown |
| OpenRouter | openRouter | fixed | shown |
| OpenAI-compatible server | openAICompatible | typed | shown |
| Anthropic-compatible server | anthropicCompatible | typed | shown |

Address rules for typed addresses:
- `http` or `https` only; host required; no user or password in the URL; no query or fragment.
- Plain `http://` only to `localhost`, `127.0.0.1` or `::1` (parsed host, not string match). Otherwise the sheet shows "Use https:// for a server that is not on this Mac." and Save is disabled.
- Saving a changed address of a connection that has a key clears the key; the sheet says "Enter the key again for the new address." first.

### 3.2 Migration from `textModel`

When `settings.json` has `textModel` and no `models`:

| Old `provider` | New |
|---|---|
| `openAICompatible` | one connection, kind `openAICompatible`, name from preset address (LM Studio / Ollama / MLX server) or "OpenAI-compatible server" |
| `anthropicCompatible` | one connection, kind `anthropic` when the host is `api.anthropic.com`, else `anthropicCompatible`, name "Anthropic" / "Anthropic-compatible server" |
| `appleIntelligence` | no connection; engine `appleIntelligence` |
| `none` | no connection; engine `none` |

- The connection takes `baseURL` and `model`; id `migrated-1`.
- `dictation` and `meetings` both use it; `notes` = nil; `disableThinking` and `timeoutSeconds` carry over.
- Keys: the app copies Keychain account `openai` (or `anthropic`) to `connection-migrated-1` when the new account is empty, then deletes the old account. `speech-openai` is untouched.
- The next settings save writes only `models`.

## 4. Behaviour

### 4.1 Resolving a feature

`ModelResolver` (VoiceCore) turns settings + a feature into `ResolvedModel`: the engine to call, model id, `disableThinking`, timeout, and a short HUD name — or a reason it cannot run:

| Case | Result |
|---|---|
| engine `none` | no model (cleanup off; meetings show "Choose a model for Meeting notes in Settings → Models.") |
| `connection(id)` with no such connection | unavailable: "The connection for <feature> was deleted. Choose another in Settings → Models." |
| `cli` not found on this Mac | unavailable: "<tool> was not found on this Mac." |
| Apple Intelligence not available | unavailable: "Apple Intelligence is not available on this Mac" (as today) |

For dictation, unavailable behaves as today: raw text pasted, HUD "Raw — model unavailable". Notes dictation resolves `notes ?? dictation`.

### 4.2 HTTP requests

Same adapters as today, with:
- **OpenAI kind**: send `max_completion_tokens` instead of `max_tokens` and omit `temperature` (newer OpenAI models reject both). Other OpenAI-compatible kinds unchanged.
- **OpenRouter kind**: same body as OpenAI-compatible; also sends `X-Title: BugVoice`.
- `chat_template_kwargs` only for `openAICompatible` (local servers), as today.
- Requests that carry a key do not follow redirects (a redirect would re-send the key to another host); a 3xx becomes "The server redirected the request. BugVoice does not follow it with a key."
- Error text never repeats the provider's response body when a key was sent (it can echo the request). Status → plain sentence: 401/403 "The key was refused.", 404 "The model or address was not found.", 429 "The service is rate limiting requests.", 5xx "The service had an error."
- Timeouts: dictation/notes use `dictationTimeoutSeconds`; meeting notes 120 s per call to a cloud address, 600 s to localhost (a local model may think for minutes).

### 4.3 Coding CLIs

`CLITextModel` (VoiceCore, `TextModel`) runs one call as a subprocess through an injected `ProcessRunner`:

- **Finding the tool**: `/bin/zsh -lc 'command -v <tool>'` (a Finder-launched app has a short PATH), cached until Settings → Models is opened again. Version from `<tool> --version`, shown in the CLIs card.
- **Prompt**: system prompt, a blank line, then the user text, on stdin. Never as an argument.
- **Working directory**: a fresh temporary folder, deleted after the call.
- **Arguments** (BugMind's hardened sets, re-measured on this Mac before use):

| Tool | Arguments | Answer |
|---|---|---|
| `claude` | `-p --output-format json --restricted --strict-mcp-config [--model M] [--effort E] --disallowed-tools <BugMind's list>` | JSON `result` field |
| `codex` | `exec -s read-only --skip-git-repo-check -C <tmp> --output-last-message <tmp>/answer.txt [-m M] [-c model_reasoning_effort="E"] -` | contents of `answer.txt` |
| `pi` | `-ne -nt --mode json [--model M] [--thinking E] -p` | last `message_end` event with role `assistant` |

- A model or effort starting with `-` is dropped (it would be read as a flag).
- Effort lists: claude `low medium high xhigh max`; codex `minimal low medium high`; pi `off minimal low medium high`.
- Timeout 600 s per call. Cancel (meeting generation cancelled) terminates the process.
- Exit status ≠ 0 or no answer: "<tool> did not return an answer." plus the last 300 characters of stderr.
- Meeting notes split the transcript into parts as today; each part is one CLI call.

### 4.4 Test connection

Lists models with `GET {base}/v1/models` (existing `ModelCatalog`), never a generation. Shows "Reachable · N models" or the error sentence from §4.2. The model list fills the sheet's **Choose…** menu. The connection list shows each connection's last test result for this session (not stored).

## 5. UI

Follows the mockup.

- **Settings tabs**: General, Speech, **Models**, Meetings, Storage (Text model removed).
- **Use for card**: rows Dictation cleanup ("Answer within N s or raw text is pasted" with the timeout picker 3/5/8 s), Notes dictation (first option "Same as Dictation"), Meeting notes. Each row: engine picker (connections by name, then Apple Intelligence when available, then None; Meeting notes adds a "Coding CLIs" group), model field (placeholder = connection default), thinking picker (API engines: "Thinking off" / "Thinking on") or effort picker (CLI), status dot (last test; grey when unknown). Note under the card: "Coding CLIs take several seconds per call, so they are offered for Meeting notes only. Text goes to a cloud service only when a feature uses a cloud connection."
- **Connections card**: rows with name, address · model, kind · key state ("key saved", "no key needed", "no key yet"), status, **Edit**. **+ Add connection** menu per §3.1 presets.
- **Edit sheet**: Name, Kind (read-only), Address (read-only for fixed kinds), API key (SecureField, hidden for local presets; **Remove**), Default model + **Choose…**, **Test connection**, **Delete** (existing only), **Cancel**, **Save**. Deleting a connection a feature uses leaves that row pointing at it; the row shows "Choose a model".
- **Coding CLIs card**: per tool, path and version, or "Not found". Status text: claude "tools and MCP servers turned off", codex "read-only sandbox", pi "extensions and tools turned off".
- **Test sentence**: the existing "Send test sentence" moves under the Dictation row and runs the Dictation engine.
- **Menu bar**: "Text model" picker becomes "Dictation model" listing connections, Apple Intelligence (when available) and None; it sets the Dictation row's engine.
- **HUD**: "Cleaning (Qwen)" uses the resolved model id's short name as today; for a connection with no model it uses the connection name.

## 6. Components

### 6.1 VoiceCore (Foundation only, TDD)

| Unit | Responsibility |
|---|---|
| `ModelConnection`, `ConnectionKind`, `ModelEngine`, `CLITool`, `ModelUse`, `ModelSettings` | Records, tolerant decoding, limits (§3.1) |
| `LegacyTextModelMigration` | `textModel` → `ModelSettings` (§3.2), returns key moves `[(from: String, to: String)]` |
| `ConnectionAddress` | Fixed addresses, address rules, effective base URL |
| `ModelResolver` | Feature → `ResolvedModel` or unavailable reason (§4.1) |
| `OpenAICompatibleModel` (modify) | OpenAI kind body; OpenRouter header |
| `HTTP` (modify) | No-redirect session for keyed requests; status sentences |
| `CLIArguments` | Argument lists and model/effort checks per tool (§4.3) |
| `CLIOutput` | Parse claude JSON, codex answer file, pi JSONL |
| `CLITextModel` + `ProcessRunner` protocol | Run one call; timeout; cancellation |
| `DictationPipeline` (modify) | Takes `ResolvedModel` instead of reading `settings.textModel` |

### 6.2 App

| Change | Where |
|---|---|
| `ProviderFactory.textModel(for: ResolvedModel, keychain:)`; Keychain account per connection; `FoundationProcessRunner` (Process, stdin pipe, terminate on cancel) | `ProviderFactory.swift`, `BugVoiceMac` |
| Migration key copy at bootstrap; `makePipeline` resolves Dictation or Notes; meetings resolve Meeting notes | `AppModel.swift`, `DictationController.swift` |
| `ModelsTab`, `UseForCard`, `ConnectionsCard`, `ConnectionSheet`, `CLIsCard`; delete `TextModelTab` | `Sources/BugVoice/UI/Settings/Models/` |
| "Dictation model" picker | `MenuContent.swift` |
| `CLILocator` (zsh lookup + version, cached) | `Sources/BugVoice/` |

## 7. Testing

VoiceCore (failing test first):
- `ModelSettings`: round trip; unreadable connection dropped; 21st connection dropped; duplicate id keeps first; `cli-` id rejected; CLI engine on Dictation decodes as `none`; `notes` nil.
- Migration: each old provider; preset names; Anthropic host → `anthropic` kind; key moves; existing `models` wins over `textModel`.
- `ConnectionAddress`: fixed kinds ignore stored URL; http to localhost/127.0.0.1/::1 allowed; http to `localhost.example.com` and LAN IP rejected; userinfo, query, fragment rejected.
- `ModelResolver`: each row of §4.1; Notes falls back to Dictation; timeouts per §4.2.
- `OpenAICompatibleModel`: OpenAI kind sends `max_completion_tokens`, no `temperature`; OpenRouter sends `X-Title`; local kind unchanged.
- `HTTP`: keyed 3xx not followed; status sentences; body not echoed when a key was sent.
- `CLIArguments`: exact lists per tool; `-model` dropped; unknown effort dropped; prompt never in arguments.
- `CLIOutput`: claude JSON `result`; codex answer file; pi last assistant `message_end` (not the user's); malformed → error.
- `CLITextModel` with a fake runner: stdin = system + blank line + user; non-zero exit → error with stderr tail; timeout; cancellation terminates.
- `DictationPipeline`: uses resolved model id, thinking flag and timeout; unavailable → raw with `.modelError`.

Manual checklist (append to `docs/testing/manual-checklist.md`, items 92–101):

| # | Check |
|---|---|
| 92 | Upgrade: dictation still uses LM Studio Qwen; Models tab shows one "LM Studio" connection used by all rows; old key moved |
| 93 | Add Anthropic with a key; Test connection lists models; set Meeting notes to it; generate a summary |
| 94 | Add OpenAI with a key; Dictation cleanup on a gpt model works (no max_tokens error) |
| 95 | Add OpenRouter with a key; Test connection lists models |
| 96 | Add Ollama; with Ollama not running the dot is grey or orange and dictation pastes raw text |
| 97 | Custom server at `http://192.168.1.5:8000` → Save disabled with the https message |
| 98 | Meeting notes with `claude`: summary generated; Activity Monitor shows the process gone after |
| 99 | Meeting notes with `codex` and with `pi`: summary generated |
| 100 | Cancel a CLI-backed generation: the process ends within 2 s |
| 101 | Menu bar "Dictation model" switches the Dictation row |
