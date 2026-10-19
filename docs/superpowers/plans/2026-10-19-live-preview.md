# Live Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. If neither skill is installed, execute the plan directly, task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the words Whisper hears in a card under the HUD while the hotkey is held (dictation and command mode), kept dimmed through Transcribing / Cleaning / Rewriting, without slowing the paste.

**Architecture:** VoiceCore gets a third, lowest transcription priority (`.preview`) in the shared `PriorityTranscriber`, which can now cancel a running preview pass, plus pure helpers for when to run a pass (`LivePreviewCadence`), whether preview is on (`LivePreviewPolicy`) and what the card shows (`LivePreviewText`), all test-first. `WhisperKitTranscriber` stops decoding when its task is cancelled. The app adds `AudioRecorder.recentSamples(seconds:)`, a `LivePreviewController` per recording, `HUDModel.preview`, the card in `HUDView`, and the setting.

**Tech Stack:** Swift 6 package, macOS 15, SwiftUI/AppKit, WhisperKit 1.1.1, Swift Testing. No new dependency.

**Spec:** `docs/superpowers/specs/2026-10-19-live-preview-design.md` (mockup `docs/design/proposal-live-preview.html`).

## Global Constraints

- `VoiceCore` imports Foundation only. TDD for VoiceCore. `swift test` passes before every commit.
- No new dependency. WhisperKit stays `exact: "1.1.1"`.
- The pasted text comes from the existing final transcription of the whole recording; preview results are never used for it.
- Preview text is never written to history, logs, diagnostics or Insights.
- Preview is off when: setting off, engine is not `.whisperKit`, focused field secure at key down, a meeting is recording, speech model not `.ready`.
- Priority order: dictation, then meeting, then preview. At most one queued preview request.
- Cadence: first pass at 1.0 s recorded, next pass 0.6 s after the previous returned, window = last 15 s, one pass at a time, a pass returning after release is discarded.
- Card: at most 2 lines, last 140 characters cut at a word boundary with "…", width up to 460 pt × HUD size factor, 0.15 s crossfade, secondary color after release.
- Setting `speech.livePreview`, default `true`. Footnote text exactly: "Shows the words under the HUD while you speak. The pasted text still comes from the whole recording after you release. Off with the OpenAI-compatible engine."
- UI copy: plain English, no hedging, no emoji.
- Commit after each task; the pre-commit hook raises the build, never edit CFBundleVersion.

## Review Focus

1. Release while a preview pass is running: the final dictation request must not wait for the full pass; the running preview is cancelled the moment a dictation request is enqueued (Task 1 test `dictationCancelsRunningPreview`).
2. A meeting chunk queued while previews keep arriving: the meeting chunk runs before any preview, previews never starve meeting work (Task 1 test `meetingBeforePreview`).
3. Whisper returns only "Thank you." or "[BLANK_AUDIO]" for silence: card shows nothing, not the hallucination (Task 2 test `hallucinationShowsNothing`).
4. A preview pass that returns after the key is released, or after the next recording started, never shows on the new HUD (Task 4: generation counter, device check P3).
5. Vietnamese text with diacritics cut at 140 characters: cut lands on a word boundary and never splits a grapheme (Task 2 test `cutsAtWordBoundaryVietnamese`).

---

### Task 1: Preview priority in the transcription queue (VoiceCore)

**Files:**
- Modify: `Sources/VoiceCore/Transcription.swift` (`TranscriptionPriority`), `Sources/VoiceCore/TranscriptionScheduler.swift` (`TranscriptionPriorityQueue`, `PriorityTranscriber`)
- Test: `Tests/VoiceCoreTests/` — the existing test file for `TranscriptionPriorityQueue` / `PriorityTranscriber` (find it with `rg -l PriorityTranscriber Tests`), or `TranscriptionPreviewPriorityTests.swift` if none

**Interfaces:**
- Produces:
  - `TranscriptionPriority.preview = 2` (keep `meeting = 0`, `dictation = 1`; raw values are persisted in nothing, but do not renumber).
  - `TranscriptionPriorityQueue.enqueue(_:) -> [String]` returns ids it dropped: enqueuing a `.preview` drops any queued preview; enqueuing a `.dictation` drops all queued previews. Existing callers ignore the result (`@discardableResult`).
  - `dequeue()` order: first `.dictation`, else first `.meeting`, else first `.preview`.
  - `PriorityTranscriber` resumes dropped requests with `CancellationError`, runs each `base.transcribe` inside a stored child `Task`, cancels the running task when (a) it is a `.preview` and a `.dictation` request is enqueued, or (b) its caller is cancelled (the existing `onCancel` path now also covers the running request, for every priority).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func dequeueOrderDictationMeetingPreview()   // enqueue preview p, meeting m, dictation d → dequeue d, m, p
