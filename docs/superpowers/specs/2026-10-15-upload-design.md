# Upload Audio/Video — Design

Date: 2026-10-15. Roadmap item 4 ([roadmap](../../ROADMAP.md)).
Mockup: [Upload page and uploaded meeting](../../design/proposal-upload.html).
Builds on [Meetings](2026-10-14-meetings-design.md) and
[Models per Feature](2026-10-15-models-design.md).

## 1. Goal

Drop or browse for audio/video files, transcribe on this Mac, and open each result
in Meetings. The Upload page follows the agreed mockup: choose files, review the
file card, press Transcribe, follow reading and transcription progress, then open
the saved meeting. Several files run one at a time.

Success: a long video becomes a timestamped meeting with an Uploaded badge,
Speaker labels, playable audio, Summary and Action items on demand, and exports.
Only extracted audio is retained; the original stays where it is and is never
copied or modified. Import and speech recognition send no audio or text off this
Mac unless Settings › Speech already uses a server the user configured, exactly
as for recorded meetings. On-demand meeting text generation follows the user's configured Meeting
notes provider; only an explicitly configured remote provider receives text.

### Out of scope

- URL/YouTube import; these remain deferred in the roadmap.
- Speaker detection (diarization), per-person names, or separated speakers.
- Folders (roadmap item 9), automatic summaries, transcript editing.
- Notes integration or sending uploaded text to Scratchpad (item 8).
- Ask AI, retrieval and MCP (item 6). Preserve segment timestamps so that later
  citations can refer to real audio ranges.
- ffmpeg, other decoders, or another dependency. Use AVFoundation and the existing
  WhisperKit dependency pinned to `exact: "1.1.1"`.

## 2. Concepts

| Concept | Meaning |
|---|---|
| Upload | A local file import job; the name does not mean a network transfer |
| Uploaded meeting | A `MeetingManifest` with `source == .upload`, stored in the existing Meetings library |
| File track | New `MeetingTrack.file`: one mono mix, labelled Speaker everywhere |
| Reading | Decode the asset into a durable PCM journal; no microphone or system capture |
| Transcribing | Run the existing chunk processor and merger, then finalize `audio.m4a` |
| Queue | New `UploadQueue`: a pure VoiceCore state machine that orders jobs and admits one at a time |

New names in this spec are implementation contracts. `UploadJob` is a queue entry
with a stable UUID, file name, media kind (Audio/Video), asset duration, byte size,
optional meeting ID, state, phase progress and optional error message.
`UploadJobState` has `queued`, `reading`, `transcribing`, `ready`, `failed`,
`cancelled`. The app owns file URLs and access lifetimes separately from this
pure state. A selection is a draft until Transcribe admits it to the queue.

## 3. Data

### 3.1 Manifest and compatibility

Add `MeetingSource` (VoiceCore, Codable): `recording` or `upload`.
Add `MeetingManifest.source: MeetingSource`,
`MeetingManifest.sourceFileName: String?` and `MeetingManifest.importedAt: Date?`.
New recorded meetings default to `.recording`, nil and nil. Uploaded meetings store the original last path component,
including extension, without its parent path. The name is display metadata, not
a path used for storage or recovery.

Keep `MeetingManifest.currentSchemaVersion == 1`. These are additive fields:
synthesized Decodable ignores unknown keys in older builds. The new manifest
decoder must explicitly default a missing `source` to `.recording` and a missing
`sourceFileName` and `importedAt` to nil; Swift property defaults alone do not provide that
Codable migration. All existing manifest fields retain their decoding semantics.

This is forward compatibility for recorded meetings, not downgrade support for
uploads: an older build cannot decode the new `MeetingTrack.file` raw value in
chunks or segments. Its current `MeetingStore.list()` can consequently fail to
load the library containing that upload. Do not claim schema 1 makes uploads
readable by older builds. No rewrite of existing recordings is required.

For an upload:

- `title`: original file name with the final extension removed.
- `startedAt`: valid media creation-date metadata, else filesystem creation date,
  else the import clock's current date. Invalid metadata falls through.
- `duration`: finite, positive asset duration, independent of decode time or
  time spent waiting. Align the extracted audio to that media timeline.
