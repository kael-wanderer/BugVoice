# BugVoice core review notes — 2026-10-27

Scope: source review of dictation, insertion, server STT, diagnostics, and existing benchmark evidence. No app launch, owner data access, audio submission, or synthetic paste. Findings below are supported by code paths; runtime reproduction remains a separate validation step. No production files changed and no tests run for this documentation-only review.

## Existing strengths

The app already has cleanup fidelity checks, raw-text fallback, dictionary/snippet protection, per-app languages, project vocabulary, secure-field copy-only behavior, clipboard restoration, retry/redo, stage timings, and optional live preview. These should be improved, not proposed as new features. Most behavior is isolated in Foundation-only VoiceCore with substantial tests. Incremental transcription already has a bench and a deliberately unpassed release gate; do not bypass it.

## P1 — Carry privacy classification through the entire dictation

**Confirmed control-flow gap.** `Sources/VoiceCore/DictationPipeline.swift:261` checks only the current focus before insertion. It does not retain `startFocus.isSecure`. A recording begun in a secure field and completed after moving to a normal field can become `.inserted`. `DictationResult.recallable` and `historyEntry` redact only `.copiedSecureField` (`:63`, `:77`), and `Sources/BugVoice/AppModel+Models.swift:130` records that result. Consequently that secure-start text can enter recall/history. Conversely, a normal-start recording that becomes secure is copy-only, but `Sources/BugVoice/DictationController.swift:287` has already written last.wav based solely on start focus and does not remove it on secure completion.

Plan: introduce per-run privacy classification independent of delivery outcome; conservatively mark sensitive if either focus snapshot is secure/unreadable. Apply it to history, last-result recall, Insights, retry audio, correction learning and diagnostics. Delete retained retry audio when the run becomes sensitive. Preserve existing copy-only UX. Evaluate whether remote processing of secure-start dictation should be separately disabled; this is a product policy decision, not an asserted current requirement.

Acceptance: transition matrix secure→ordinary, ordinary→secure, secure→secure and ordinary→ordinary with deterministic focus fakes. Sensitive cases never produce history/recall/Insights/retry audio; secure current focus never receives synthetic paste. Test failure/cancel paths too.

## P1 — Apply provider privacy protections to server transcription

**Confirmed inconsistency.** `Sources/VoiceCore/OpenAICompatibleTranscriber.swift:11` defaults to `URLSession.shared`; `Sources/BugVoice/ProviderFactory.swift:74` uses that default. Other model providers use `HTTP.noRedirectSession`, which explicitly refuses redirects (`Sources/VoiceCore/HTTP.swift:3`, `:25`). STT sends multipart audio plus vocabulary prompt and an optional Authorization header (`OpenAICompatibleTranscriber.swift:34–45`). Its request currently can follow redirects under URLSession behavior rather than enforcing the intended host boundary. Exact redirect credential propagation depends on OS/redirect type and was not tested.

The same STT path calls `HTTP.send` without body redaction. HTTP errors retain up to 2,000 bytes and malformed responses retain 500 (`HTTP.swift:34`, `:52`). `DictationPipeline.swift:181` uses `String(describing: error)`, which includes associated enum payloads, and `DictationController.swift:362` writes the resulting message with public log privacy. A server that echoes request text/key material into an error can therefore expose it in diagnostics. This is conditional on server response contents; it is not evidence that existing logs contain secrets.

Plan: use the no-redirect session consistently, redact all content-bearing HTTP error bodies regardless of whether a key exists, and introduce typed safe diagnostics (provider, status, category, duration) instead of logging arbitrary error descriptions. Keep actionable user messages. Audit cleanup malformed-response paths under the same rule.

Acceptance: stub 307/308 redirects and assert no second-host upload; response fixtures containing a sentinel secret in HTTP error and malformed JSON must not reach result messages or diagnostic output. Add keyed and keyless cases. No real credentials or remote request needed.

## P1/P2 — Make destination changes safe and cancellation complete

**Confirmed behavior; product improvement rather than a proven violation of existing design.** Ordinary insertion checks security, but not app/element identity (`DictationPipeline.swift:261–269`). `PasteboardInserter.swift:32` posts Command-V to whichever app is frontmost. Switching apps while transcription/cleanup runs can insert text into a different destination from the one used to choose style and language. Command mode and fix-last already have stronger focus checks, so those patterns can inform this work.