@Test func secondPreviewReplacesQueued()           // enqueue p1 then p2 → returns ["p1"]; queue holds only p2
@Test func dictationDropsQueuedPreviews()          // enqueue p, then d → returns ["p"]; dequeue d, then nil
@Test func meetingBeforePreview()                  // p queued first, then m → m dequeued first
@Test func droppedPreviewThrowsCancellation() async  // fake base blocks on first call (meeting); preview p1, p2 enqueued → p1 throws CancellationError
@Test func dictationCancelsRunningPreview() async  // fake base: preview call sleeps 5 s honoring cancellation; start preview, then dictation → preview throws CancellationError within 0.2 s and dictation result returns
@Test func cancellingCallerStopsRunningRequest() async // start a preview, cancel its Task → base saw cancellation, caller gets CancellationError
@Test func runningMeetingNotCancelledByDictation() async // a running meeting request completes normally when dictation arrives
```

- [ ] **Step 2: Run, expect failures**

Run: `swift test --filter PriorityTranscriber` (and the queue suite)
Expected: FAIL, `.preview` not defined.

- [ ] **Step 3: Implement** as in Interfaces. Keep `waitUntilIdle()` semantics. The child task inherits no actor context it should not; resume each continuation exactly once (a cancelled running task still resumes its continuation with the thrown error).

- [ ] **Step 4: Run, expect pass**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceCore Tests/VoiceCoreTests
git commit -m "feat(core): preview transcription priority that yields to dictation"
```

### Task 2: Preview helpers and setting (VoiceCore)

**Files:**
- Create: `Sources/VoiceCore/LivePreview.swift`
- Modify: `Sources/VoiceCore/Settings.swift` (`SpeechSettings.livePreview`)
- Test: `Tests/VoiceCoreTests/LivePreviewTests.swift`, settings decode test in the existing settings test file

**Interfaces:**
- Consumes: `HallucinationFilter.strip(_:)`, `HallucinationFilter.isHallucination(_:)`, `DictationPipeline.stripPlaceholders(_:)`, `SpeechEngine`, `AppSettings`.
- Produces:

```swift
public enum LivePreviewPolicy {
    public static func isEnabled(settings: AppSettings, secureField: Bool, meetingRecording: Bool, speechReady: Bool) -> Bool
}
public enum LivePreviewCadence {
    public static let firstPassAfter: TimeInterval = 1.0
    public static let gapAfterPass: TimeInterval = 0.6
    public static let window: TimeInterval = 15
    public static func shouldStart(recorded: TimeInterval, running: Bool, lastReturnedAt: Date?, now: Date) -> Bool
}
public enum LivePreviewText {
    public static let maxCharacters = 140
    public static func display(_ transcript: String) -> String?   // nil = show nothing
}
// SpeechSettings
public var livePreview = true
```

- [ ] **Step 1: Write the failing tests**

```swift
@Test func policy() // enabled only when livePreview && engine == .whisperKit && !secureField && !meetingRecording && speechReady; each condition flipped alone → false
@Test func cadence() {
    #expect(!LivePreviewCadence.shouldStart(recorded: 0.9, running: false, lastReturnedAt: nil, now: t))
    #expect(LivePreviewCadence.shouldStart(recorded: 1.0, running: false, lastReturnedAt: nil, now: t))
    #expect(!LivePreviewCadence.shouldStart(recorded: 3, running: true, lastReturnedAt: nil, now: t))
    #expect(!LivePreviewCadence.shouldStart(recorded: 3, running: false, lastReturnedAt: t, now: t + 0.5))
    #expect(LivePreviewCadence.shouldStart(recorded: 3, running: false, lastReturnedAt: t, now: t + 0.6))
}
@Test func displayCollapsesAndStrips()   // "  Hey [BLANK_AUDIO]  Linh\n" → "Hey Linh"
@Test func hallucinationShowsNothing()   // "Thank you." → nil; "" → nil; "[Music]" → nil
@Test func shortTextUnchanged()          // 60 chars → same text, no "…"
@Test func longTextKeepsEnd()            // 300-char English text → hasPrefix("…"), count <= 141, hasSuffix(last word of input), first char after "…" starts a word
@Test func cutsAtWordBoundaryVietnamese() // 200 chars of "sáng nay mình họp với team mobile …" → same rules, all words from the input intact
@Test func singleHugeWord()              // one 300-char token → "…" + its last 140 characters
@Test func livePreviewDecodesDefaultOn() // settings JSON without the key → true; with false → false; encode round-trip
```