- `endedAt`: `startedAt + duration` (media end time, for display).
- `importedAt`: the import clock's date when the job is admitted. Retention
  counts from `importedAt ?? endedAt`, so an old recording imported today is
  kept for the full retention period, not pruned at the next launch.
- `audioFormat`: existing `MeetingAudioFormat`, 16 kHz mono, signed Int16
  little-endian journal PCM and final AAC.
- Every chunk and segment uses `.file`; marks are empty. `summary` and
  `actionItems` start nil. `MeetingSegment.speaker` returns "Speaker" for `.file`,
  "You" for `.mic`, and "Others" for `.system`.

### 3.2 Files and the durable boundary

Use `AppPaths.meetings/<MeetingID>/` and `MeetingStore.save(_:)` as today.
During reading the folder contains `meeting.json` and
`.capture/file.pcm` plus `.capture/checkpoint.json`, written through
`MeetingPCMJournalWriter`. Only the `.file` journal is started.

The staging manifest has `source == .upload` and `state == .interrupted`.
For uploads only, this combination means reading never committed and the folder
must be discarded at launch. It is not a recoverable recording. Do not introduce
a persisted `reading` MeetingState or reuse `.recording` and trigger capture.
Keep this staging entry out of the Meetings list.

After decoder EOF and successful final journal checkpoint, close the writer and
atomically save `state == .transcribing` before starting recognition. This is the
commit boundary: a launch sees either incomplete reading to discard, or complete
PCM to transcribe without needing the original file.

On success the folder contains `meeting.json` and `audio.m4a` (16 kHz mono AAC).
Finalize durably, save ready, then call `cleanupCapture()`. Never create
`mic.m4a` or `system.m4a` for an upload. Temporary output files and journals are
removed after their durable replacements succeed. Transcription failure also
produces `audio.m4a` before claiming the audio is saved, and keeps the journal
for Retry (§7).

Queue drafts and waiting file URLs are session-only; they do not survive quit.
Committed transcribing uploads are restored from manifests at launch. Recover
these in stable meeting-ID order before accepting newly queued jobs; no original
drop order across launches is promised. Ready/error queue history is session-only.

## 4. Behaviour

### 4.1 Choose and enqueue

Accept MP3, WAV, M4A, AIFF, CAF, MP4, MOV and M4V, case-insensitively.
AVFoundation must actually decode the contents; an allowed extension does not
promise support for every codec inside that container. Reject everything else
with the exact unreadable-file sentence in §7.

Drop over the whole Upload page or click the drop zone to open `NSOpenPanel`.
Set `allowedContentTypes` from the eight extensions using
`UTType(filenameExtension:)`, disallow other file types and directories, and
allow multiple selection. Do not use broad audio/movie types that admit extra
formats. Reject directory drops without traversing them. Keep file access alive
through reading and balance any security-scoped access when the job ends.

Load metadata asynchronously for the file card: original name, Audio or Video,
asset duration and file byte size. Video means the asset has a video track;
recognition still uses audio only. A readable asset with no audio gets the
no-audio error. An empty, invalid or non-finite-duration asset gets the unreadable
error. Probe only metadata for drafts; do not decode the entire asset here.

Transcribe submits the selected batch in drop/picker order. Single-file selection
shows the mockup's file card; a batch previews the same metadata per file with
one Transcribe/Cancel action for the batch. Files added to an existing queue use
the same confirmation before appending. Cancel on a draft clears that selection
and creates no meeting folder. Separate submissions of the same file are separate
jobs, each with its own meeting ID.

### 4.2 Queue and progress

`UploadQueue` accepts completion/progress/failure/cancellation events tagged with
job ID. Ignore stale callbacks from terminal jobs. Its transition contract is:

| Current | Event | Next |
|---|---|---|
| queued | First eligible job admitted | reading |
| reading | EOF, checkpoint and transcribing manifest committed | transcribing |
| transcribing | Transcript and audio saved ready | ready |
| reading / transcribing | Operation fails | failed |
| queued / reading / transcribing | User cancels and cleanup completes | cancelled |

