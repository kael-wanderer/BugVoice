# Incremental Transcription Bench (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `bugvoice-bench --latency` mode that measures where Whisper's fixed cost goes, tries one cheap lever, and simulates incremental transcription on local clips, then applies the spec's gate.

**Architecture:** Pure, tested logic goes in `VoiceCore`: the pause chunker (reused as-is by Phase 2), the virtual-clock simulation, and stats plus gate evaluation. The bench target supplies the real model and the report. App behavior is unchanged except for one new `TranscriptionOptions` field whose default keeps today's decoding.

**Tech Stack:** Swift 6 package, Swift Testing, WhisperKit 1.1.1 (via `WhisperEngine`), `bugvoice-bench` executable.

**Spec:** `docs/superpowers/specs/2026-10-24-incremental-transcription-design.md` (Phase 1 only. Phase 2 gets its own plan after the gate passes.)

## Global Constraints

- Swift package, tools 6.0, macOS 15.0 floor. `VoiceCore` imports Foundation only.
- Exactly one external dependency: WhisperKit pinned `exact: "1.1.1"`. No package manifest change.
- TDD for everything in `VoiceCore`: failing test first, then code. `swift test` must pass before every commit.
- No microphone, no app launch, no paste, nothing sent off the Mac. Bench reads local clips and the cached models only.
- The committed report carries numbers only. Transcripts go to stderr, and only with `--show-text`.
- Clips and their `.txt` references stay gitignored (`bench/clips/*.wav`, `*.txt`).
- Commit after each task; message style `feat(core): …`, `feat(bench): …`, `docs: …`, ending with the Co-Authored-By line.
- Codex: ignore the sub-skill header above and execute the tasks directly (AGENTS.md rule).

## Review Focus

