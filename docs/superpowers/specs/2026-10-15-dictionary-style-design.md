# Dictionary, Snippets and Style — Design

Date: 2026-10-15. Roadmap item 2 (`docs/ROADMAP.md`).
Mockup: `docs/design/proposal-dictionary-style.html`.

## 1. Goal

Two new main-window pages:

- **Dictionary** with two tabs:
  - **Dictionary**: words BugVoice must spell right (names, tools, acronyms), each with optional *heard as* forms that are replaced by the word.
  - **Snippets**: a spoken trigger phrase is replaced by saved text (links, sign-offs, prompts), pasted exactly.
- **Style**: six styles chosen by the app being dictated into (Personal messages, Work messages, Email, Document, Terminal, Other), each with its apps, cleanup switch, tone rules and an example.

They replace Settings → Vocabulary and Settings → Styles.

Success: add "OpenWhispr" heard as "open whisper" and it comes out right in every app; say "my linkedin" in Slack and get the exact saved URL inside a cleaned Work message; Slack gets Work tone and Zalo gets Personal tone without setup.

### Out of scope

- Telling personal from work inside one app (e.g. a personal Slack DM). Style is per app or website.
- Per-style models (roadmap item 3), import/export of the dictionary, sharing.

## 2. Concepts

| | Dictionary | Snippets | Style |
|---|---|---|---|
| Unit | word + heard-as forms | trigger → text | tone for a whole dictation |
| Scope | every app | every app | chosen by app |
| Done by | WhisperKit hint, text-model hint, exact replace | exact replace (no AI) | text model |
| Text model off | still applied | still applied | skipped |

## 3. Data

### 3.1 `dictionary.json`

`~/Library/Application Support/BugVoice/dictionary.json` (`AppPaths.dictionary`):

```json
{
  "schemaVersion": 1,
  "words": [
    { "id": "6F1C…", "word": "OpenWhispr", "heardAs": ["open whisper", "open whispers"] }
  ],
  "snippets": [
    { "id": "9A20…", "trigger": "my linkedin", "text": "linkedin.com/in/kael" },
    { "id": "B7D4…", "trigger": "sign off", "text": "Best,\nKael · kael@example.com" }
  ]
}
```

Rules:
- `word` and `trigger` are trimmed; empty ones are rejected.
- Words are unique case-insensitively; adding an existing word does nothing.
- Triggers are unique case-insensitively; a duplicate trigger is rejected with "A snippet with this trigger already exists."
- A heard-as form equal (case-insensitively) to its own word is dropped.
- Snippet text keeps line breaks and is never trimmed inside; leading/trailing whitespace is trimmed.
- Order: newest first in each list.
- Damaged file: rename to `dictionary.corrupt-<unix>.json`, start empty, alert "Dictionary file was damaged and has been reset. The old file is kept next to it." Newer `schemaVersion`: read-only, pages show "Dictionary was saved by a newer BugVoice." and editing is disabled.

### 3.2 Migration from `vocabulary.txt`

On launch, if `dictionary.json` does not exist and `vocabulary.txt` does:
- each plain line → a word (no heard-as);
- each `spoken => written` line → a snippet (`trigger` = spoken, `text` = written with `\n` as line break);
- comments and blank lines are skipped;
- write `dictionary.json`, then rename `vocabulary.txt` to `vocabulary.migrated.txt`.

If neither exists, start empty. BugVoice no longer creates `vocabulary.txt`.

### 3.3 Styles

`Style` becomes: `personal`, `work`, `email`, `document`, `terminal`, `other`. `chat` is removed.

Legacy `chat`:
- Decoding a `Style` from `"chat"` yields `.personal` (history lines and anything else stored with a style keep loading).
- `StyleSettings` decoding: `appOverrides` value `"chat"` → the bundle's built-in style if it is `.personal` or `.work`, else `.personal`. `customRules["chat"]` and `cleanupEnabled["chat"]` are copied to `personal` and `work` when those keys are absent, then removed.
- Insights `wordsByStyle` keeps `"chat"` keys as recorded; the By style panel labels a key with no matching style "Chat (old)".