Only one job owns the reading/transcribing slot, including while it waits for a
meeting. Terminal jobs release it; failure does not block the next file.
Clear finished removes ready, failed and cancelled queue entries only, never
saved meetings. Cancel of a waiting job removes it from pending work.

Reading progress is decoded media time divided by asset duration; transcription
progress is completed planned chunks divided by total chunks. Clamp each phase
to 0–1 and reset the displayed percentage at phase change. The sidebar ring
uses the same current-phase progress. Indicate activity while metadata or EOF
completion has no usable percentage. Keep the second phase active through
finalization and show Ready only after audio and manifest are durable.

### 4.3 Streaming and shared transcription

Use approach A. New `MediaAudioDecoder` (BugVoiceMac) uses `AVAssetReader` to
extract the asset's audio into 16 kHz mono PCM. Mix playable audio tracks/channels
into one `.file` timeline, including stereo and surround sources; preserve gaps
as silence and align sample zero with player time zero. Video frames are never
decoded or retained. Feed bounded PCM blocks to `MeetingPCMJournalWriter.append`
with offsets derived from media time, not wall time.

Bound both decoder buffers and outstanding writer work. `append` queues its
input asynchronously today; the decoder must await periodic `checkpoint()`
barriers before producing more blocks so the write queue cannot accumulate a
whole file. Checkpoint at least once per second of decoded audio and at EOF;
surface append failures before declaring reading complete. Never use
`committedData(for:)` or load a whole file into an `AudioClip`. A two-hour or
three-hour asset consumes bounded audio-buffer memory; manifests still grow
with transcript/chunk metadata. Do not impose the dictation time cap.

New `UploadAudioSourceControl` (BugVoiceMac) conforms to
`MeetingAudioSourceControl`. Its start/pause/resume/stop methods do no capture;
checkpoint/recover read or recover the file journal only. It never creates an
`AVAudioEngine`, process tap, or microphone/system permission request.

New `UploadTranscriptionScheduler` (app) conforms to
`MeetingTranscriptionScheduler`. It follows
`MeetingLiveTranscriptionScheduler.transcribeFinal`, but plans `.file` only with
`MeetingChunkPlanner.plan` (30 seconds, existing one-second overlap). Read one
range using `committedSamplesAsync(for:range:)`, call
`MeetingChunkProcessor.process`, and merge through `MeetingTranscriptMerger`.
Reuse timestamped auto language, configured-language fallback, silence gating,
placeholder/hallucination filtering and per-chunk attempts. Treat `.failed`
chunk records as transcript failure; silent `.empty` chunks are successful and
can produce a ready meeting with no transcript lines.

New `MeetingSession.transcribeUpload(_:)` accepts a fully read upload manifest,
persists its transcribing state and enters the existing private
`finishTranscription(_:)` path. It preserves media dates/duration and requires
`.upload`; it does not call `start()` or `stop()`, which currently start mic/system
sources or derive duration from elapsed recording time. Recovery uses
`recover(id:)` and `retryTranscription()` with the upload dependencies.

New `MeetingSession.persistFinal(_:)` checkpoints a final chunk result while
transcribing: replace the chunk with the same ID, merge completed results and
save atomically. The upload scheduler calls it before reporting progress.
Recover/retry reuse completed/empty records whose stable IDs, ranges and `.file`
track match the current plan; retry failed or absent ranges. Preserve these IDs
when replaying results so merging and retries do not duplicate transcript lines.

New `UploadAudioFinalizer` (BugVoiceMac) conforms to
`MeetingAudioFinalizerProtocol`. Reuse the block-based AAC writing and durable
replacement used by `MeetingAudioFinalizer`, reading only `.file` with
`makeReader(for:)`. Do not run its dual-track mix or attenuate the file audio.
All recording loops currently using `MeetingTrack.allCases`, including live and
final scheduling, must explicitly select `.mic` and `.system` when `.file` is
added. Define deterministic track ordering in the merger and exporter.

### 4.4 Meetings take priority

Starting a live meeting is allowed while an upload runs. Keep upload activity
separate from `MeetingController.isActive` so it cannot disable Start recording.
Before each upload chunk and its fallback transcription calls, wait while a live
meeting is recording, paused, or finishing transcription. A chunk already in
flight finishes; the upload then yields. Resume after the live meeting stops and
its final transcription drains. Dictation retains priority through the existing
shared transcription router.