1. Trailing silence after the last word (the owner pauses before releasing): the tail must be skipped, not transcribed into "Thank you.". Test in Task 2 (`silentTailIsSkipped`).
2. A clip shorter than the shortest part, or one with no pause at all: zero cuts, so incremental equals the baseline path. Tests in Task 1 (`noPauseNoCut`) and Task 2 (`noCutsMeansOnePass`).
3. A pass still running at release: the tail starts when that pass ends, not at release. Test in Task 2 (`tailWaitsForRunningPass`).
4. A corpus missing a length bucket (today's four 15 s clips): the gate must fail, not pass vacuously. Test in Task 3 (`missingBucketFails`).
5. A clip without a `.txt` reference: timed but left out of the WER checks, never counted as WER 0. Test in Task 3 (`missingReferenceIgnoredForWER`).

---

### Task 1: SpeechChunker

**Files:**
- Create: `Sources/VoiceCore/SpeechChunker.swift`
- Test: `Tests/VoiceCoreTests/SpeechChunkerTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct SpeechChunker: Sendable {
      public struct Parameters: Sendable, Equatable, Hashable {
          public var pause: TimeInterval        // seconds of silence that allow a cut
          public var shortestPart: TimeInterval // audio since last cut before a cut is allowed
          public var longestPart: TimeInterval  // forced cut after this much without a pause
          public var silenceFactor: Float = 0.25
          public var floorRMS: Float = 0.003
          public init(pause: TimeInterval, shortestPart: TimeInterval, longestPart: TimeInterval)
      }
      public struct Cut: Sendable, Equatable {
          public var sample: Int     // where the part ends (sample index)
          public var decidedAt: Int  // sample index at which the chunker could know it
      }
      public static let frameSamples = 320  // 20 ms at 16 kHz
      public init(parameters: Parameters)
      public mutating func append(_ samples: [Float]) -> [Cut]  // streaming, returns new cuts
      public static func cuts(in samples: [Float], parameters: Parameters) -> [Cut]
  }
  ```

Rules (from the spec):
- Frames are 320 samples; a trailing partial frame waits for more samples.
- A frame is voiced when its RMS ≥ `floorRMS`. A frame is silent when its RMS < `max(floorRMS, silenceFactor × median RMS of voiced frames so far)`.
- Normal cut: when a run of silent frames reaches `pause` seconds and the audio from the last cut to the start of that run is ≥ `shortestPart` and contains a voiced frame. `sample` = pause start + (pause frames / 2) frames, integer division; `decidedAt` = pause start + `pause`.
- Forced cut: when audio since the last cut reaches `longestPart` with a voiced frame in it, cut at the centre of the quietest 10-frame (200 ms) window in the last 3 s; `decidedAt` = the current sample.
- Silence-only audio never cuts.

- [ ] **Step 1: Write the failing tests**

Build the audio with a helper in the test file: `tone(seconds:amplitude:)` (a 220 Hz sine at 16 kHz) and `silence(seconds:)` (zeros). Tests:

```swift
let p = SpeechChunker.Parameters(pause: 0.5, shortestPart: 4, longestPart: 25)

@Test func cutsInsidePause() {
    let audio = tone(seconds: 5, amplitude: 0.1) + silence(seconds: 1) + tone(seconds: 3, amplitude: 0.1)
    let cuts = SpeechChunker.cuts(in: audio, parameters: p)
    #expect(cuts.count == 1)
    #expect((5 * 16_000 ... 6 * 16_000).contains(cuts[0].sample))
    #expect(cuts[0].decidedAt == 5 * 16_000 + 8_000)   // pause start + 0.5 s
    #expect(cuts[0].sample == 5 * 16_000 + 3_840)      // pause start + 12 frames
}
@Test func pauseBeforeShortestPartGivesNoCut() {
    let audio = tone(seconds: 2, amplitude: 0.1) + silence(seconds: 1) + tone(seconds: 2, amplitude: 0.1)
    #expect(SpeechChunker.cuts(in: audio, parameters: p).isEmpty)
}
@Test func shortPauseGivesNoCut() {
    let audio = tone(seconds: 5, amplitude: 0.1) + silence(seconds: 0.3) + tone(seconds: 3, amplitude: 0.1)
    #expect(SpeechChunker.cuts(in: audio, parameters: p).isEmpty)
}
@Test func noPauseNoCut() { #expect(SpeechChunker.cuts(in: tone(seconds: 20, amplitude: 0.1), parameters: p).isEmpty) }
@Test func silenceOnlyNeverCuts() { #expect(SpeechChunker.cuts(in: silence(seconds: 40), parameters: p).isEmpty) }
@Test func forcedCutAtQuietestWindow() {
    // 23.5 s loud, 0.2 s quiet (above floor, below 0.25 × median), 3 s loud: no real pause.
    let audio = tone(seconds: 23.5, amplitude: 0.2) + tone(seconds: 0.2, amplitude: 0.01) + tone(seconds: 3, amplitude: 0.2)
    let cuts = SpeechChunker.cuts(in: audio, parameters: p)
    #expect(cuts.count == 1)
    #expect(abs(cuts[0].sample - Int(23.6 * 16_000)) <= SpeechChunker.frameSamples * 2)
    #expect(cuts[0].decidedAt == 25 * 16_000)
}
@Test func relativeThresholdCuts() {
    // Room noise at 0.008 is above the 0.003 floor but below 0.25 × the speaker's level: still a pause.
    let audio = tone(seconds: 5, amplitude: 0.1) + tone(seconds: 1, amplitude: 0.008) + tone(seconds: 3, amplitude: 0.1)
    #expect(SpeechChunker.cuts(in: audio, parameters: p).count == 1)
}
@Test func streamingMatchesBatch() {
    let audio = tone(seconds: 5, amplitude: 0.1) + silence(seconds: 1) + tone(seconds: 6, amplitude: 0.1) + silence(seconds: 0.8) + tone(seconds: 2, amplitude: 0.1)
    var chunker = SpeechChunker(parameters: p)
    var streamed: [SpeechChunker.Cut] = []
    for start in stride(from: 0, to: audio.count, by: 1_234) {   // odd size: frames straddle appends
        streamed += chunker.append(Array(audio[start ..< min(start + 1_234, audio.count)]))
    }
    #expect(streamed == SpeechChunker.cuts(in: audio, parameters: p))
    #expect(streamed.count == 2)
}
```

Frame RMS of a sine is amplitude / √2. In `forcedCutAtQuietestWindow` the 0.01 stretch is silent (0.007 < 0.25 × 0.141) but lasts only 0.2 s, so only the forced rule can cut there.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SpeechChunkerTests`
Expected: FAIL to compile, "cannot find 'SpeechChunker' in scope".

- [ ] **Step 3: Implement `SpeechChunker` in `Sources/VoiceCore/SpeechChunker.swift`**

Keep running state (frame buffer, voiced RMS values for the median, current silent run start, last cut sample, per-frame RMS history for the last 3 s). `cuts(in:parameters:)` = one `append` of the whole array. The median can be recomputed per frame from a sorted insert. Clips are at most minutes long.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SpeechChunkerTests`
Expected: all 8 pass.

- [ ] **Step 5: Full suite and commit**

Run: `swift test` (expected: all pass).
```bash
git add Sources/VoiceCore/SpeechChunker.swift Tests/VoiceCoreTests/SpeechChunkerTests.swift
git commit -m "feat(core): speech chunker that cuts recordings at pauses"
```

---

### Task 2: IncrementalSimulation

**Files:**
- Create: `Sources/VoiceCore/IncrementalSimulation.swift`
- Test: `Tests/VoiceCoreTests/IncrementalSimulationTests.swift`

**Interfaces:**
- Consumes: `SpeechChunker.Cut` (Task 1), `DictationPipeline.stripPlaceholders`, `HallucinationFilter.strip` / `isHallucination`, `AudioClip`.
- Produces:
  ```swift
  public enum IncrementalSimulation {
      public struct Pass: Sendable, Equatable { public var start: Double; public var end: Double }
      public struct Outcome: Sendable, Equatable {
          public var text: String
          public var parts: Int                 // passes run, tail included
          public var releaseToTranscript: Double
          public var passes: [Pass]
      }
      /// `transcribe` gets the part's audio and the previous part's cleaned
      /// text ("" when `previousTextInPrompt` is false) and returns the raw
      /// text plus the seconds the pass took.
      public static func run(
          samples: [Float], cuts: [SpeechChunker.Cut], previousTextInPrompt: Bool,
          transcribe: (AudioClip, String) async throws -> (text: String, seconds: Double)
      ) async throws -> Outcome
      /// Same cleanup the pipeline applies to a transcript.
      public static func clean(_ raw: String) -> String
  }
  ```

Timeline (virtual seconds = samples / 16 000):
- Part i spans `[previous cut sample, cuts[i].sample)` and closes at `cuts[i].decidedAt / 16_000`.
- Pass start = `max(close, previous pass end)`; end = start + returned seconds.
- Release = `samples.count / 16_000`. Tail = `[last cut sample, samples.count)`, starts at `max(release, last pass end)`.
- A part or tail whose `AudioClip.rms` < 0.003 is not transcribed and not counted in `parts`.
- `releaseToTranscript` = end of the last pass minus release, floored at 0.
- `clean(raw)` = `HallucinationFilter.strip(DictationPipeline.stripPlaceholders(raw))`, then "" if `HallucinationFilter.isHallucination`. `text` = cleaned non-empty part texts joined with one space.

- [ ] **Step 1: Write the failing tests**

Use a fake `transcribe` that records each call's sample count and prompt and returns `("part\(n)", 1.0)`. Use `tone`/`silence` helpers (copy them from Task 1's test file into a shared `Tests/VoiceCoreTests/Support/TestAudio.swift`, and update Task 1's tests to use it).

```swift
@Test func noCutsMeansOnePass() async throws {
    let audio = tone(seconds: 3, amplitude: 0.1)
    let out = try await IncrementalSimulation.run(samples: audio, cuts: [], previousTextInPrompt: false) { _, _ in ("hello", 1.2) }
    #expect(out.parts == 1); #expect(out.releaseToTranscript == 1.2); #expect(out.text == "hello")
}
@Test func partsFinishedBeforeReleaseLeaveOnlyTail() async throws {
    // 20 s audio, cuts decided at 5 s and 12 s; each pass 1 s; release at 20 s.
    let audio = tone(seconds: 20, amplitude: 0.1)
    let cuts = [SpeechChunker.Cut(sample: 4 * 16_000, decidedAt: 5 * 16_000), .init(sample: 11 * 16_000, decidedAt: 12 * 16_000)]
    let out = try await IncrementalSimulation.run(samples: audio, cuts: cuts, previousTextInPrompt: false) { _, _ in ("w", 1.0) }
    #expect(out.passes == [.init(start: 5, end: 6), .init(start: 12, end: 13), .init(start: 20, end: 21)])
    #expect(out.releaseToTranscript == 1.0); #expect(out.parts == 3)
}
@Test func tailWaitsForRunningPass() async throws {
    // Cut decided at 9.5 s of a 10 s clip, pass takes 1 s: tail starts at 10.5.
    let audio = tone(seconds: 10, amplitude: 0.1)
    let cuts = [SpeechChunker.Cut(sample: 9 * 16_000, decidedAt: 9 * 16_000 + 8_000)]
    let out = try await IncrementalSimulation.run(samples: audio, cuts: cuts, previousTextInPrompt: false) { _, _ in ("w", 1.0) }
    #expect(out.passes.last == .init(start: 10.5, end: 11.5)); #expect(out.releaseToTranscript == 1.5)
}
@Test func silentTailIsSkipped() async throws {
    let audio = tone(seconds: 6, amplitude: 0.1) + silence(seconds: 2)
    let cuts = [SpeechChunker.Cut(sample: 6 * 16_000 + 4_000, decidedAt: 6 * 16_000 + 8_000)]
    let out = try await IncrementalSimulation.run(samples: audio, cuts: cuts, previousTextInPrompt: false) { _, _ in ("Thank you.", 1.0) }
    #expect(out.parts == 1); #expect(out.releaseToTranscript == 0)   // pass ended at 7.5 s, release at 8 s
}
@Test func textJoinedAndCleaned() async throws {
    // Second part returns only a hallucination: dropped from the text.
    let audio = tone(seconds: 12, amplitude: 0.1)
    let cuts = [SpeechChunker.Cut(sample: 5 * 16_000, decidedAt: 5 * 16_000), .init(sample: 9 * 16_000, decidedAt: 9 * 16_000)]
    var n = 0
    let out = try await IncrementalSimulation.run(samples: audio, cuts: cuts, previousTextInPrompt: false) { _, _ in
        n += 1; return ([" first [BLANK_AUDIO] part", "Thank you.", "last part"][n - 1], 0.5)
    }
    #expect(out.text == "first part last part")
}
@Test func previousTextOnlyWhenEnabled() async throws {
    // Assert the prompts seen by transcribe: ["", "a", "b"] when true, ["", "", ""] when false.
}
@Test func partAudioBoundaries() async throws {
    // Assert recorded sample counts equal [cut0, cut1 - cut0, total - cut1].
}
```

Write the last two bodies out in full, in the same style as the others.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter IncrementalSimulationTests`
Expected: FAIL to compile, "cannot find 'IncrementalSimulation' in scope".

- [ ] **Step 3: Implement `IncrementalSimulation` in `Sources/VoiceCore/IncrementalSimulation.swift`**

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "IncrementalSimulationTests|SpeechChunkerTests"`
Expected: all pass.

- [ ] **Step 5: Full suite and commit**

Run: `swift test`.
```bash
git add Sources/VoiceCore/IncrementalSimulation.swift Tests/VoiceCoreTests/IncrementalSimulationTests.swift Tests/VoiceCoreTests/Support/TestAudio.swift Tests/VoiceCoreTests/SpeechChunkerTests.swift
git commit -m "feat(core): virtual-clock simulation of incremental transcription"
```

---

### Task 3: Latency stats and gate

**Files:**
- Create: `Sources/VoiceCore/LatencyBench.swift`
- Test: `Tests/VoiceCoreTests/LatencyBenchTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum LatencyStats {
      public static func median(_ values: [Double]) -> Double          // 0 for empty; mean of middle two for even
      public static func linearFit(x: [Double], y: [Double]) -> (fixed: Double, perSecond: Double) // least squares
  }
  public struct ClipRun: Sendable, Equatable {
      public var name: String            // file name, e.g. "vi-3.wav"
      public var audioSeconds: Double
      public var baselineSeconds: Double
      public var incrementalSeconds: Double
      public var baselineWER: Double?    // nil without a reference
      public var incrementalWER: Double?
      public var group: String { get }   // "en", "vi", "mix" from the name prefix before "-", else "other"
  }
  public enum IncrementalGate {
      public enum Failure: Sendable, Equatable {
          case missingBucket(group: String, bucket: String)        // bucket: "under 8 s", "15 s+", "30 s+"
          case shortSlower(group: String, seconds: Double)         // median incremental − baseline, > 0.05
          case savingTooSmall(group: String, bucket: String, seconds: Double) // median saving below 0.5 (15 s+) or 1.0 (30 s+)
          case groupWER(group: String, delta: Double)              // mean incremental − baseline WER, > 0.02
          case clipWER(name: String, delta: Double)                // > 0.05
      }
      public static let groups = ["en", "vi", "mix"]
      public static func failures(_ runs: [ClipRun]) -> [Failure]
  }
  ```

Gate values come from the spec's *Goal*. Buckets use `audioSeconds`: under 8 s is `< 8`; 15 s+ is `>= 15`; 30 s+ is `>= 30`. Each of the three groups needs at least one clip in each bucket. WER checks use only clips with both WERs. Failures are ordered by group in `groups` order, then by kind in declaration order, then `clipWER` by name.

- [ ] **Step 1: Write the failing tests**

```swift
func run(_ name: String, _ audio: Double, base: Double, inc: Double, bw: Double? = 0.1, iw: Double? = 0.1) -> ClipRun { … }
func passingCorpus() -> [ClipRun] {   // one clip per group per bucket, all passing
    IncrementalGate.groups.flatMap { g in [
        run("\(g)-1.wav", 6, base: 1.2, inc: 1.2), run("\(g)-2.wav", 16, base: 1.8, inc: 1.2), run("\(g)-3.wav", 40, base: 3.0, inc: 1.3)] }
}
@Test func medianAndFit() {
    #expect(LatencyStats.median([3, 1, 2]) == 2); #expect(LatencyStats.median([4, 1, 2, 3]) == 2.5); #expect(LatencyStats.median([]) == 0)
    let fit = LatencyStats.linearFit(x: [1, 2, 4, 8], y: [1.12, 1.14, 1.18, 1.26])
    #expect(abs(fit.fixed - 1.10) < 1e-9); #expect(abs(fit.perSecond - 0.02) < 1e-9)
}
@Test func groupFromName() { #expect(run("mix-2.wav", 1, base: 1, inc: 1).group == "mix"); #expect(run("test.wav", 1, base: 1, inc: 1).group == "other") }
@Test func passingCorpusPasses() { #expect(IncrementalGate.failures(passingCorpus()).isEmpty) }
@Test func missingBucketFails() {
    let today = ["en-1.wav", "mix-1.wav", "mix-2.wav", "vi-1.wav"].map { run($0, 15, base: 1.5, inc: 1.0) }
    #expect(IncrementalGate.failures(today).contains(.missingBucket(group: "en", bucket: "30 s+")))
}
@Test func shortSlowerFails() {
    var c = passingCorpus(); c[0].incrementalSeconds = 1.3
    let f = IncrementalGate.failures(c)
    #expect(f.count == 1)
    guard case .shortSlower("en", let s) = f.first else { Issue.record("expected shortSlower"); return }
    #expect(abs(s - 0.1) < 1e-9)
}
@Test func savingThresholds() {
    var c = passingCorpus()
    c[1].incrementalSeconds = 1.4   // en-2, 16 s: saving 0.4
    c[2].incrementalSeconds = 2.6   // en-3, 40 s: saving 0.4
    let f = IncrementalGate.failures(c)
    #expect(f.contains { if case .savingTooSmall("en", "15 s+", _) = $0 { true } else { false } })  // median 0.4 < 0.5
    #expect(f.contains { if case .savingTooSmall("en", "30 s+", _) = $0 { true } else { false } })  // 0.4 < 1.0
    #expect(!f.contains { if case .savingTooSmall("vi", _, _) = $0 { true } else { false } })
}
@Test func werChecks() {
    var c = passingCorpus(); c[4].incrementalWER = 0.16      // vi-2: +0.06, vi mean +0.02 (not above the limit)
    var f = IncrementalGate.failures(c)
    #expect(f.contains { if case .clipWER("vi-2.wav", _) = $0 { true } else { false } })
    #expect(!f.contains { if case .groupWER = $0 { true } else { false } })
    c[4].incrementalWER = 0.19                                // vi mean +0.03
    f = IncrementalGate.failures(c)
    #expect(f.contains { if case .groupWER("vi", _) = $0 { true } else { false } })
}
@Test func missingReferenceIgnoredForWER() {
    var c = passingCorpus(); c[4].baselineWER = nil; c[4].incrementalWER = nil
    #expect(IncrementalGate.failures(c).isEmpty)
}
```

`run(…)` builds a `ClipRun` with the given fields. Compare WER deltas with a 1e-9 tolerance: a delta of exactly 0.02 must not fail.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LatencyBenchTests`
Expected: FAIL to compile.

- [ ] **Step 3: Implement `Sources/VoiceCore/LatencyBench.swift`**

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LatencyBenchTests`
Expected: all pass.

- [ ] **Step 5: Full suite and commit**

```bash
git add Sources/VoiceCore/LatencyBench.swift Tests/VoiceCoreTests/LatencyBenchTests.swift
git commit -m "feat(core): latency stats and incremental transcription gate"
```

---

### Task 4: VAD chunking option

**Files:**
- Modify: `Sources/VoiceCore/Transcription.swift:114-139` (`TranscriptionOptions`)
- Modify: `Sources/WhisperEngine/WhisperKitTranscriber.swift` (`decode.chunkingStrategy = .vad`)
- Test: `Tests/VoiceCoreTests/TranscriptionOptionsTests.swift` (create if missing, else add to the existing options tests)

**Interfaces:**
- Produces: `TranscriptionOptions.vadChunking: Bool`, init parameter `vadChunking: Bool = true` (last parameter). `WhisperKitTranscriber` sets `decode.chunkingStrategy = options.vadChunking ? .vad : ChunkingStrategy.none`, whichever WhisperKit 1.1.1 spells as "no chunking". If its type is optional, use `nil`.

- [ ] **Step 1: Failing test**

```swift
@Test func vadChunkingDefaultsOn() {
    #expect(TranscriptionOptions().vadChunking)
    #expect(TranscriptionOptions(vadChunking: false) != TranscriptionOptions())
}
```

- [ ] **Step 2: Run** `swift test --filter vadChunkingDefaultsOn`. Expected: FAIL to compile.
- [ ] **Step 3: Add the field and use it in `WhisperKitTranscriber`.** No app call site changes: every caller keeps the default.
- [ ] **Step 4: Run** `swift test` (expected: all pass) and `swift build` (expected: success).
- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceCore/Transcription.swift Sources/WhisperEngine/WhisperKitTranscriber.swift Tests/VoiceCoreTests/TranscriptionOptionsTests.swift
git commit -m "feat(core): transcription option to turn off VAD chunking"
```

---

### Task 5: `bugvoice-bench --latency`

**Files:**
- Create: `Sources/BugVoiceBench/LatencyBench.swift`
- Modify: `Sources/BugVoiceBench/main.swift`: usage comment, plus an early branch after the `--fidelity-history` block: `if CommandLine.arguments.contains("--latency") { try await runLatencyBench(...); exit(0) }`

**Interfaces:**
- Consumes: Tasks 1–4; `WhisperKitTranscriber`, `AudioFileLoader.load`, `WordErrorRate.compute`, `Vocabulary`, `LivePreviewModel.name`, `AppPaths.standard().models`.
- Produces: `func runLatencyBench(clipsDir: URL, modelName: String, showText: Bool) async throws`, writing markdown to stdout and progress to stderr (`log`).

Behavior:
- **Clips:** same discovery as clip mode. Language from the name prefix: `en` → `.en`; `vi` → `.vi`; `mix` → `.vi` with prompt `Vocabulary().whisperPrompt(example: Vocabulary.mixedExample)` (as the pipeline does with Keep English words on); other prefixes are skipped with a stderr note. Reference = `name.txt` if present. Warm up once before timing.
- **Timing:** `ContinuousClock` around `engine.transcribe`. Each timed number is the median of 3 runs unless stated otherwise.
- **Section 1, fixed cost:** for every clip, slices of the first 1, 2, 4, 8, 15, 25 s that fit, plus the whole clip. Table: slice length, median seconds across clips, and a fit line `LatencyStats.linearFit` over all (slice seconds, median) points: "fixed X s + Y s per audio second".
- **Section 2, cheap levers:** full clips with `vadChunking` true and false. Per group: median seconds and mean WER for each. Below the table add the line "Other options tried: none". The executor replaces it with any `DecodingOptions` actually tried and their result, if any.
- **Section 3, sweep:** every combination of pause {0.3, 0.5, 0.8} × shortest {2, 4, 6} × longest {15, 25} × previous text {off, on}. For each clip: `SpeechChunker.cuts`, then `IncrementalSimulation.run`. The transcribe closure runs the real engine once (not 3 times), cached by (clip, start sample, end sample, prompt text) so combinations with the same cuts reuse the pass and its measured seconds. The baseline per clip = Section 2's `vadChunking: true` median. Build `ClipRun`s. Table: one row per combination with the gate failure count and the median saving on 15 s+ clips. Best combination = fewest failures, ties broken by the larger median saving on 15 s+.
- **Section 4, best combination:** per-clip table (clip, audio s, parts, baseline s, incremental s, saving, baseline WER, incremental WER), a per-group-and-bucket table, and the gate failures listed in plain words (or "Gate: pass").
- **Section 5, with preview load:** rerun the best combination with no cache, while a background task loops on a second `WhisperKitTranscriber(modelName: LivePreviewModel.name, …)`. The loop transcribes the last 15 s of the current clip every 0.6 s after each pass returns. Re-time the baseline the same way. Same tables and gate as Section 4.
- **Section 6, automatic language (informational, my call):** the best combination with `language: .auto` for all clips. Tables only; the gate is not applied. If it would fail, the report says so, and Phase 2 then falls back to the full clip when the language is automatic.
- `--show-text` prints each clip's baseline text and incremental text to stderr. Stdout never carries transcript text.
- The header lists the model name, date, clip count per group, and how long the run took.

- [ ] **Step 1: Write `LatencyBench.swift` and the `main.swift` branch.**
- [ ] **Step 2: Build** with `swift build -c release --product bugvoice-bench`. Expected: success.
- [ ] **Step 3: Smoke run on the four existing clips**

Run: `Scripts/stt-bench.sh --latency > /tmp/latency-smoke.md` (the script already passes `--clips bench/clips`).
Expected: exit 0; all six sections present; Section 4 lists `missingBucket` failures, since today's clips are all 15 s; searching the output file for a distinctive word from `bench/clips/en-1.txt` finds nothing.

- [ ] **Step 4: Full suite** with `swift test`. Expected: all pass.
- [ ] **Step 5: Commit**

```bash
git add Sources/BugVoiceBench/LatencyBench.swift Sources/BugVoiceBench/main.swift
git commit -m "feat(bench): latency mode with fixed-cost, lever and incremental sweeps"
```

---

### Task 6: Corpus instructions and log

**Files:**
- Modify: `bench/clips/README.md`
- Create: `docs/progress/incremental-log.md`
- Modify: `AGENTS.md` (key documents: plan and log lines next to the spec line)

- [ ] **Step 1: README.** Add the 18-clip table from the spec (en/vi/mix × 6 s, 15 s, 40 s × 2; names `en-2` … continue numbering after existing files), the note that long clips include at least one coding-agent prompt with paths and identifiers, the ffmpeg line with `-t 40`, and the run command:
  `Scripts/stt-bench.sh --latency > docs/bench/$(date +%F)-incremental-bench.md`.
- [ ] **Step 2: Log.** Sections: *Built* (what each task added, test counts from `swift test`), *Smoke run* (the date, and that the gate failed only on missing buckets with four clips; paste the Section 1 fit line and Section 2 table, numbers only), *Owner run* (empty, with the command), *Gate result* (empty), *Decision* (empty: Phase 2 plan, or drop with numbers in `docs/ROADMAP.md`).
- [ ] **Step 3: AGENTS.md** line (the plan line is already there):
  `- Incremental transcription execution log and bench results: docs/progress/incremental-log.md`
- [ ] **Step 4: Commit**

```bash
git add bench/clips/README.md docs/progress/incremental-log.md AGENTS.md
git commit -m "docs: incremental bench corpus, log and key docs"
```

After Task 6 the owner records the clips and runs the bench. The owner and Claude read the report against the gate before any Phase 2 plan.