Display names: Personal messages, Work messages, Email, Document, Terminal, Other.

Default rules (`PromptBuilder.defaultRules`):

| Style | Rules |
|---|---|
| personal | Casual and warm. Remove filler words, add light punctuation, keep slang and the speaker's wording. No greeting or sign-off unless spoken. |
| work | Clear and short. Remove filler words, apply self-corrections such as "no, I mean" or "à không" by keeping only the corrected version, keep technical terms. One short paragraph; when the speaker lists items, use bullets. |
| email | unchanged |
| document | unchanged |
| terminal | unchanged |
| other | unchanged ("Light touch…") |

Cleanup defaults: unchanged (terminal off, others on).

### 3.4 Routing (`StyleRouter`)

Order unchanged: user override → editor terminal panel → website rule → built-in app → `.other`.

Built-in apps (replacing the `.chat` entries; others unchanged):

| Style | Bundle IDs |
|---|---|
| personal | `com.apple.MobileSMS`, `com.vng.zalo`, `net.whatsapp.WhatsApp`, `ru.keepcoder.Telegram`, `com.hnc.Discord`, `com.facebook.archon` (Messenger) |
| work | `com.tinyspeck.slackmacgap`, `com.microsoft.teams2`, `com.microsoft.teams`, `com.electron.lark` |

Website rules (added to the existing ones; `app.slack.com` changes from chat to work):

| Host | Style |
|---|---|
| `web.whatsapp.com`, `messenger.com`, `discord.com`, `web.telegram.org`, `chat.zalo.me` | personal |
| `app.slack.com`, `teams.microsoft.com`, `teams.live.com`, `chat.google.com` | work |

Bundle IDs not verified on the maintainer's Mac are checked during the device pass (`osascript -e 'id of app "Name"'`) and corrected if wrong.

## 4. Pipeline order

For every dictation (`DictationPipeline`):

1. Transcribe; Dictionary words are the Whisper prompt when `useVocabularyHints` is on (unchanged behaviour, now fed from Dictionary).
2. **Corrections**: every heard-as form → its word (whole-word, case-insensitive, NFC, longest first — the existing `Vocabulary.applyReplacements` algorithm).
3. **Protect snippets**: each trigger match → a placeholder `⟦S1⟧`, `⟦S2⟧`… in order of appearance. Remember placeholder → snippet text.
4. **Clean up** (when cleanup applies to the style): the system prompt adds "Tokens like ⟦S1⟧ are placeholders. Keep every one exactly once, unchanged, where it belongs." and the Dictionary words as "Spell these terms exactly" (existing line).
5. **Check placeholders**: if the cleaned text does not contain each placeholder exactly once, discard the cleaned text and continue with the step-3 text (outcome stays `inserted`; `rawReason` = `.placeholderLost`, shown in history like other raw reasons).
6. **Corrections again** on the text (the text model may re-split a word).
7. **Fill**: each placeholder → its snippet text, exactly.
8. Insert.