A new upload submitted while a meeting records stays queued and displays
Waiting. If reading is already running when a meeting starts, it can finish its
bounded local decode; hold recognition at the chunk gate. A suspended upload
keeps its transcribing state and percentage, with supporting copy "Waiting for
meeting to finish". Keep the ring visible at that percentage. No competing job
passes it in the queue. Meeting pause alone does not resume uploads.

### 4.5 Library and lifecycle

After ready or retained transcript failure, call `AppModel.reloadMeetings()`.
Open in Meetings selects that meeting ID and navigates to `.meetings`.
`MeetingListProjection.groups` / `matches` continue searching title and transcript
without a source filter. Uploaded meetings group by their media `startedAt`.

Settings › Meetings **Delete ready meetings after** applies equally to uploads
through `MeetingRetention.pruneCandidates`, measured from `importedAt` for
uploads and `endedAt` for recordings; it excludes active, staging and
retryable transcribing entries. Pruning deletes the whole folder, including
uploaded audio. Storage includes upload audio and active journals under Meetings.
If retention or manual deletion removes a ready result, clear its stale queue
link on reload. Upload import, completion, recovery and retry never call
`AppModel.recordMeetingInsights(seconds:)` or add an Insights usage delta.

Leaving Upload or closing the main window does not cancel its controller's job.
Quit during reading stops the decoder/writer and leaves the discardable staging
folder for startup cleanup. Quit during transcription checkpoints completed work,
quiesces workers and keeps the manifest transcribing; it is not a user Cancel.

## 5. UI

Follow the linked mockup's spacing, hierarchy and cards in light and dark mode.
Add **Upload** immediately after **Meetings** in `Page` and `MainWindow`; retain
the sidebar name Meetings. The Upload sidebar item shows a progress ring while
a job runs, including when another page is selected.

- Page title **Upload**, heading **Upload a recording**. Under the heading:
  "Transcribed on this Mac with <speech model>" when Settings › Speech uses
  WhisperKit, or "Transcribed by <server host> with <model>" when it uses an
  OpenAI-compatible server the user configured. The link opens Settings › Speech.
  Uploads use `AppModel.transcriptionRouter`, the same transcriber as Meetings,
  so they follow the configured engine and never pick a server on their own.
  The label updates when settings change.
- Empty drop zone: "Drop an audio or video file, or click to browse" and
  "MP3, WAV, M4A, AIFF, CAF, MP4, MOV, M4V". Hint: "You can drop several files;
  they are transcribed one at a time. Uploads appear in Meetings when they are
  ready."
- File card: name and "Audio/Video · duration · size", **Transcribe** and
  **Cancel**. Hint: "Only the audio is kept, as a small audio.m4a in the meeting
  folder. The video stays where it is."
- Progress card: file name, percentage, **Cancel**, two phase indicators
  **1 Reading file** / **2 Transcribing locally**. Active heading is
  "Reading file…" then "Transcribing locally…" ("Transcribing…" when the
  speech engine is a configured server). Explain that leaving the page
  is safe, meetings take priority, and transcription continues on next launch.
- Queue: compact "Drop more files, or click to browse" zone, file count,
  **Clear finished**, metadata per row. Waiting rows say **Waiting**, active
  recognition says **Transcribing N%**, and ready rows offer **Open in Meetings**.
  The active job retains the phase card and Cancel; failed rows expose the error
  card, and cancelled rows say **Cancelled** until cleared.
- Ready card: **Ready**, title, duration and transcript line count;
  **Upload another** and **Open in Meetings**.
- Error card: exact error sentence (§7), original file name and
  **Choose another file**. For retained audio, also provide **Open in Meetings**
  to reach Retry transcript. The mockup's "Other messages" panel is illustrative
  documentation, not a second card shown in the product.

`MeetingListRow` and `MeetingDetails` show an **Uploaded** badge. Detail metadata
adds "from <original file name>". Reuse `MeetingPlayer`,
`MeetingPlayerModel.seek(to:)`, `MeetingTimeline.seekTime(for:)`, waveform,
play/pause, speed, transcript highlighting and click-to-seek. All upload rows
show Speaker; there are no You/Others lanes for the file mix.

