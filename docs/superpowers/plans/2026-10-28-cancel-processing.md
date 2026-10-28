# Cancel while processing — plan for Codex Luna (2026-10-28)

Spec: `docs/superpowers/specs/2026-10-28-cancel-processing-design.md`.
Mockup: `docs/design/proposal-cancel-processing.html`.

Every decision is made below, and all code here was compiled and tested in a
draft worktree (full suite: 1,354 VoiceCore, 30 MCPKit, 114 BugVoiceMac). Do not
redesign, rename or touch other files. If a "find" block below does not match
the file exactly once, stop and report instead of improvising.

## Ground rules

- Read `AGENTS.md` first. Swift Testing (`@Test`, `#expect`), not XCTest.
- `git switch -c feat/cancel-processing` from `main`.
- One commit per task, message given per task. End every commit message with a
  blank line and `Co-Authored-By: Codex <noreply@openai.com>`.
- The pre-commit hook bumps the build number in `App/Info.plist`; let it.
- Do not launch the app, do not send synthetic input, do not push or merge.

## Task 1 — the pipeline honors cancellation before cleanup and before insert

### 1a. Tests

In `Tests/VoiceCoreTests/DictationPipelineTests.swift`, find this line (it occurs once):

```swift
    @Test func anyErrorAfterTaskCancellationIsQuietCancellation() async {
```

and insert these three tests directly above it (keep a blank line between tests):

```swift
    @Test func cancelDuringCleanupPastesNothing() async throws {
        let model = RecordingModel(delay: 5)
        let insertion = RecordingInsertion()
        let pipeline = pipeline(model: model, insertion: insertion)
        let task = Task {
            await pipeline.run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        }
        while await model.requests.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        task.cancel()
        let r = await task.value
        #expect(r.outcome == .cancelled)
        #expect(await model.wasCancelled)
        #expect(await insertion.inserted.isEmpty)
        #expect(await insertion.copied.isEmpty)
        #expect(r.historyEntry == nil)
    }

    @Test func cancelBeforeCleanupSkipsTheModel() async {
        let model = RecordingModel()
        let insertion = RecordingInsertion()
        let pipeline = pipeline(model: model, insertion: insertion)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await pipeline.run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        }
        let r = await task.value
        #expect(r.outcome == .cancelled)
        #expect(await model.requests.isEmpty)
        #expect(await insertion.inserted.isEmpty)
        #expect(await insertion.copied.isEmpty)
    }

    @Test func cancelledNotesRunAddsNothing() async {
        let insertion = RecordingInsertion()
        let pipeline = pipeline(model: nil, insertion: insertion)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await pipeline.run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), mode: .notes, onStage: { _ in })
        }
        let r = await task.value
        #expect(r.outcome == .cancelled)
        #expect(await insertion.inserted.isEmpty)
    }

```

Run `swift test --filter "DictationPipelineTests/cancel"`. The three new tests
must FAIL (outcome is not `.cancelled`, text was inserted). If any passes, stop
and report.

### 1b. Code

In `Sources/VoiceCore/DictationPipeline.swift`:

Find:

```swift
        guard !raw.isEmpty, !HallucinationFilter.isHallucination(raw) else {
            result.outcome = .nothingHeard
            return result
        }
```

Replace with:

```swift
        guard !raw.isEmpty, !HallucinationFilter.isHallucination(raw) else {
            result.outcome = .nothingHeard
            return result
        }
        // Cancelled while the engine finished anyway: skip cleanup.
        if Task.isCancelled {
            result.outcome = .cancelled
            return result
        }
```

Find:

```swift
        text = result.finalText

        // Insert
```

Replace with:

```swift
        text = result.finalText

        // Cancelled during cleanup: the model's error became raw text above,
        // but nothing is pasted, copied or kept.
        if Task.isCancelled {
            result.outcome = .cancelled
            return result
        }

        // Insert
```

Run `swift test` (whole suite must pass).

Commit: `feat(core): a cancelled dictation pastes nothing, even during cleanup`

## Task 2 — Esc cancels a dictation while Transcribing or Cleaning

No test (app target). Make exactly these edits.

### 2a. `Sources/BugVoice/HUD/HUDView.swift`

Find:

```swift
            Text("Transcribing").fontWeight(.semibold)
            Text(language).foregroundStyle(.bvSecondary)
```

Replace with:

```swift
            Text("Transcribing").fontWeight(.semibold)
            Text("\(language) · Esc to cancel").foregroundStyle(.bvSecondary)
```

Find:

```swift
            Text(modelName.map { "Cleaning (\($0))" } ?? "Cleaning").fontWeight(.semibold)
            if let app { Text(app).foregroundStyle(.bvSecondary) }
```

Replace with:

```swift
            Text(modelName.map { "Cleaning (\($0))" } ?? "Cleaning").fontWeight(.semibold)
            Text(app.map { "\($0) · Esc to cancel" } ?? "Esc to cancel").foregroundStyle(.bvSecondary)
```

### 2b. `Sources/BugVoice/DictationController.swift` — nine edits

Edit 1. Find:

```swift
    private var stagedRun: Int?
```

Replace with:

```swift
    private var stagedRun: Int?
    /// The pipeline task of the current run; Esc cancels it while its
    /// stages show.
    private var processingTask: Task<Void, Never>?
    /// What the Cancelled message says about the current run.
    private var cancelDetail = "nothing was pasted"
    /// The run cancelled with Esc; its result changes the HUD no further.
    private var cancelledRun: Int?
```