- [ ] **Step 2: Run, expect failures**

Run: `swift test --filter LivePreviewTests`
Expected: FAIL, types not defined.

- [ ] **Step 3: Implement** `Sources/VoiceCore/LivePreview.swift` and the setting (decode with `c.value(.livePreview, default: livePreview)` like `useVocabularyHints`). `display`: `stripPlaceholders`, then `HallucinationFilter.strip`, collapse whitespace; nil when empty or `isHallucination`; when longer than `maxCharacters`, take the suffix of `maxCharacters` characters, drop up to the first whitespace (unless that leaves nothing), prefix "…".

- [ ] **Step 4: Run, expect pass**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceCore/LivePreview.swift Sources/VoiceCore/Settings.swift Tests/VoiceCoreTests
git commit -m "feat(core): live preview cadence, policy, text and setting"
```

### Task 3: Stoppable WhisperKit pass and recent audio

**Files:**
- Modify: `Sources/WhisperEngine/WhisperKitTranscriber.swift`, `Sources/BugVoiceMac/AudioRecorder.swift`
- Test: `Tests/BugVoiceMacTests/` existing recorder tests if any; otherwise none (AVAudioEngine not testable headless)

**Interfaces:**
- Produces:
  - `WhisperKitTranscriber.transcribe` passes `callback: { _ in Task.isCancelled ? false : nil }` to `kit.transcribe(audioArray:decodeOptions:callback:)` and calls `try Task.checkCancellation()` after it returns, so a cancelled pass throws `CancellationError` instead of returning partial text. If the callback does not see the caller's cancellation (it runs on WhisperKit's own task), capture a `Mutex<Bool>`/`ManagedAtomic`-free flag set from `withTaskCancellationHandler` instead.
  - `AudioRecorder.recordedDuration: TimeInterval` (sample count / `AudioClip.sampleRate`) and `AudioRecorder.recentSamples(seconds: TimeInterval) -> AudioClip` (copy of the last N seconds under the existing `samples` mutex; all of it when shorter).

- [ ] **Step 1: Implement both.**

- [ ] **Step 2: Verify cancellation**

Write a throwaway check (not committed) or a test behind the existing WhisperEngine test target if one loads a model: start a transcription of a 20 s clip, cancel after 100 ms, measure time to `CancellationError`. Expected: under 0.3 s. Record the measured number in `docs/progress/live-preview-log.md` (created in Task 5). If WhisperKit cannot stop mid-pass, say so in the log; the spec accepts waiting one pass.

- [ ] **Step 3: Build and test**

Run: `swift build && swift test`
Expected: success.

- [ ] **Step 4: Commit**

```bash
git add Sources/WhisperEngine/WhisperKitTranscriber.swift Sources/BugVoiceMac/AudioRecorder.swift
git commit -m "feat(app): stoppable whisper pass and recent recorder audio"
```

### Task 4: LivePreviewController and the HUD card

**Files:**
- Create: `Sources/BugVoice/HUD/LivePreviewController.swift`
- Modify: `Sources/BugVoice/HUD/HUDView.swift` (`HUDModel.preview`, the card), `Sources/BugVoice/HUD/HUDController.swift`, `Sources/BugVoice/DictationController.swift` (`begin`, `cancel`, `finish`, `cycleLanguage`), `Sources/BugVoice/CommandController.swift` (`begin`, `cancel`, `finish`, `cycleLanguage`)

**Interfaces:**
- Consumes: Task 1–3 types; `model.transcriptionRouter`, `model.vocabulary`, `model.settings`, `model.speechState`, `model.meetings?.isRecording`.
- Produces:

```swift
@MainActor final class LivePreviewController {
    init(recorder: AudioRecorder, transcriber: any Transcriber, hud: HUDController)
    /// Starts passes for one recording when the policy allows; no-op otherwise.
    func start(enabled: Bool, language: @escaping @MainActor () -> SpeechLanguage, prompt: String)
    /// Stops passes and discards any result still in flight. Keeps the card text.
    func stop()
}
// HUDModel
var preview: String?
// HUDController
func setPreview(_ text: String?)
```

- [ ] **Step 1: Controller.** `start` bumps a generation counter and runs a `Task` loop: every 0.1 s, if `LivePreviewCadence.shouldStart(recorded: recorder.recordedDuration, running:, lastReturnedAt:, now:)`, take `recorder.recentSamples(seconds: LivePreviewCadence.window)`, skip when `clip.rms < 0.003`, transcribe with `TranscriptionOptions(language: language(), prompt: prompt, priority: .preview)`, and on success with the same generation and the recorder still running, `hud.setPreview(LivePreviewText.display(transcript.text))` only when non-nil. Errors (including `CancellationError`) are ignored. `stop` bumps the generation and cancels the task (which cancels the in-flight request through Task 1's `onCancel`).

- [ ] **Step 2: Wire dictation.** In `DictationController.begin` after `showListening`, call `preview.start(enabled: LivePreviewPolicy.isEnabled(settings: model.settings, secureField: startFocus.isSecure, meetingRecording: model.meetings?.isRecording == true, speechReady: model.speechState == .ready), language: { [weak self] in self?.languageCycler?.current ?? .auto }, prompt: model.settings.speech.useVocabularyHints ? model.vocabulary.whisperPrompt() : "")`. Call `preview.stop()` first thing in `finish()` and `cancel()` (before `recorder.stop()`). The language closure makes a language key change apply from the next pass. Same wiring in `CommandController` with its own recorder and cycler.

- [ ] **Step 3: HUD.** `HUDController.show(_:)`: when the new state is `.done`, `.warning`, `.failure`, `.message` or `.nothingHeard`, set `model.preview = nil`; `.listening` and `.commandListening` from a new recording also clear it (a new recording starts empty: clear in `start` via `setPreview(nil)`). `hide()` clears it. `HUDView`: wrap the pill in a `VStack(spacing: 6 × factor)`; below it, when `model.preview != nil`, the card: same background/stroke/shadow as the pill, `RoundedRectangle(cornerRadius: 12 × factor)`, `lineLimit(2)`, `frame(maxWidth: 460 × factor)`, `fixedSize(horizontal: false, vertical: true)`, `foregroundStyle` `.bvText` while the state is `.listening` / `.commandListening`, `.bvSecondary` otherwise, `.animation(.easeInOut(duration: 0.15), value: model.preview)` with `.contentTransition(.opacity)`. The HUD panel must resize to fit (check how `HUDController` sizes the panel and grow it for the card; the pill stays where it is today).

- [ ] **Step 4: Build and test**

Run: `swift build && swift test`
Expected: success.

- [ ] **Step 5: Commit**

```bash
git add Sources/BugVoice/HUD Sources/BugVoice/DictationController.swift Sources/BugVoice/CommandController.swift
git commit -m "feat(app): live preview card under the HUD"
```

### Task 5: Setting, docs

**Files:**
- Modify: `Sources/BugVoice/UI/Settings/SpeechTab.swift`, `AGENTS.md`, `docs/progress/HANDOFF.md`, `docs/propose-new-features.md`
- Create: `docs/progress/live-preview-log.md`

- [ ] **Step 1: Setting.** In `SpeechTab`, right after the "Use Dictionary words as hints" toggle: `SettingsToggle(title: "Live preview", isOn: $model.settings.speech.livePreview)` with the footnote from Global Constraints, styled like other footnotes in that tab.

- [ ] **Step 2: Build the app**

Run: `Scripts/build-app.sh`
Expected: "Built …/build/BugVoice.app".

- [ ] **Step 3: Docs.** `docs/progress/live-preview-log.md`: what was built, the Task 3 cancellation measurement, and device checks:
  - P1 Release to text: 10 dictations of about 5 s with Live preview on and 10 with it off (Settings › Speech); median release-to-text from History differs by at most 0.3 s.
  - P2 Hold in Slack or Notes and speak: card appears after about a second and updates about once a second; after release it stays dimmed under Transcribing and Cleaning, hides with Done.
  - P3 Two quick dictations in a row: the second HUD never shows words from the first.
  - P4 Speak 30 s: the card stays at two lines, start cut with "…", newest words visible.
  - P5 Vietnamese and mixed speech: diacritics correct in the card; language key tap changes the next update.
  - P6 Command mode with a selection: the instruction shows under the Command pill and stays dimmed under Rewriting.
  - P7 Password field: no card. Meeting recording: no card. Engine set to OpenAI-compatible: no card. Setting off: no card.
  - P8 Silence for 3 s: no card, no "Thank you.".
  - P9 History, Insights and logs contain no preview text (only the final dictation).
  - P10 HUD size Large: card scales with the pill.
  An AGENTS.md line for the log, a HANDOFF.md entry, item 3 in `docs/propose-new-features.md` marked built.

- [ ] **Step 4: Commit**

```bash
git add Sources/BugVoice/UI/Settings/SpeechTab.swift AGENTS.md docs
git commit -m "feat(app): live preview setting and docs"
```