Keep Transcript, Summary and Action items tabs, rename/delete, Show in Finder,
and Markdown/SRT/audio exports. `MeetingExporter.markdown` and `srt` obtain
Speaker from `MeetingSegment.speaker`. Audio export copies only `audio.m4a`.
Summary and Action items are generated only on request via
`AppModel.generateMeetingText(id:kind:progress:)` using the Meeting notes model,
including the existing context splitting, cancellation and retry behavior.

## 6. Components

### 6.1 VoiceCore (Foundation only, TDD)

| Unit | Responsibility |
|---|---|
| `MeetingSource`, `MeetingManifest` | Source metadata, legacy decoding, staging/transcribing distinction |
| `MeetingTrack`, `MeetingSegment.speaker` | `.file` and Speaker; preserve recorded labels |
| `UploadJob`, `UploadJobState`, `UploadQueue` | Pure transitions, FIFO admission, meeting gate, progress and terminal cleanup events |
| `MeetingSession` | `transcribeUpload(_:)`, `persistFinal(_:)`, source-aware recovery and retained-audio failure ordering |
| `MeetingChunkPlanner`, `MeetingChunkProcessor`, `MeetingTranscriptMerger` | Reuse ranges, language attempts and merge; deterministic file ordering |
| `MeetingRecoveryPolicy`, `MeetingRetention`, `MeetingListProjection`, `MeetingExporter` | Source-aware recovery routing; shared retention, search and exports |

Keep AVFoundation, AppKit, permissions and file selection outside VoiceCore.
Use injected clock, store, audio, scheduler and finalizer protocols; write failing
unit tests before implementation.

### 6.2 BugVoiceMac

| Unit | Responsibility |
|---|---|
| `MediaAudioDecoder` | AVAssetReader metadata/PCM, channel mix, bounded decode, progress and cancellation |
| `MeetingPCMJournalWriter` | Existing `.file` journal, checkpoints, range readers; decoder backpressure |
| `UploadAudioSourceControl` | No-op capture lifecycle; file checkpoint/recovery only |
| `UploadAudioFinalizer` | Stream file journal to durable mono AAC; cleanup only after safe persistence |

### 6.3 App

| Change | Where |
|---|---|
| New `UploadController`, owned for the app lifetime by `AppModel` | Own drafts, file access, `UploadQueue`, worker tasks, decoding, source-aware session construction, cancel and recovery |
| `UploadTranscriptionScheduler` | File-only final chunks, local transcriber, persisted results, live-meeting admission gate |
| New `UploadPage` | Mockup states, whole-page drop, NSOpenPanel, actions and progress |
| `.upload` page and ring | `Page`, `MainWindow` |
| Badge, original name, upload retry/cancel routing | `MeetingsPage`, `MeetingListRow`, `MeetingDetails`; reuse `MeetingPlayer` |
| Launch cleanup/recovery, library and Insights boundaries | `AppModel.recoverUnfinishedMeetings`, `reloadMeetings`, `recordMeetingInsights`; coordinate `MeetingController.start` / `stop` and recovery |

## 7. Errors and recovery

| Condition | Message and action |
|---|---|
| Readable asset, no audio track | "This file has no audio." Remove staging folder; continue queue |
| Unsupported format/codec, corrupt/empty file, invalid duration, DRM or failed file access | "BugVoice can't read this file. Use MP3, WAV, M4A, AIFF, CAF, MP4, MOV or M4V." Remove staging folder; continue queue |
| Disk full during reading, transcription checkpoint or finalization | "Not enough disk space to transcribe this file." Stop workers and remove the partial meeting folder; continue queue |
| Transcription throws or any chunk finishes failed | "Transcript could not be completed. The audio is saved; use Retry transcript in Meetings." Finalize and keep audio, retain retryable manifest and completed results; continue queue |
| Summary or Action items generation fails | Keep audio and transcript; use existing generation error and Retry |
| User cancels reading/transcription | Quiesce decoder, scheduler and finalizer, then delete that upload's entire folder; original untouched |

