# Trust fixes — plan for Codex Luna (2026-10-27)

Source: `docs/research/2026-10-27-app-review-and-improvement-plan.md` (Phase 1, verified
by Claude against `864c404`). Five small fixes. Every decision is made below; do not
redesign, do not widen scope. If something here does not match the code, stop and report
instead of improvising.

## Ground rules

- Read `AGENTS.md` first. Swift Testing (`@Test`, `#expect`), not XCTest.
- Work on a new branch: `git switch -c fix/trust-fixes` from `main`.
- For each task: write the failing test, run it and see it fail, then change the code,
  then run `swift test` (whole suite must pass), then commit. One commit per task.
- Commit message style is given per task. End every commit message with a blank line and
  `Co-Authored-By: Codex <noreply@openai.com>`.
- The pre-commit hook bumps the build number in `App/Info.plist`; let it.
- Do not launch the app, do not send synthetic input, do not push.
- Touch only the files named below.

## Task 1 — a dictation that starts in a secure field stays copy-only

Problem: `Sources/VoiceCore/DictationPipeline.swift` (insert section, ~line 260) checks only
the focus at insert time. Start in a password field, click into a normal field while it
transcribes, and the text is pasted and saved to history.

Test — add to `Tests/VoiceCoreTests/DictationPipelineTests.swift`, next to
`secureFieldAtInsertTimeCopiesOnly`:

```swift
    @Test func secureFieldAtStartCopiesOnlyEvenWhenFocusMoves() async {
        let insertion = RecordingInsertion()
        let r = await pipeline(insertion: insertion, focusAtInsert: notionFocus)
            .run(clip: speechClip, startFocus: FocusSnapshot(bundleID: "com.apple.Safari", isSecure: true),
                 startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .copiedSecureField)
        #expect(await insertion.inserted.isEmpty)
        #expect(await insertion.copied.count == 1)
        #expect(r.historyEntry == nil)
        #expect(r.recallable.finalText.isEmpty)
    }
```

Code — in `DictationPipeline.run`, ordinary branch, change:

```swift
            if current.isSecure {
```

to:

```swift
            // A run that began in a secure field stays secure even if focus moved.
            if startFocus.isSecure || current.isSecure {
```

Commit: `fix(core): a dictation that starts in a secure field stays copy-only`

## Task 2 — speech server never follows redirects and hides keyed error bodies

Problem: `Sources/VoiceCore/OpenAICompatibleTranscriber.swift` defaults to
`URLSession.shared` (follows redirects, resending audio and the key) and never sets
`redactBody`. Every other provider defaults to `HTTP.noRedirectSession`.

Tests — add to `Tests/VoiceCoreTests/TranscriberTests.swift` inside the existing
`extension ProviderTests { ... }` (same pattern as the tests already there):

```swift
    @Test func transcriberDefaultsToNoRedirectSession() {
        let t = OpenAICompatibleTranscriber(baseURL: URL(string: "http://h")!, model: "m")
        #expect(t.session === HTTP.noRedirectSession)
    }

    @Test func transcriberTreatsRedirectAsError() async {
        StubURLProtocol.handler = { _, _ in (307, Data()) }
        let t = OpenAICompatibleTranscriber(baseURL: URL(string: "http://h")!, model: "m", apiKey: "K", session: StubURLProtocol.session())
        await #expect(throws: ProviderError.redirected) {
            try await t.transcribe(AudioClip(samples: [0]), options: TranscriptionOptions())
        }
    }

    @Test func transcriberDropsErrorBodyWhenKeyed() async {
        StubURLProtocol.handler = { _, _ in (500, Data("SENTINEL-SECRET".utf8)) }
        let t = OpenAICompatibleTranscriber(baseURL: URL(string: "http://h")!, model: "m", apiKey: "K", session: StubURLProtocol.session())
        await #expect(throws: ProviderError.http(status: 500, body: "")) {
            try await t.transcribe(AudioClip(samples: [0]), options: TranscriptionOptions())
        }
    }
```

Code — in `OpenAICompatibleTranscriber.swift`:

1. `session: URLSession = .shared` becomes `session: URLSession = HTTP.noRedirectSession`.
2. The send line becomes:

```swift
        let keyed = !(apiKey ?? "").isEmpty
        let reply = try HTTP.decode(Reply.self, from: try await HTTP.send(request, session: session, redactBody: keyed))
```

Commit: `fix(core): speech server refuses redirects and hides keyed error bodies`

## Task 3 — error text never carries a response body

Problem: transcription errors are stored with `String(describing: error)`, which prints the
raw enum including up to 2,000 characters of response body, and
`Sources/BugVoice/DictationController.swift:361` logs it with `privacy: .public`.
`HTTP.decode` also copies 500 bytes of the reply into `.malformedResponse`, and
`ProviderError.http`'s description appends up to 200 characters of body.

Tests — add to `Tests/VoiceCoreTests/ProviderTests.swift` (inside `struct ProviderTests`
or an `extension ProviderTests`, matching the file):

