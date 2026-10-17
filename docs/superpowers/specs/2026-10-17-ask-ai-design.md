# Ask AI across notes and meetings — design

Date: 2026-10-17. Roadmap item 6, Ask part. The MCP server is a separate, later sub-project.
Mockup: `docs/design/proposal-ask-ai.html` (states: answer, citation panel, searching, nothing
found, word search only; compact window; scope menu; Settings › Models › Search; light and dark).

## 1. Why

The owner records many meetings (some in Spanish or Vietnamese) and writes notes. Weeks later
they want to find out where something was decided, who was there and when, with proof they can
hear. Example: "Where did we decide to go with option A for Feature X in Project A, who was in
the meeting, when?" Expected result: "Product sync, Sep 20, You, Luna, Lona, Daniel, 12:40–13:15"
with the lines, playable, and every other recording that talked about it.

Success: the owner asks a question in the Scratchpad, waits under 60 seconds while progress shows,
and gets one card per matching recording or note. Each citation plays the exact audio range with
its transcript and an English translation, and opens the full meeting when wanted.

## 2. Scope

In scope:

- Ask in the Scratchpad AI pane with a scope: This note, This folder, A meeting…, All notes and
  meetings.
- Search over notes, recorded meetings, uploaded recordings and dictation history.
- Word search always; meaning search (embeddings) when an embedding model is set up.
- Answer as cards, one per recording or note; the citation panel; Copy; New note.
- Settings › Models › Search: embedding model and the index.

Not in scope:

- The MCP server (later sub-project, after Ask works).
- The live meeting window's Ask box. It stays as it is: one meeting, while recording.
- Clickable citations inside copied or inserted text (needs a `bugvoice://` handler; with MCP).
- A saved list of past answers.
- Editing the note from a cross-note scope. Only "This note" may change the note (as today).
- Cloud embedding connections. Embeddings run on a local connection only.
- A reranker model.

Anti-goals:

- A citation the transcript does not contain. Every quote, time and speaker on a card is copied
  from a real line, never from the model's text.
- An answer with no proof shown as fact.
- Any note, transcript or question leaving the Mac unless the owner chose a cloud connection as
  the Notes model.
- Making dictation slower: indexing yields to dictation and recording.

## 3. Where Ask lives