`MeetingSession.finishTranscription` currently leaves `.transcribing` on failure
without finalizing audio. Extend the upload branch: on a recognition failure,
finalize `audio.m4a` so the meeting plays and exports, persist the error and
completed chunks in a transcribing manifest, and keep the `.capture` journal.
`cleanupCapture()` runs only after the meeting is saved ready. The upload queue
is failed even though this durable manifest stays retryable. If saving audio
fails, report "Could not save the audio. Retry transcript in Meetings." Do not
claim saved playable audio until it exists; disk-full errors take the deletion
path above.

Retry transcript reads the kept journal, reuses valid chunk results and
processes missing/failed ones. The journal costs about 115 MB per hour of audio
until the upload is ready or deleted. Never decode `audio.m4a` back into a
journal: it is lossy and a second code path.

Extend `AppModel.recoverUnfinishedMeetings()` before its recording-state sweep:
discard `.upload` + `.interrupted` staging folders, then enqueue `.upload` +
`.transcribing` manifests for automatic continuation through
`MeetingSession.recover(id:)`. The current launch sweep only marks recordings
interrupted; automatic upload continuation is new work, not existing behavior.
Dispatch by source before constructing session dependencies. Upload recovery and
Retry transcript must never call `MeetingController.recover(id:)` with its
microphone/system sources. Recover the journal's committed bounds; the original file is not needed.
A transcribing upload whose journal is missing or unreadable is marked failed
with the retained-audio message replaced by "The transcript cannot be retried.
The audio is saved." and stays playable if `audio.m4a` exists.

Cancellation must prevent late progress/save callbacks from recreating a deleted
folder. Persist a hidden `.upload-cancelled` marker in the meeting folder before
draining workers; startup deletes folders with that marker before manifest
recovery. Mark queue cancellation terminal only after deletion finishes. If
deletion fails, retain the marker, show "Could not remove the cancelled upload."
and retry cleanup on launch. The same cleanup mechanism handles failed imports
whose folders could not be removed. Never remove the user's source file.

A crash after ready is saved but before `cleanupCapture()` only leaves redundant
journals; remove them after validating saved audio. Sleep suspends upload work
at a checkpoint/chunk boundary and wake resumes automatically; it does not
change the live recorder's existing manual-resume policy.

## 8. Testing

### 8.1 Unit tests

VoiceCore (failing test first, then implementation; `swift test` before commits):

- Manifest round trips for both sources; legacy manifests without new keys;
  schema stays 1; file track decoding; Speaker in transcript, Markdown and SRT;
  recorded You/Others unchanged.
- `UploadQueue`: ordered batch admission, one active job, invalid transitions,
  progress clamping, cancellation in every active state, stale callbacks,
  failure advances queue, Clear finished preserves meetings, live meeting gate
  and resume without reordering.
- `MeetingSession` with fake audio/scheduler/finalizer/store: upload never calls
  capture start; media dates/duration survive transcription, recover and retry;
  commit boundary precedes recognition; final chunks persist before progress;
  merged overlap has no duplicate lines; failed records trigger retained audio;
  empty/silent chunks can finish ready.
- Recovery cases: discard upload staging, continue transcribing via file-only
  dependencies, marker wins over recovery, missing journal marks failed;
  recorded recovery unchanged. Cancellation drains before deletion and late
  callbacks cannot save. Transcript failure keeps the journal; only ready cleans it.
- `MeetingChunkPlanner` and merger: partial last chunk, long media, deterministic
  track order, chunk reuse by ID/range, timestamps aligned with audio timeline.
- `MeetingListProjection.matches`: uploaded title and transcript, grouped media
  date. `MeetingRetention`: uploads expire from `importedAt` (a 2024 file
  imported today survives a 30-day policy), recordings from `endedAt`,
  active/staging exclusion. No upload completion/retry emits Insights usage.

BugVoiceMac/app tests use fixture assets and fake decoder/session boundaries:
bounded PCM production and writer backpressure, resampling/downmix, EOF flush,
read errors and cancellation, disk-full classification, `.file`-only AAC,
source-specific recovery construction and use of the shared transcription router.
Keep device-dependent checks in the manual checklist.