When cleanup is off (the master switch, or the style's switch — off by default for Terminal) or the model is unavailable: steps 4–5 are skipped; 6–7 still run.

Trigger matching:
- Whole words, case-insensitive, NFC on both sides.
- Between trigger words, any run of spaces or hyphens matches (Whisper may write "sign-off" for "sign off").
- Punctuation right after a trigger stays after the placeholder ("my linkedin." → "⟦S1⟧.").
- Longest trigger first; text already replaced is not re-scanned.

`raw` in the result and history stays the unmodified transcript. `cleaned` is the model output after step 6 with placeholders filled (nil when cleanup did not run or was discarded). `finalText` is what was inserted.

Snippet text never goes to the text model.

## 5. Pages

Layout follows the mockup. Sidebar order: Dictation, Insights, **Dictionary**, **Style**, Meetings, Notes, Settings. SF Symbols: Dictionary `character.book.closed`, Style `paintbrush.pointed`.

### 5.1 Dictionary page

Title "Dictionary"; `PillTabs` with **Dictionary** and **Snippets** (both enabled; icons optional).

**Dictionary tab**
- Hero card: title "Add words to your dictionary"; text "Names, tools and acronyms BugVoice should always get right. Add what it mishears them as, and those are fixed too."; add field placeholder "Add words separated by commas — OpenWhispr, Supabase, Kael" with an **Add** button (Return also adds). Hint: "Words also guide speech recognition and the text model." Right side: decorative illustration (two chips `~~open whisper~~ OpenWhispr`, `~~bug voice~~ BugVoice`, dashed rings, icon badge); hidden below 900 pt width.
- List card: header "N words" + search field (matches word and heard-as). Each row: word (bold), "Heard as" tags, "+ heard as" control that opens an inline field (Return adds, comma-separated allowed), each tag removable; **Edit** (rename word inline) and **Delete** (no confirmation; ⌘Z not required).
- Empty state: hero only, the list card shows "No words yet."

**Snippets tab**
- Hero: title "Stuff you shouldn't have to say twice"; text "Say a trigger phrase and BugVoice puts in what you saved: links, intros, sign-offs, prompts. The saved text is pasted exactly, never reworded."; add field placeholder "Add a trigger phrase — \"my linkedin\", \"cal link\"" with **Add**. Adding opens a sheet: Trigger (prefilled), Text (multi-line editor), **Save** / **Cancel**; Save disabled while text is empty. Illustration chips: `"Sign off" ↳ Best, Kael · kael@example.com`, `"My LinkedIn" ↳ linkedin.com/in/kael`.
- List: header "N snippets" + search (trigger and text). Row: “trigger”, `↳` text on one line with line breaks shown as ` ⏎ `, **Edit** (same sheet) and **Delete**.

### 5.2 Style page

Title "Style"; caption "Each app is matched to a style when you start dictating. The style sets how the text model cleans your words."

Left column: the six styles (name + short app summary). Right panel for the selected style:
- **Apps and websites**: built-in apps and website rules for the style plus the user's overrides into it; app names from the installed app (`NSWorkspace`) or the bundle ID if not installed. Each chip has **Move to…** (menu of the other five styles; writes an override). Overrides show a **Reset** item in that menu, which removes the override. **+ Add app** (open panel on /Applications) adds an override to this style. Other shows "Every app without a style uses Other." and no Add button.
- **Clean up with the text model** switch (`cleanupEnabled`).
- **Tone**: editor for the rules (`customRules`), **Reset to default**.
- **Example**: static "You say" / "BugVoice writes" pair per style (text from the mockup).

### 5.3 Settings

- Remove the Vocabulary and Styles tabs.
- Speech tab: toggle label "Use vocabulary as hints" → "Use Dictionary words as hints".
- Text Model tab prompt preview keeps working with the new styles.

## 6. Components

### 6.1 VoiceCore (Foundation only, TDD)

| Unit | Responsibility |
|---|---|
| `DictionaryWord`, `Snippet`, `DictionaryFile` | Codable records (§3.1) with tolerant decoding and the uniqueness/trim rules as mutating methods: `addWords(_ text: String)` (comma-separated), `addHeardAs(_:to:)`, `removeHeardAs`, `renameWord`, `deleteWord`, `addSnippet(trigger:text:) throws`, `updateSnippet`, `deleteSnippet`. |
| `DictionaryStore` (actor) | `load()` with damaged/newer handling, `save(_:)` atomic, `migrateIfNeeded(vocabularyURL:)` (§3.2). |
| `Vocabulary` (modify) | Built from a `DictionaryFile`: `terms` = words, `replacements` = heard-as → word, new `snippets: [Snippet]`. `Vocabulary.parse` stays for the bench tool and migration. |
| `SnippetExpander` | `protect(_ text:, snippets:) -> ProtectedText` (`text`, `fills: [String: String]`); `ProtectedText.isIntact(_ cleaned:) -> Bool`; `ProtectedText.fill(_ text:) -> String`. Trigger matching per §4. |
| `Style` (modify) | New cases, legacy `chat` decoding, `title`. |
| `StyleSettings` decoding (modify) | Legacy `chat` migration (§3.3). |
| `StyleRouter` (modify) | Tables in §3.4; `static func builtInApps(for: Style) -> [String]` and `websites(for: Style) -> [String]` for the Style page. |
| `PromptBuilder` (modify) | New default rules; placeholder instruction when the request contains a placeholder. |
| `DictationPipeline` (modify) | Order in §4; `RawReason.placeholderLost`. |
| `AppPaths.dictionary` | New URL. |

### 6.2 App

| Change | Where |
|---|---|
| `AppModel`: `dictionary: DictionaryFile`, `dictionaryReadOnly`, load + migrate at bootstrap (before `startDictation()`), edit methods that save and rebuild `vocabulary`; remove `vocabularyText` / `saveVocabulary` | `AppModel.swift` |
| `Page.dictionary`, `Page.style` | `AppModel.swift`, `MainWindow.swift` |
| `DictionaryPage` (tabs), `DictionaryWordsView`, `SnippetsView`, `SnippetEditorSheet`, `HeroCard` (shared hero layout with illustration) | `Sources/BugVoice/UI/Dictionary/` |
| `StylePage`, `StyleDetailView`, `StyleExamples` (static examples) | `Sources/BugVoice/UI/Style/` |
| Remove `VocabularyTab`, `StylesTab`; update `SettingsView`, `SpeechTab` label | `Sources/BugVoice/UI/Settings/` |
| Insights By style labels via `Style(rawValue:)?.title ?? "Chat (old)"` | `InsightsUsageView.swift` |

## 7. Testing

VoiceCore (failing test first):
- `DictionaryFile`: comma add with trimming and duplicates; heard-as add/remove/self-drop; rename; delete; snippet add/duplicate trigger error/update/delete; tolerant decode.
- `DictionaryStore`: missing file; round trip; damaged file renamed; newer schema read-only; migration from `vocabulary.txt` (terms, `=>` lines with `\n`, comments) and rename to `.migrated.txt`; no migration when `dictionary.json` exists.
- `SnippetExpander`: single and multiple triggers; case-insensitive; NFC Vietnamese trigger; hyphen-or-space between words; punctuation after trigger; longest first; no match inside a longer word; `isIntact` with missing, duplicated and changed placeholders; `fill` restores multi-line text exactly.
- `Style`: decodes `"chat"` as `.personal`; titles.
- `StyleSettings`: legacy chat override for Slack → work, for Zalo → personal; chat rules and cleanup flag copied to personal and work without overwriting existing keys.
- `StyleRouter`: every row of §3.4; override still wins; `builtInApps(for:)` and `websites(for:)`.
- `PromptBuilder`: new defaults; placeholder line present only when a placeholder is in the request.
- `DictationPipeline`: heard-as fixed before cleanup; snippet survives cleanup; model drops a placeholder → cleaned text discarded, `rawReason == .placeholderLost`, snippet still filled; cleanup off → snippet filled; terminal style → snippet filled, no model call; secure field unchanged behaviour.

Manual checklist (append to `docs/testing/manual-checklist.md`, items 81–90):

| # | Check |
|---|---|
| 81 | Dictionary page: add "OpenWhispr, Supabase" in one go; both rows appear, newest first |
| 82 | Add heard-as "open whisper"; dictate "open whisper is great" in TextEdit → "OpenWhispr is great" |
| 83 | Snippets: add "my linkedin" → URL; dictate "here is my linkedin" in Slack → cleaned sentence with the exact URL |
| 84 | Multi-line snippet "sign off" in Mail → line breaks kept |
| 85 | Snippet with LM Studio off → still expanded |
| 86 | Style page: Slack listed under Work, Zalo under Personal; dictation in each shows that tone |
| 87 | Move Telegram to Work; dictate in Telegram → Work tone; Reset returns it to Personal |
| 88 | Edit Work tone, Reset to default restores it |
| 89 | Existing `vocabulary.txt` with a term and a `=>` line migrates on first launch; file renamed |
| 90 | Settings has no Vocabulary or Styles tab; Speech tab reads "Use Dictionary words as hints" |
