# Meetings v2 (5b): live English translation — design

Date: 2026-10-16. Roadmap item 5, second sub-project. Follows 5a (meeting window, merged
`b4d309c`). Mockup: `docs/design/proposal-meeting-translation.html` (states: Transcript tab with
English lines, Show English off, no Meetings model, meeting detail page; light and dark).

## 1. Goal

Follow a meeting held partly in a language the owner reads slowly. The motivating case is the
monthly Spanish and English meeting; Vietnamese meetings work the same way.

What the owner chose (2026-10-16):

- Layout: under each line. The original line stays as it is; its English shows below it in a
  smaller grey line. English lines get no translation. A Show English switch hides the English.
- Trigger: automatic and live. Each new non-English line is translated as it arrives. On only
  when the meeting's languages include one other than English.
- Keep: saved with the meeting. The detail page Transcript shows the English under each line,
  and the Markdown export includes it.
- Model: the Meetings model (Settings › Models), the same one as the live summary and Ask.
  No new setting.

Not in scope:

- Translation into a language other than English.
- Uploaded files. Their transcript has no English lines; uploads may get a Translate button
  later.
- A Translate button for older meetings on the detail page.
- Translating summaries, notes or answers. The summary and Ask already answer in the language
  of the transcript or question.

## 2. Which lines are translated

A line needs English when all of these hold:

- The meeting's languages (`MeetingManifest.languages`) include a language other than English.
- Show English is on for the meeting (`MeetingManifest.showEnglish`, default on).
- The line has no translation yet (`MeetingSegment.translation == nil`).
- The line's text is not empty.

English lines are sent too, and the model returns them unchanged. Whisper's chunk language is
not used: in a test on 2026-10-16 it reported `en` for chunks of Spanish speech, which would have
skipped every line.

A translation that equals the original (ignoring case, spaces and punctuation) is saved as
an empty string: the line is done and shows no English. Mixed lines (Vietnamese with English
words) are translated whole.

## 3. Requests

- Batch: up to 12 lines, oldest first, one request at a time.
- System prompt:

  > You translate meeting transcript lines into English. Each input line starts with its
  > number. Return the same numbers, one line each, as `N. English text`. Keep names, product
  > names and technical terms as they are. When a line is already English, return it unchanged.
  > Return only the numbered lines.

- User message: the lines as `1. text`, `2. text`, … with newlines inside a line flattened to
  spaces.
- `maxTokens`: `min(budget.outputTokens, 2_048)`; `disableThinking: true`. Measured 2026-10-16 on
  the owner's Qwen 27B: 12 lines took 30 s with thinking and 6 s without, same English.
- Parse: each reply line that starts with `N.` or `N)` (after optional spaces) gives line N.
  Numbers out of range and empty texts are ignored. When a number repeats, the last one wins: a
  model that writes its reasoning into the reply puts the answer after it. Lines the reply
  left out stay without a translation and go into the next batch. A batch whose reply gave no
  usable line counts as a failure.

## 4. When

The meeting window's 1-second monitor tick calls `translateIfDue()`. It starts a request when:

- no translation request is running;
- dictation is not busy and not listening (dictation goes first on the same model, as for the
  live summary);
- the live summary is not refreshing and the final summary is not being written;
- after a failure, 30 seconds have passed;
- at least one line needs English (section 2).

It keeps running after Stop: the final transcript replaces the live lines (section 5), and the
lines still without English are translated after the final summary is written. It stops when no
line needs English, when Show English is turned off, or when a new meeting starts.

No Meetings model: no request; the Transcript bar shows "English needs a Meetings model." under
the switch while Show English is on.

## 5. Stop and the final transcript

At Stop the final pass replaces all lines. Before saving them, each final line takes the
translation of a live line on the same track whose text is equal (trimmed) and whose start is
within 1 second. Live and final passes both use 30-second chunks with a 1-second overlap, so
most lines carry over; the rest are translated after the final summary.

When the transcript merger trims words that repeat across a chunk boundary from a line, that
line's translation is cleared, so it is translated again from the new text.

## 6. Meeting window

### 6.1 Transcript tab

- Under each line with a non-empty translation, a second line: the English text, caption size,
  secondary colour, indented to the text column, selectable.
- A line waiting for English shows nothing extra (no spinner per line).
- Search matches the original and the English.
- Copy includes the English as `  English: text` under its line while Show English is on.

### 6.2 Show English switch

- In the Transcript bar, after Copy: a small switch labelled "Show English".
- Visible when the meeting's languages include a language other than English, or when any line
  has a translation.
- Off hides the English lines and stops new requests. On shows them and resumes requests.
- Saved on the meeting (`showEnglish`), so the detail page follows it.

## 7. Meeting detail page

- The Transcript tab shows the English under each line, as in 6.1, when Show English is on.
- A "Show English" switch sits above the transcript when any line has a translation. It saves
  `showEnglish` the same way as notes: through the meeting window's session while it owns the
  meeting, otherwise straight to the store.

## 8. Export

- Markdown: under each transcript line with a non-empty translation, a line
  `  English: <text>` (two spaces). Written regardless of Show English.
- SubRip captions and Send to Scratchpad stay as they are.
- Meeting search on the Meetings page also matches English lines.

## 9. Data

- `MeetingSegment.translation: String?` — nil: not translated; empty: done, nothing to show.
  Older files decode with nil.
- `MeetingManifest.showEnglish: Bool` — default true; older files decode with true.
- `MeetingSession.setTranslations(_: [String: String])` — sets `translation` on the segments with
  those ids; segments no longer present are ignored. Allowed while recording, paused,
  transcribing or ready (`acceptsNotes`).
- `MeetingSession.setShowEnglish(_:)` — same states.

## 10. Errors

- A failed request or an unusable reply: no message; the lines stay without English and the next
  try waits 30 seconds.
- No Meetings model: the caption in 4.
- Saving fails: the translations are dropped and the lines are sent again later.

## 11. Copy rules

Plain English, no hedging, no emoji. Strings: "Show English", "English needs a Meetings model.",
"English:" (export and Copy).

## 12. Tests (VoiceCore, TDD)

- `MeetingTranslation.pending`: skips lines with a translation (including empty), empty lines,
  meetings with only English, and Show English off; sends English lines too; oldest
  first; at most 12.
- `MeetingTranslation.request`: numbered lines, flattened newlines, system prompt, max tokens.
- `MeetingTranslation.parse`: `N.` and `N)` forms, out-of-range and repeated numbers ignored,
  missing lines left out, unchanged English saved as empty.
- `MeetingTranslation.carryOver`: equal text within 1 second on the same track carries over;
  other track, other text or a start 2 seconds away do not.
- Merger: a trimmed line loses its translation; an untouched line keeps it.
- Session: `setTranslations` and `setShowEnglish` save; refused when interrupted; Stop carries
  live translations over to the final lines.
- Manifest and segment: older JSON decodes with `translation == nil` and `showEnglish == true`.
- Export: Markdown writes the English line; an empty translation writes none.
- Search: `MeetingListProjection.matches` finds a meeting by its English.