### 8.2 Manual checklist

Implementation will append these rows to
[manual checklist](../../testing/manual-checklist.md), starting at 103. This
spec does not modify that file. Results remain blank until run on device.

| # | Where | Do | Expect | Result |
|---|---|---|---|---|
| 103 | Sidebar / Upload | Open Upload and click the speech model link | Upload follows Meetings; empty drop copy matches mockup; Settings › Speech opens | |
| 104 | Upload | Browse, then drop several supported files over different parts of the page; cancel a draft | Multiple selection allowed; cards show name, Audio/Video, duration and size; draft Cancel creates no folder | |
| 105 | Upload | Transcribe MP3, WAV, M4A, AIFF, CAF, MP4, MOV and M4V fixtures | Reading file… then Transcribing locally…; each becomes ready with the configured speech engine | |
| 106 | Upload / sidebar | Queue three files, leave page and close/reopen main window | FIFO, one active job; Waiting / Transcribing N% / Open in Meetings; ring follows current phase; work continues | |
| 107 | Upload / Meetings | Open ready result and Clear finished | Uploaded badge in row and title; metadata says from original name; clearing queue keeps meeting | |
| 108 | Meeting detail | Play, scrub, change speed and click transcript lines | Correct audio and seek/highlight timing; every row says Speaker | |
| 109 | Meeting detail | Generate Summary and Action items with Meeting notes model; export Markdown, SRT and audio | No automatic generation; configured model used; Speaker in text exports; audio export is audio.m4a | |
| 110 | Finder / Storage | Inspect saved upload and original file | Only audio.m4a retained as audio; no mic/system files or completed capture journal; original bytes/location unchanged; Meetings storage includes upload | |
| 111 | Upload / Meetings | Start meeting during upload transcription; pause, resume and stop meeting; submit another upload while recording | Meeting starts; upload yields between chunks, stays held through pause/final pass, then resumes; new upload waits | |
| 112 | Upload / dictation | Dictate while upload transcribes | Dictation has priority; upload continues between requests; with WhisperKit, import makes no network request; no capture permission request | |
| 113 | Upload | Cancel during reading, transcription and while waiting | Workers stop; corresponding meeting folder removed; original untouched; next job advances | |
| 114 | Quit / relaunch | Quit once during reading and once during transcription | Reading staging discarded; transcription resumes from durable work without mic/system capture or source file | |
| 115 | Upload / Meetings | Induce recognition failure, then Retry transcript | Exact retained-audio error; audio plays/exports; retry uses same meeting and the kept journal; journal removed once ready | |
| 116 | Upload | Try unsupported/DRM file and simulate disk full | Exact unreadable/disk-full sentence; partial folders removed; next queued file runs | |
| 117 | Meetings / Settings / Insights | Search uploaded title and transcript, apply Delete ready meetings after, compare Insights | Search finds both; uploads expire counted from import time, not media date; active uploads kept; upload minutes/counts do not change Insights | |
| 118 | Upload | Import fixtures with metadata date, filesystem date only and neither usable date | Date fallback order correct; title drops extension; duration comes from asset | |
| 119 | Upload / Activity Monitor | Run the five review-focus inputs below; sleep/wake during a long job | Expected errors or ready result; bounded buffers; no dictation time cap; wake resumes upload | |

### 8.3 Review focus

| Input most likely to break | Expected behaviour |
|---|---|
| Zero-length file | Unreadable-file sentence; no empty ready meeting; remove staging and advance queue |
| Audio at 48 kHz stereo or 5.1 | AVFoundation downmixes/resamples to 16 kHz mono; audible content preserved without half-volume mixing; timestamps and player stay aligned |
| Video track only | "This file has no audio." No retained folder; original unchanged |
| File deleted or moved while reading | If the already-open reader completes, finish normally; if access/read fails, show unreadable-file sentence and remove partial folder; never create a truncated ready result |
| Very long file, three hours or more | Stream bounded PCM blocks and individual chunks; no duration cap or full-file buffer; progress/cancel/meeting preemption stay responsive; timestamps and exports cover full asset |

## 9. Open questions

None. The scope and behaviour above implement the maintainer's decisions.