```swift
    @Test func errorDescriptionsNeverIncludeTheBody() {
        let http = ProviderError.http(status: 418, body: "SENTINEL-SECRET")
        #expect(http.localizedDescription == "The service answered with status 418.")
    }

    @Test func malformedReplyKeepsNoReplyText() {
        #expect(throws: ProviderError.self) {
            _ = try HTTP.decode([String: Int].self, from: Data("SENTINEL-SECRET".utf8))
        }
        do {
            _ = try HTTP.decode([String: Int].self, from: Data("SENTINEL-SECRET".utf8))
        } catch {
            #expect(!String(describing: error).contains("SENTINEL"))
        }
    }
```

Add to `Tests/VoiceCoreTests/DictationPipelineTests.swift`:

```swift
    @Test func transcriptionErrorMessageHasNoResponseBody() async {
        let failing = FakeTranscriber(error: ProviderError.http(status: 400, body: "SENTINEL-SECRET"))
        let r = await pipeline(transcriber: failing).run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.outcome == .transcriptionFailed)
        #expect(r.errorMessage?.contains("SENTINEL") == false)
    }
```

Code:

1. `Sources/VoiceCore/TextModel.swift`, `ProviderError.errorDescription`, the `default:`
   line in the `.http` case becomes:

   ```swift
            default: "The service answered with status \(status)."
   ```

   Leave the stored `body` field as is.
2. `Sources/VoiceCore/HTTP.swift`, in `decode`, replace the throw with:

   ```swift
            throw ProviderError.malformedResponse("\(data.count)-byte reply")
   ```

3. Replace `String(describing: error)` with `error.localizedDescription` in exactly these
   places (all store text that is shown or logged):
   - `Sources/VoiceCore/DictationPipeline.swift:181`
   - `Sources/VoiceCore/MeetingTranscription.swift:136` and `:212`
   - `Sources/VoiceCore/MeetingSession.swift:246` and `:424`

   Leave `AudioRecorder.swift` and `UploadController.swift` alone (no provider bodies there).
4. If an existing test asserts the old text from one of these places, change only its
   expected value to the new `localizedDescription` text. If a test fails for any other
   reason, stop and report.

Commit: `fix(core): provider errors never carry the response body`

## Task 4 — keep dictated square brackets

Problem: `DictationPipeline.stripPlaceholders` removes every `[...]` span, so
`use items[0]` becomes `use items`. Only Whisper's own annotations should go.
(Leave `HallucinationFilter.isHallucination` alone: it only decides whether a whole
transcript is annotation-only.)

Tests — add to `Tests/VoiceCoreTests/DictationPipelineTests.swift`:

```swift
    @Test(arguments: [
        ("[BLANK_AUDIO] merge the branch", "merge the branch"),
        ("[ Music ] hello [MUSIC PLAYING]", "hello"),
        ("[inaudible] sửa lỗi build", "sửa lỗi build"),
        ("use items[0] here", "use items[0] here"),
        ("return [String] values", "return [String] values"),
        ("mark it [draft] for now", "mark it [draft] for now"),
        ("see [the docs](https://example.com) now", "see [the docs](https://example.com) now"),
    ])
    func stripPlaceholdersRemovesOnlyWhisperAnnotations(input: String, expected: String) {
        #expect(DictationPipeline.stripPlaceholders(input) == expected)
    }

    @Test func bracketedCodeReachesTheResult() async {
        let r = await pipeline(transcriber: FakeTranscriber(text: "use items[0] here"), model: nil)
            .run(clip: speechClip, startFocus: notionFocus, startedAt: Date(), onStage: { _ in })
        #expect(r.finalText == "use items[0] here")
    }
```

Code — replace `stripPlaceholders` (and its doc comment) in `DictationPipeline.swift` with:

```swift
    /// Whisper's own annotations, compared lowercased with `_` read as a space.
    static let annotations: Set<String> = [
        "blank audio", "music", "music playing", "silence", "applause", "laughter", "laughs",
        "noise", "background noise", "inaudible", "sound", "no speech", "typing", "clicking",
        "coughs", "coughing", "sighs", "breathing", "pause", "wind", "static", "beep",
    ]

    /// Removes Whisper annotations such as `[BLANK_AUDIO]` or `[Music]`. Any other
    /// bracketed text (`items[0]`, `[String]`, `[draft]`) was dictated and stays.
    /// Parentheses stay: dictated text may use them.
    static func stripPlaceholders(_ text: String) -> String {
        text.replacing(/\[([^\[\]]*)\]/) { match in
            let inner = match.output.1.replacingOccurrences(of: "_", with: " ")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
            return annotations.contains(inner) ? " " : String(match.output.0)
        }
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    }
```

The existing tests around `DictationPipelineTests.swift:413-439` (`[BLANK_AUDIO]`, `[Music]`)
must still pass unchanged.

Commit: `fix(core): keep dictated square brackets, strip only Whisper annotations`

## Task 5 — Permissions copy points at sections that exist

`Sources/BugVoice/UI/PermissionsView.swift:19` says "Settings → Text model"; Settings now has
"Models" and "Speech". Change the string to:

```swift
            Text("Nothing you say leaves this Mac unless you set a remote server in Settings → Models or Settings → Speech.")
```

No test. Run `swift test`.

Commit: `fix(app): Permissions copy names the Models and Speech settings`

## Finish

1. `swift test` — whole suite passes.
2. `Scripts/build-app.sh` — builds and signs. Do not run the app.
3. Do not merge or push. Report: branch name, the five commit hashes with messages,
   test totals from the last `swift test`, and any place where the code did not match
   this plan.