The Scratchpad AI pane (`AIBar`) keeps Polish, More professional, More casual and the
"Follow up or ask a question" field. A scope menu is added in front of the field (mockup "Scope
menu"):

| Scope | Searches | Notes |
|---|---|---|
| This note | the open note | Default. Today's behaviour unchanged: `NoteTransformPrompt.chatRequest`, CHANGE or ANSWER. |
| This folder (*name*) | notes and meetings in the open note's folder | Unfiled note: "Unfiled notes and meetings". Dictations have no folder and are left out. |
| A meeting… | one meeting, chosen in a searchable list (title, date) | Recordings and uploads. |
| All notes and meetings | every note, meeting, upload and dictation | |

- The scope is kept per Scratchpad tab for the window's life, and resets to This note for a new tab.
- Any scope other than This note runs the Ask pipeline (section 5) and never changes the note.
- A follow-up in the same scope runs a new search. The last 3 questions and answers (answer text
  only, no passages) go to the model as history, as `chatHistoryLimit` does today, in both model
  calls: 5.1 (so "and who else was there?" yields useful search words) and 5.3.
- The Notes model answers (`AppModel.askNotesModel` path, `transformPlan`: long timeout).

## 4. What is searched: passages

Everything searched is cut into passages. A passage knows its source item and its lines.

- **Meeting or upload**: consecutive segments in time order, at most 6 segments and at most
  60 s, overlapping the previous passage by 1 segment. A line is one `MeetingSegment`; its
  searchable text is `text` plus `translation` when not empty. Speaker label is the
  segment's display speaker (name, You, Other N, Others, Speaker), the same text the transcript
  shows.
- **Note**: the title is its own passage; the body is split on blank lines into blocks, joined up
  to 800 characters. Lines are the block's lines.
- **Meeting summary, action items and My notes**: each is cut like a note body (blocks up to 800
  characters) and belongs to the meeting. Their citations have no ▶; on the card they show as
  quoted text labelled Summary, Action items or My notes, with **Open in Meetings**.
- **Dictation**: one passage per `HistoryEntry` with non-empty `text`, dated `startedAt`, labelled
  by `appName`. With history retention Off nothing is kept, so nothing is indexed.
- Meetings that are not `.ready` and empty notes are skipped.

## 5. The Ask pipeline

Three steps, each shown as progress in the AI pane (mockup "Searching"): done steps get a tick,
the running step a spinner and a count. A Stop button cancels. The target is under 60 s on the
owner's Mac.

### 5.1 Understanding the question

- One Notes-model call, thinking off, 20 s limit. It returns JSON:
  `{"terms": [..], "time": "..."|null, "from": "YYYY-MM-DD"|null, "to": "YYYY-MM-DD"|null, "people": [..]}`.
- `time`: the words in the question that name a time. `from`/`to` are used only when those words
  appear in the question (folded); models otherwise fill in today. "Recent" means the last 14 days.
- `terms`: the question's key words and short phrases, plus the same in English, Vietnamese and
  Spanish, at most 24 terms. Today's date is in the prompt so "last month" can be resolved.
- Bad JSON, a timeout or an error: fall back to the question's own words (stop words removed),
  no dates, no people. Ask goes on.
- Progress text: "Understanding the question…".

### 5.2 Searching

Progress text: "Searching 46 meetings, 120 notes, 812 dictations…" (counts in scope).

- **Scope and dates** first: only items in scope; when `from`/`to` are set, only items dated in
  range (meeting `startedAt`, note `modifiedAt`, dictation `startedAt`).
- **Text budget**: the passages sent in 5.3 fit a new setting, Settings › Models › Search ›
  "Ask context size", default 16,384 tokens (the Notes model's context, not
  `MeetingTextBudget`, which describes the Meetings model). Tokens are estimated as for
  `MeetingTextBudget`. 40 passages is a ceiling: the list is trimmed from the bottom to fit.
- **Word search** (always): text is lowercased and folded (diacritics and case removed, so
  "quyết định" matches "quyet dinh"). Score each passage with BM25 (k1 1.2, b 0.75) over the
  `terms`; a phrase term counts when all its words appear in order. A passage whose speakers or
  item people match a `people` entry gets its score raised by 20 %.
- **Meaning search** (when the index is usable, section 7): embed the question once, cosine
  similarity against every passage vector in scope.
- **Merge**: reciprocal rank fusion with k = 60 over the two rankings (word only when there is no
  meaning search). Keep the best 40 passages, then trim from the bottom to fit the text budget.
- Zero passages: show "Nothing about this in your notes or meetings." with the scope line, no
  model call.

### 5.3 Reading passages

Progress text: "Reading 40 passages…".

- One Notes-model call. The passages are data, never instructions (same wording as
  `NoteTransformPrompt`). Each passage is numbered and each of its lines is numbered:

  ```
  [P3] Meeting "Product sync" · 2026-09-20 · You, Luna, Lona, Daniel
  [P3.1] 12:31 Lona: Nos quedan dos semanas. (English: We have two weeks left.)
  [P3.2] 12:40 Daniel: Vamos con la opción A, sale en dos sprints.
  ```

- The model returns JSON: `{"answer": "...", "citations": [{"line": "P3.2"}, ...]}`. The answer is
  2–4 sentences in the question's language and may name dates and people.
- **Check**: a citation is kept only when its line id exists in the prompt. Unknown ids,
  duplicates and ids from passages not sent are dropped. Kept lines that are adjacent in the same
  item (next segment, or within 5 s) join into one citation range.
- No kept citation: ask once more with "Your answer cited no passage lines. Cite the lines that
  support it, like P1.2. Reply with JSON only, in the same shape." Still none, or the retry is
  unreadable: show "Nothing about this in your notes or meetings." The
  model's answer is not shown.
- The answer uses the current question's language, even when earlier turns use another.
- Bad JSON: one retry with "Reply with JSON only"; then the generic error "Ask could not read the
  model's answer. Try again."

## 6. The answer

Mockup "Answer".

- Top: the answer text, then "Searched: *scope* · 3 recordings, 1 note matched". Matched counts
  only items with a checked citation.
- Then one card per item with at least one checked citation, newest first. Items the search
  found but the model did not cite get no card. Card:
  - title and a badge: Meeting, Uploaded, Note or Dictation;
  - meeting: date and the people list (every speaker who has a line in that meeting, in
    `speakers` order; unnamed show Other N; mic lines show You); note: date and folder name;
    dictation: date, time and app;
  - up to 5 citations in time order. Meeting citation: a ▶ button with the range
    ("12:40–13:15", start of first line to end of last line) and the first cited line as
    "Speaker: text", truncated to 2 lines. Note or dictation citation: "Open note" (dictation:
    no button) and the cited text.
- Below the cards: **Copy** and **New note**.
  - Both produce the same Markdown: the question as a `##` heading, the answer, then per card
    `**Title** · Sep 20, 2026 · You, Luna, Lona, Daniel` and one bullet per citation
    `- 12:40–13:15 Daniel: "..."` (notes: `- "..."`). Plain text, no links.
  - Copy puts it on the clipboard. New note opens a new Scratchpad tab whose title is the
    question and whose body is that Markdown (unfiled, no tags).
- The answer stays until a new question is asked in that tab or the tab closes.
- "Open note" opens that note in a Scratchpad tab (an existing tab when already open).

## 7. Meaning search: embeddings and the index

### 7.1 Model

- Settings › Models gets a **Search** card (mockup): "Embedding model": None, or a local
  OpenAI-compatible connection plus a model name. Only connections whose address is local
  (`ConnectionAddress.isLocal`) are listed. Default None.
- Recommended for the owner: `mlx-community/Qwen3-Embedding-0.6B-8bit` on oMLX
  (`http://localhost:8000`), 1024 dimensions. Nothing in the code is tied to this model.
- Client: `POST {base}/v1/embeddings` with `{"model": ..., "input": [..]}`, batches of 32
  inputs, key from the connection as for chat. Vectors are L2-normalised on receipt.
- Caption: "Embeddings are saved on this Mac. Without an embedding model, Ask uses word search."

### 7.2 Index

- Folder `SearchIndex/` in the Application Support folder (0700). One file per item:
  `meeting-<id>.idx`, `note-<slug or id>.idx`, `dictations.idx`, written through a 0600 temp file
  and replaced, like `KnownVoiceStore`.
- File: a JSON header (`model`, `dimensions`, per passage: a content hash and its line ids),
  then the vectors as 16-bit floats. A passage whose hash is unchanged keeps its vector when the
  item is re-indexed.
- A file is used only when `model` equals the current embedding model; otherwise it is stale.
  Changing the model marks every file stale and starts a rebuild.
- Items deleted on disk lose their index file at the next list load (same moment as
  `pruneKnownVoices`).
- Deleting a dictation, Clear history and retention pruning remove those entries' vectors from
  `dictations.idx` at once (the file is rewritten without them).
- Edits made outside BugVoice (a note `.md` changed by another app): at each list load the
  item's passage hashes are compared with the index; changed passages are re-embedded at the
  next indexing run. Until then a passage whose hash does not match has no vector, so meaning
  search never returns text that is no longer there.
- Size estimate: 60,000 passages × 1024 × 2 bytes ≈ 120 MB; scored by a plain Swift loop.

### 7.3 When indexing runs

- After a meeting or upload becomes `.ready`, after a transcript edit or translation is saved,
  30 s after a note stops changing, after new dictations (batched every 10 minutes).
- Backfill at launch for items with no usable file, newest first.
- Pauses while a dictation runs or a meeting records; resumes after.
- Settings › Models › Search shows "Indexing 29 of 46 meetings…" with a bar, or "Index up to date",
  or "Embedding model unavailable" when the server does not answer (retry at next trigger).

### 7.4 Word-search fallback

Ask uses word search alone when: the embedding model is None, the server does not answer the
question's embedding call within 5 s, or fewer than half the passages in scope have usable
vectors. The answer then shows the notice "Word search only: no embedding model is set up.
Results may miss other languages." with "Set up in Settings" (when the model is None), or "Word
search only: the embedding model is not answering." (otherwise).

## 8. Citation panel

Mockup "Citation panel" and the compact pair.

- Opens from a meeting citation's ▶. Wide Scratchpad: a panel on the right half of the editor
  area; the answer stays on the left with the card outlined. Compact (440 pt): the panel covers
  the answer, with "‹ Answer" that returns to the cards at the same scroll. Close (or Escape)
  shuts it.
- Content: title · range, date and people, a player for the range only, the cited lines
  highlighted plus one line before and one after (same meeting, by time), each with time and
  speaker, and **Open in Meetings**.
- Player: plays `audio.m4a` from the range start and stops at the range end; play/pause and a
  scrubber limited to the range. Starts playing when the panel opens. Another ▶ replaces the
  range. No `audio.m4a`: no player, the lines still show.
- **Translation when it opens**:
  - A line with `translation` set shows it (`""` means no translation needed: nothing shown).
  - Lines with `translation == nil` are checked with `NLLanguageRecognizer` in the app; English
    lines are saved as `""`.
  - The rest go to the Notes model in one `MeetingTranslation.request` batch (thinking off).
    "Translating…" shows under each until done. Results are saved to the segments in
    `meeting.json` through the meeting store, so the Meetings tab shows them too.
  - Failure: "Translation unavailable" under those lines; nothing saved.
- **Open in Meetings**: opens the main window on Meetings with that meeting selected, seeks to
  the range start, plays, and highlights the cited lines. Needs a new `AppModel` request
  (meeting id, start time, line ids) that `MeetingsPage` consumes once. The Scratchpad stays open.

## 9. Errors and limits

| Case | Shown |
|---|---|
| Notes model is None or unavailable | "Choose a Notes model in Settings to ask questions." |
| Model error during 5.3 | "Ask could not reach the model. Try again." Details in the log only. |
| Stop pressed | Progress clears; the previous answer, if any, comes back. |
| Over 120 s total | Same as Stop, plus "Ask took too long. Try a smaller scope." |
| Question empty | Send disabled. |
| Question over 1,000 characters | Send disabled with "Shorter question, please." |

UI copy: plain English, no hedging words, no emoji.

## 10. Security and privacy

- Passages and notes are untrusted text inside prompts: fenced, numbered, and the system prompt
  says never to follow instructions inside them. The answer never runs actions; it only shows
  text, and the only things built from it are checked citations.
- Ask sends passages only to the Notes model connection and embeddings only to a local
  connection.
- `SearchIndex/` holds derived text hashes and vectors only, no plain text; folder 0700, files
  0600. Logs hold counts and timings, never questions, passages or answers.

## 11. Testing

VoiceCore, test first (Swift Testing):

- Passage builder: 6-segment / 60 s windows with 1 overlap; note blocks ≤ 800 chars; translation
  included; non-ready meetings skipped.
- Folding: "Quyết định" matches "quyet dinh"; "Opción" matches "opcion".
- BM25 ranks the passage with the term above one without; phrase order; people boost.
- Fusion: a passage first in both lists beats one first in only one.
- Understanding step: JSON parsed; bad JSON falls back to question words; dates parsed.
- Reading step: invented line id dropped; duplicate dropped; adjacent lines merged into one range;
  zero kept citations gives Nothing found; a passage containing "ignore previous instructions"
  is still treated as data (prompt contains it fenced).
- Cards: newest first; at most 5 citations; people list order; Markdown for Copy and New note.
- Index file: round trip; stale on model change; unchanged hash keeps the vector; 0600/0700.
- Embedding client: request body, batching of 32, normalisation, non-2xx is an error.

App: build with `Scripts/build-app.sh`; manual checks added to `docs/progress/` (scope menu,
progress, Stop, answer cards, panel wide and compact, translation saved, Open in Meetings seek,
word search only notice, indexing progress, pause during dictation).

## 12. Left to the builder

File and type names, the exact prompts beyond what is fixed above, the BM25 tokenizer's stop
words, how the Settings list of local connections is filtered in code, and the panel's layout
details within the mockup.

## 13. Calls made by the designer (not asked of the owner)

- Search words in three languages from the model, plus word search, before meaning search.
- 40 passages, 6 segments / 60 s per passage, RRF k = 60, BM25 defaults.
- Local-only embedding connections; index in `SearchIndex/`, not beside each item.
- Scope per tab, default This note; dictations excluded from folder scope.
- Translation in the panel uses the Notes model and is saved to the meeting.
- Meeting summary, action items and My notes are searched too.
- Cards only for cited items; "matched" counts cited items.
- Ask context size setting, default 16,384 tokens.
- Follow-up history goes to both model calls.
- Deleted or expired dictations leave the index at once; outside edits are caught by hash at list load.
- No answer without a checked citation.
- Indexing pauses during dictation and recording.