Edit 2. Find:

```swift
    private func keyDownObserved(keyCode: Int64, flags: UInt64, userData: Int64) {
```

Replace with:

```swift
    private func keyDownObserved(keyCode: Int64, flags: UInt64, userData: Int64) {
        if keyCode == 53, userData != FixLast.syntheticEventMarker, let run = stagedRun {
            cancelProcessing(run: run)
            return
        }
```

Edit 3 (in `process(...)`). Find:

```swift
        let language = LanguageResolver(settings: model.settings.speech).language(for: focus, keyChoice: languageChoice).displayName
        let modelName = model.plan(for: feature).shortName
        Task { [self] in
```

Replace with:

```swift
        let language = LanguageResolver(settings: model.settings.speech).language(for: focus, keyChoice: languageChoice).displayName
        let modelName = model.plan(for: feature).shortName
        // last.wav holds this clip unless it went to a note, came from a
        // secure field or is a kept recording being retried.
        cancelDetail = intoNotes ? "nothing was added"
            : focus.isSecure || copyOnly ? "nothing was pasted"
            : "nothing was pasted · Retry last runs it again"
        processingTask = Task { [self] in
```

Edit 4 (in `process(...)`). Find:

```swift
            if result.outcome == .cancelled {
                hud.hide()
            } else {
                if copyOnly, [.copiedNotConsumed, .copiedFocusChanged].contains(result.outcome) {
```

Replace with:

```swift
            if result.outcome == .cancelled {
                if cancelledRun != run { hud.hide() }
            } else {
                if copyOnly, [.copiedNotConsumed, .copiedFocusChanged].contains(result.outcome) {
```

Edit 5 (end of `process(...)`). Find:

```swift
                if runCounter == run { lastRecordingFailedID = result.id }
            }
            isBusy = false
            languageCycler = nil
        }
    }
```

Replace with:

```swift
                if runCounter == run { lastRecordingFailedID = result.id }
            }
            if cancelledRun == run { cancelledRun = nil }
            processingTask = nil
            isBusy = false
            languageCycler = nil
        }
    }

    /// Esc while Transcribing or Cleaning: the run stops, nothing is pasted
    /// and nothing is kept in history.
    private func cancelProcessing(run: Int) {
        cancelledRun = run
        stagedRun = nil
        processingTask?.cancel()
        hud.show(.message(title: "Cancelled", detail: cancelDetail))
    }
```

Edit 6 (in `showStage`). Find:

```swift
        case .inserting: break
        }
```

Replace with:

```swift
        case .inserting: stagedRun = nil  // too late for Esc to stop the paste
        }
```

Edit 7 (in `redoInOtherLanguage`). Find:

```swift
        isBusy = true
        runCounter += 1
        let run = runCounter
        stagedRun = run
        Task { [self] in
            let result = await pipeline.run(
                clip: clip,
                startFocus: focus,
                startedAt: Date(),
                languageChoice: language
```

Replace with:

```swift
        isBusy = true
        runCounter += 1
        let run = runCounter
        stagedRun = run
        cancelDetail = "nothing was replaced"
        processingTask = Task { [self] in
            let result = await pipeline.run(
                clip: clip,
                startFocus: focus,
                startedAt: Date(),
                languageChoice: language
```

Edit 8 (in `redoInOtherLanguage`). Find:

```swift
            stagedRun = nil
            if result.outcome == .inserted {
                model.redoChain = advanced
```

Replace with:

```swift
            stagedRun = nil
            if result.outcome == .cancelled {
                if cancelledRun != run { hud.hide() }
            } else if result.outcome == .inserted {
                model.redoChain = advanced
```

Edit 9 (end of `redoInOtherLanguage`). Find:

```swift
            } else {
                showNothingToFix()
            }
            isBusy = false
        }
    }
```

Replace with:

```swift
            } else {
                showNothingToFix()
            }
            if cancelledRun == run { cancelledRun = nil }
            processingTask = nil
            isBusy = false
        }
    }
```

Run `swift build` (no new warnings) and `swift test` (whole suite must pass).

Commit: `feat(app): Esc cancels a dictation while it is transcribing or cleaning`

## Task 3 — docs

In `AGENTS.md`, find:

```
- Readiness card plan: `docs/superpowers/plans/2026-10-28-readiness-card.md`
```

and add these two lines directly below it:

```
- Cancel while processing spec: `docs/superpowers/specs/2026-10-28-cancel-processing-design.md` (mockup: `docs/design/proposal-cancel-processing.html`)
- Cancel while processing plan: `docs/superpowers/plans/2026-10-28-cancel-processing.md`
```

Then `git add AGENTS.md docs/superpowers/specs/2026-10-28-cancel-processing-design.md docs/design/proposal-cancel-processing.html docs/superpowers/plans/2026-10-28-cancel-processing.md`.

Commit: `docs: cancel while processing spec, mockup and plan`

## Finish

1. `swift test` — whole suite passes (expect 1,354 VoiceCore, 30 MCPKit, 114 BugVoiceMac).
2. `Scripts/build-app.sh` — builds and signs. Do not run the app.
3. Report: branch name, the three commit hashes with messages, test totals,
   whether the Task 1 tests failed before 1b, and any place the code did not
   match this plan.