The processing task is created without retaining a handle (`DictationController.swift:338`), while `cancel()` stops recording/preview but not that processing task (`:241–255`). Additionally cleanup cancellation is caught as a model error (`DictationPipeline.swift:233–238`) and there is no final cancellation guard before insertion. A future Stop button that merely cancels the task would not be sufficient.

Plan: capture an insertion destination token at recording start; before posting paste, compare app identity and accessible field identity. On change, retain text and show “Copied — destination changed” with an explicit recovery action. Define browser/tab and inaccessible-AX fallbacks. Retain processing task and implement Cancel through transcription, cleanup, and pre-insert; late results must be ignored. Avoid claiming cancellation can instantly halt Core ML; suppress side effects immediately while compute unwinds.

Acceptance: fake focus changes during STT/cleanup, cancellation during each stage, late model success after cancellation, and user focus change immediately before insertion. Owner-operated device checks in a terminal, browser editor, and native editor; never perform synthetic paste while the owner is using the keyboard.

## P2 — Preserve literal bracketed text before fidelity checking

**Confirmed transformation.** `DictationPipeline.stripPlaceholders` (`Sources/VoiceCore/DictationPipeline.swift:124–127`) removes every square-bracketed span, not just known Whisper annotations. A transcript such as `use items[0]` becomes `use items`, and Markdown `[label](url)` loses its label before `result.raw` is recorded. Later cleanup fidelity cannot detect text already discarded. Existing tests exercise `[BLANK_AUDIO]` and `[Music]` (`Tests/VoiceCoreTests/DictationPipelineTests.swift:413`, `:439`) but do not justify dropping arbitrary brackets.

Plan: strip an explicit normalized allowlist of known non-speech annotations, preserve all other bracketed content, and review the hallucination filter for similarly broad transformations. Keep a distinction between engine output and normalized raw text where useful for local debugging without expanding persistent retention by default.

Acceptance: failing tests first for arrays/indexing, Markdown links, bracketed Vietnamese text, nested/unmatched brackets, and existing known-placeholder cases. Assert byte preservation for literal content and continued rejection of annotation-only silence.

## P2 — Do real-voice latency/quality evaluation before incremental rollout

**Existing unresolved evidence gate, not a new architecture proposal.** `docs/progress/HANDOFF.md` records synthetic 30s+ incremental savings of 0.85s English, 0.88s mixed and 1.18s Vietnamese against the original 1.0s target; preview reduced mixed savings to 0.47s. The owner chose a real-voice rerun and possible 0.8s gate. Current preview invalidates results on stop but Core ML cancellation is not immediate (`Sources/BugVoice/HUD/LivePreviewController.swift:51`, `Sources/WhisperEngine/WhisperKitTranscriber.swift:130–141`).

Plan: finish the six real-voice recordings and existing bench first. Report release-to-visible-text p50/p95 separately from clipboard restore time and STT/cleanup stage time; include preview on/off, short/long speech, mixed language, cold/warm state, background meeting/upload work, correction rate and fidelity false positives. StageTimings currently includes the insertion wait and restoration delay (`PasteboardInserter.swift:34–46`), so it is not an exact measurement of visible text latency. If the agreed quality/latency gate passes, implement incremental transcription with explicit preview/part-pass scheduling and fallback to full final transcription. Otherwise keep the simpler pipeline and tune measured bottlenecks.

Acceptance: published real-voice report with confidence/sample-size limits, no short-dictation regression, existing WER limits met, preview contention addressed, and device release-to-visible-text observations. Do not infer hardware success from unit tests.

## Suggested execution order and estimates

1. Privacy propagation + safe server diagnostics/redirects: 2–3 implementation days, with independent VoiceCore tests and app integration.
2. Destination checks + full processing cancellation: 2–3 days plus owner device checks.
3. Literal transcript preservation: 0.5–1 day.
4. Real-voice bench and decision record: 0.5–1 engineering day after recordings are supplied; incremental implementation scope estimated only after the gate.

These are planning estimates, not commitments. Each core change follows the repository's failing-test-first rule, runs `swift test`, and gets a signed app build and relevant owner device checks before release. Privacy and destination reliability should precede adding more feature breadth.
