import AppKit
import ApplicationServices
import BugVoiceMac
import Foundation
import VoiceCore

/// Hotkey → gesture detector → recorder → pipeline → HUD → history.
///
/// Each run (a recording, or *Retry last*) gets an id. Stage updates
/// (Transcribing, Cleaning) are shown only while their run is the current one
/// and its final state has not been shown yet.
@MainActor
final class DictationController {
    private unowned let model: AppModel
    private let recorder = AudioRecorder()
    lazy var hud = HUDController(appearance: model.appearance)
    private lazy var preview = LivePreviewController(recorder: recorder, transcriber: model.previewWhisper, hud: hud)
    let inserter = PasteboardInserter()
    private var detector = HoldGestureDetector()
    private var languageCycler: LanguageKeyCycler?
    private var languageFlashTask: Task<Void, Never>?
    private var handsFreeRecording = false
    private var replacementGuard = ReplacementGuard()
    private var lastFocusedElement: AXUIElement?
    private var lastInsertionFocus: FocusSnapshot?
    private var hotkey: HotkeyMonitor!
    private var startFocus = FocusSnapshot.unknown
    private var correctionFocus: FocusSnapshot?
    private var correctionElement: AXUIElement?
    private var notesCapture: NotesDictationCapture?
    /// The meeting window's notes editor when it had the keyboard at the start.
    private var meetingNotes: MeetingNotesTextView?
    private var startedAt = Date()
    private var limitTask: Task<Void, Never>?
    private var runCounter = 0
    /// The run whose stage updates may still reach the HUD; nil once its
    /// final state is shown.
    private var stagedRun: Int?
    private(set) var isBusy = false
    var isRecording: Bool { recorder.isRunning }
    var recordingLevel: Float { recorder.level }

    init(model: AppModel) {
        self.model = model
        hud.levelSource = { [recorder] in recorder.level }
        hotkey = HotkeyMonitor(key: model.settings.hotkey) { [weak self] input in
            self?.receive(input)
        }
        hotkey.onKeyDown = { [weak self] keyCode, flags, userData in
            self?.keyDownObserved(keyCode: keyCode, flags: flags, userData: userData)
        }
        hotkey.onTapLost = { [weak self] in self?.tapLost() }
    }

    /// Call once settings are loaded.
    func start() {
        applySettings()
        model.hotkeyActive = hotkey.start()
    }

    func applySettings() {
        detector.handsFreeEnabled = model.settings.handsFreeEnabled
        hotkey.languageKey = model.settings.speech.languageKey
        inserter.restoreClipboard = model.settings.restoreClipboard
        if hotkey.key != model.settings.hotkey {
            hotkey.key = model.settings.hotkey
            detector.reset()
        }
    }

    /// Retries creating the tap, e.g. after Input Monitoring was granted or
    /// the system disabled it.
    func retryHotkey() {
        model.hotkeyActive = hotkey.start()
    }

    func toggleNotesRecording() {
        guard !isBusy, model.command?.isActive != true else { return }
        if recorder.isRunning {
            guard notesCapture != nil else { return }
            finish()
        } else {
            begin(handsFree: false, notesOnly: true)
        }
    }

    /// The monitor has stopped, so no key-up will end a hold: drop any
    /// recording in progress rather than leave the microphone on.
    private func tapLost() {
        model.hotkeyActive = false
        detector.reset()
        model.isListening = false
        if recorder.isRunning { cancel() }
    }

    // MARK: Gesture

    private func receive(_ input: KeyInput) {
        guard !isBusy, model.command?.isActive != true else { return }
        if case .hotkeyDown(let pressedAt) = input {
            // A result, warning or failure stays until the next press.
            if !recorder.isRunning, hud.model.state?.autoHideAfter != nil { hud.hide() }
            scheduleHoldTick(after: pressedAt)
        }
        for action in detector.handle(input) { perform(action) }
    }

    /// The detector starts a hold only when ticked `holdThreshold` after the
    /// key-down, measured from the event's own timestamp.
    private func scheduleHoldTick(after pressedAt: TimeInterval) {
        let due = pressedAt + detector.holdThreshold
        Task { [weak self] in
            let wait = max(0, due - ProcessInfo.processInfo.systemUptime) + 0.005
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !self.isBusy, self.model.command?.isActive != true else { return }
            for action in self.detector.tick(now: ProcessInfo.processInfo.systemUptime) { self.perform(action) }
        }
    }

    private func perform(_ action: GestureAction) {
        switch action {
        case .languageTap: cycleLanguage()
        case .startHold: begin(handsFree: false)
        case .startHandsFree: begin(handsFree: true)
        case .stop: finish()
        case .cancel: cancel()
        }
    }

    // MARK: Recording

    private func begin(handsFree: Bool, notesOnly: Bool = false) {
        guard !recorder.isRunning, model.command?.isActive != true else { return }
        model.correctionWatcher.stop()
        correctionFocus = nil
        correctionElement = nil
        replacementGuard.clear()
        lastFocusedElement = nil
        lastInsertionFocus = nil
        let micCapture = notesOnly ? model.captureSelectedNoteForMic() : nil
        guard !notesOnly || micCapture != nil else { return }
        if let notReady = speechNotReadyState() {
            if let micCapture { model.notesController.releaseCapture(micCapture) }
            detector.reset()
            hud.show(notReady)
            return
        }
        startFocus = FocusInspector.read()
        languageCycler = LanguageKeyCycler(
            start: LanguageResolver(settings: model.settings.speech).language(for: startFocus),
            languages: model.settings.speech.dictationLanguages
        )
        handsFreeRecording = handsFree
        meetingNotes = notesOnly ? nil : model.meetingNotesEditorWithKeyboard()
        notesCapture = notesOnly ? micCapture : meetingNotes == nil ? model.captureNotesDictation(startFocus: startFocus) : nil
        startedAt = Date()
        do {
            try recorder.start(deviceUID: model.settings.speech.microphoneUID)
        } catch {
            releaseNotesCapture()
            meetingNotes = nil
            detector.reset()
            languageCycler = nil
            let detail: String
            switch error {
            case RecorderError.deviceNotFound, RecorderError.deviceSelectionFailed:
                detail = "the selected microphone is not available; choose one in Settings"
            default:
                detail = Permissions.isGranted(.microphone) ? "check the input device" : "allow Microphone in Permissions"
            }
            hud.show(.failure(title: "Microphone unavailable", detail: detail))
            return
        }
        model.isListening = true
        model.notesIsListening = notesCapture != nil
        model.notesRecordingStartedAt = notesCapture == nil ? nil : startedAt
        if model.settings.soundsEnabled { NSSound(named: "Tink")?.play() }
        // The cap applies to holds too, so no recording runs unbounded even
        // if a key-up never arrives. The HUD shows it only in hands-free.
        let limit = TimeInterval(model.settings.handsFreeLimitMinutes * 60)
        showListening(languageChanged: false)
        preview.start(enabled: LivePreviewPolicy.isEnabled(settings: model.settings,
            secureField: startFocus.isSecure, meetingRecording: model.meetings?.isRecording == true,
            modelReady: model.previewModelReady),
            language: { [weak self] in self?.languageCycler?.current ?? .auto },
            prompt: model.settings.speech.useVocabularyHints ? model.vocabulary.whisperPrompt() : "")
        limitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled, let self else { return }
            self.detector.reset()
            self.finish()
        }
    }

    private func cycleLanguage() {
        guard recorder.isRunning, var cycler = languageCycler else { return }
        cycler.tap()
        languageCycler = cycler
        showListening(languageChanged: true)
        languageFlashTask?.cancel()
        languageFlashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, self.recorder.isRunning else { return }
            self.showListening(languageChanged: false)
        }
    }

    private func showListening(languageChanged: Bool) {
        guard let languageCycler else { return }
        hud.show(.listening(
            handsFree: handsFreeRecording,
            app: startFocus.appName,
            startedAt: startedAt,
            limit: handsFreeRecording ? TimeInterval(model.settings.handsFreeLimitMinutes * 60) : nil,
            language: languageCycler.current.shortCode,
            languageChanged: languageChanged
        ))
    }


    /// The HUD warning to show instead of recording while the on-device
    /// speech model is not ready (spec §7). Nil when dictation can start.
    func speechNotReadyState() -> HUDState? {
        guard model.settings.speech.engine == .whisperKit else { return nil }
        switch model.speechState {
        case .ready:
            return nil
        case .downloading(let fraction):
            return .warning(title: "Model loading", detail: "downloading \(Int(fraction * 100))%")
        case .loading, .notLoaded:
            return .warning(title: "Model loading", detail: "try again in a moment")
        case .failed:
            model.retrySpeech()
            return .warning(title: "Model loading", detail: "the last load failed, retrying")
        }
    }

    /// Option used as a modifier (e.g. ⌥E): nothing is pasted or logged.
    private func cancel() {
        preview.stop()
        limitTask?.cancel()
        detector.reset()
        languageFlashTask?.cancel()
        languageCycler = nil
        _ = recorder.stop()
        model.isListening = false
        releaseNotesCapture()
        meetingNotes = nil
        model.notesIsListening = false
        model.notesRecordingStartedAt = nil
        hud.hide()
    }

    private func finish() {
        preview.stop()
        limitTask?.cancel()
        model.isListening = recorder.isRunning
        guard recorder.isRunning else { return }
        let clip = recorder.stop()
        model.isListening = false
        detector.reset()
        languageFlashTask?.cancel()
        if model.settings.soundsEnabled { NSSound(named: "Pop")?.play() }
        let capturedNotesRun = notesCapture
        notesCapture = nil
        let capturedMeetingNotes = meetingNotes
        meetingNotes = nil
        model.notesIsListening = false
        model.notesRecordingStartedAt = nil
        if capturedNotesRun == nil && capturedMeetingNotes == nil {
            if startFocus.isSecure {
                // Likely a spoken secret: keep no audio of it. An older
                // last.wav goes too, so Retry last cannot replay another clip.
                try? FileManager.default.removeItem(at: model.paths.lastRecording)
            } else if clip.duration >= 0.3 {
                do {
                    try WAVEncoder.encode(clip).write(to: model.paths.lastRecording, options: .atomic)
                } catch {
                    model.saveError = "Could not save last.wav: \(error.localizedDescription)"
                }
            }
        }
        let languageChoice = languageCycler?.changed == true ? languageCycler?.current : nil
        process(clip, focus: startFocus, startedAt: startedAt, notesCapture: capturedNotesRun, meetingNotes: capturedMeetingNotes, languageChoice: languageChoice)
    }

    private func releaseNotesCapture() {
        if let notesCapture { model.notesController.releaseCapture(notesCapture) }
        notesCapture = nil
    }

    // MARK: Pipeline

    private func process(
        _ clip: AudioClip,
        focus: FocusSnapshot,
        startedAt: Date,
        notesCapture: NotesDictationCapture? = nil,
        meetingNotes: MeetingNotesTextView? = nil,
        languageChoice: SpeechLanguage? = nil
    ) {
        isBusy = true
        runCounter += 1
        let run = runCounter
        stagedRun = run
        let insertion: any InsertionTarget
        if let notesCapture {
            insertion = NotesEditorInsertion(controller: model.notesController, capture: notesCapture)
        } else if let meetingNotes {
            insertion = MeetingNotesInsertion(editor: meetingNotes)
        } else {
            insertion = RecordingPasteInsertionTarget(inserter: inserter) { [weak self] text in
                self?.recordOrdinaryInsertion(text, focus: focus)
            } onFailure: { [weak self] in self?.clearReplacementRecord() }
        }
        let intoNotes = notesCapture != nil || meetingNotes != nil
        let feature: ModelFeature = intoNotes ? .notes : .dictation
        let pipeline = model.makePipeline(insertion: insertion, feature: feature)
        let language = LanguageResolver(settings: model.settings.speech).language(for: focus, keyChoice: languageChoice).displayName
        let modelName = model.plan(for: feature).shortName
        Task { [self] in
            let result = await pipeline.run(
                clip: clip,
                startFocus: focus,
                startedAt: startedAt,
                mode: intoNotes ? .notes : .ordinary,
                languageChoice: languageChoice
            ) { stage in
                Task { @MainActor in
                    self.showStage(stage, run: run, language: language, modelName: modelName, app: focus.appName)
                }
            }
            stagedRun = nil
            if result.outcome == .inserted, !intoNotes, result.style != .terminal,
               !focus.isSecure, model.settings.speech.learnFromCorrections,
               let captured = correctionFocus,
               FocusInspector.isSameElement(correctionElement, FocusInspector.focusedElement()) {
                model.correctionWatcher.start(pasted: result.finalText, focus: captured, app: captured.appName)
            }
            correctionFocus = nil
            correctionElement = nil
            model.recordProjectMatch(result.projectName, app: focus.appName)
            Log.dictation.info("\(Diagnostics.dictationSummary(result), privacy: .public)")
            if let message = result.errorMessage { Log.dictation.error("\(message, privacy: .public)") }
            // Agents may edit the note again once this dictation is in.
            if let notesCapture { model.notesController.releaseCapture(notesCapture) }
            if intoNotes || result.outcome != .inserted { clearReplacementRecord() }
            if result.outcome == .cancelled {
                hud.hide()
            } else {
                if let state = HUDState.from(result) { hud.show(state) } else { hud.hide() }
                await model.recordInsights(result, noteID: notesCapture?.noteID)
                if !intoNotes { await model.record(result) }
            }
            isBusy = false
            languageCycler = nil
        }
    }

    private func showStage(_ stage: PipelineStage, run: Int, language: String, modelName: String?, app: String?) {
        guard stagedRun == run else { return }
        switch stage {
        case .transcribing: hud.show(.transcribing(language: language))
        case .cleaning: hud.show(.cleaning(model: modelName, app: app))
        case .inserting: break
        }
    }

    // MARK: Menu actions

    func retryLast() {
        model.correctionWatcher.cancel()
        guard model.command?.isActive != true, model.lastResult?.command == nil else { return }
        guard !isBusy, !recorder.isRunning else { return }
        if let notReady = speechNotReadyState() {
            hud.show(notReady)
            return
        }
        guard let data = try? Data(contentsOf: model.paths.lastRecording),
              let clip = try? WAVDecoder.decode(data) else { return }
        process(clip, focus: FocusInspector.read(), startedAt: Date())
    }

    func pasteLast() {
        guard let text = model.lastResult?.finalText else { return }
        paste(text)
    }

    func pasteRaw() {
        model.correctionWatcher.cancel()
        guard model.command?.isActive != true else { return }
        if let previous = model.lastResult, previous.command != nil {
            restoreCommandOriginal(previous)
            return
        }
        guard !isBusy, !recorder.isRunning,
              let previous = model.lastResult, !previous.finalText.isEmpty, !previous.uncleanedText.isEmpty else {
            showNothingToFix()
            return
        }
        if previous.uncleanedText == previous.finalText {
            let detail = previous.rawReason == .cleanupOff ? "cleanup is off for \(previous.style.title)" : nil
            hud.show(.message(title: "Already raw", detail: detail))
            return
        }
        guard let decision = replacementDecision() else {
            showNothingToFix()
            return
        }
        var replacement = previous
        replacement.finalText = previous.uncleanedText
        replacement.cleaned = nil
        replacement.rawReason = nil
        performDirectReplacement(replacement, kind: .raw, decision: decision, title: "Replaced with raw text")
    }

    func redoInOtherLanguage() {
        model.correctionWatcher.cancel()
        guard model.command?.isActive != true else { return }
        if model.lastResult?.command != nil { showNothingToFix(); return }
        guard !isBusy, !recorder.isRunning, let previous = model.lastResult,
              let focus = lastInsertionFocus,
              let data = try? Data(contentsOf: model.paths.lastRecording),
              let clip = try? WAVDecoder.decode(data) else {
            showNothingToFix()
            return
        }
        if let notReady = speechNotReadyState() {
            hud.show(notReady)
            return
        }
        guard let decision = replacementDecision() else {
            showNothingToFix()
            return
        }
        var chain = model.redoChain ?? RedoChain(original: previous.language)
        let language = chain.next(languages: model.settings.speech.dictationLanguages)
        model.redoChain = chain
        let adapter = ReplacementInsertionTarget(controller: self, initialDecision: decision)
        let pipeline = model.makePipeline(insertion: adapter, feature: .dictation)
        let modelName = model.plan(for: .dictation).shortName
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
            ) { stage in
                Task { @MainActor in
                    self.showStage(stage, run: run, language: language.displayName, modelName: modelName, app: focus.appName)
                }
            }
            stagedRun = nil
            if result.outcome == .inserted {
                await model.replaceLast(result, kind: .otherLanguage)
                rememberReplacement(text: result.finalText)
                hud.show(.message(
                    title: "Replaced — \(language.displayName)",
                    detail: "\(InsightsDelta.wordCount(result.finalText)) words"
                ))
            } else if result.outcome == .copiedSecureField || result.outcome == .copiedNotConsumed {
                clearReplacementRecord()
                hud.show(.message(title: "Copied — press ⌘V", detail: "text changed since the paste"))
            } else if let state = HUDState.from(result) {
                hud.show(state)
            } else {
                showNothingToFix()
            }
            isBusy = false
        }
    }

    private func selectBackDecision() -> ReplacementGuard.SelectBackDecision? {
        replacementGuard.decideSelectBack(now: Date(),
            frontProcessID: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,
            sameFocus: FocusInspector.isSameElement(lastFocusedElement, FocusInspector.focusedElement()))
    }

    private func restoreCommandOriginal(_ previous: DictationResult) {
        guard !isBusy, !isRecording else { return }
        guard !previous.finalText.isEmpty else { showNothingToFix(); return }
        isBusy = true
        Task { [self] in
            defer { isBusy = false }
            guard case .selectBack(let count)? = selectBackDecision(), !FocusInspector.read().isSecure else {
                await inserter.copy(previous.uncleanedText)
                hud.show(.message(title: "Copied — press ⌘V", detail: "text changed since the paste"))
                return
            }
            await inserter.selectBack(count)
            // A secure field must never receive even the original text.
            guard case .selectBack? = selectBackDecision(), !FocusInspector.read().isSecure else {
                await inserter.copy(previous.uncleanedText)
                clearReplacementRecord()
                hud.show(.message(title: "Copied — press ⌘V", detail: "text changed since the paste"))
                return
            }
            if previous.uncleanedText.isEmpty {
                // New text had no original: remove what was written.
                await inserter.deleteBackward(1)
                clearReplacementRecord()
                var replacement = previous
                replacement.finalText = ""
                replacement.cleaned = nil
                await model.replaceLast(replacement, kind: .raw)
                hud.show(.message(title: "Written text removed", detail: nil))
                return
            }
            let outcome = await inserter.insert(previous.uncleanedText)
            if outcome == .pasted {
                var replacement = previous
                replacement.finalText = previous.uncleanedText
                replacement.cleaned = nil
                await model.replaceLast(replacement, kind: .raw)
                rememberReplacement(text: replacement.finalText)
                hud.show(.message(title: "Original restored", detail: nil))
            } else {
                clearReplacementRecord()
                hud.show(.message(title: "Copied — press ⌘V", detail: "text changed since the paste"))
            }
        }
    }

    private func performDirectReplacement(_ replacement: DictationResult, kind: FixKind, decision: ReplacementDecision, title: String) {
        isBusy = true
        Task { [self] in
            guard case .replace(let count) = decision,
                  case .replace? = replacementDecision(),
                  !FocusInspector.read().isSecure else {
                await inserter.copy(replacement.finalText)
                hud.show(.message(title: "Copied — press ⌘V", detail: "text changed since the paste"))
                isBusy = false
                return
            }
            await inserter.deleteBackward(count)
            let outcome = await inserter.insert(replacement.finalText)
            if outcome == .pasted {
                await model.replaceLast(replacement, kind: kind)
                rememberReplacement(text: replacement.finalText)
                hud.show(.message(title: title, detail: "\(InsightsDelta.wordCount(replacement.finalText)) words"))
            } else {
                clearReplacementRecord()
                hud.show(.message(title: "Copied — press ⌘V", detail: "text changed since the paste"))
            }
            isBusy = false
        }
    }

    private func keyDownObserved(keyCode: Int64, flags: UInt64, userData: Int64) {
        let keyCodes = Set([
            ShortcutAction.pasteLast, .pasteRaw, .redoOtherLanguage,
        ].compactMap { ShortcutKeys.keyCode(forLetter: model.settings.shortcuts.letter(for: $0)) }.map(Int64.init))
        if FixLast.countsAsTyping(keyCode: keyCode, flags: flags, userData: userData, shortcutKeyCodes: keyCodes) {
            replacementGuard.keyTyped()
        }
    }

    func recordOrdinaryInsertion(_ text: String, focus: FocusSnapshot) {
        if model.settings.speech.learnFromCorrections, !focus.isSecure {
            correctionFocus = FocusInspector.read()
            correctionElement = FocusInspector.focusedElement()
        }
        guard !focus.isSecure else { clearReplacementRecord(); return }
        let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        replacementGuard.recordInsertion(LastInsertion(text: text, processID: processID, at: Date()))
        lastFocusedElement = FocusInspector.focusedElement()
        lastInsertionFocus = focus
    }

    private func rememberReplacement(text: String) {
        let focus = FocusInspector.read()
        guard !focus.isSecure else { clearReplacementRecord(); return }
        let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        replacementGuard.recordInsertion(LastInsertion(text: text, processID: processID, at: Date()))
        lastFocusedElement = FocusInspector.focusedElement()
        lastInsertionFocus = focus
    }

    func clearReplacementRecord() {
        replacementGuard.clear()
        lastFocusedElement = nil
        lastInsertionFocus = nil
    }

    private func replacementDecision() -> ReplacementDecision? {
        let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let sameFocus = FocusInspector.isSameElement(lastFocusedElement, FocusInspector.focusedElement())
        return replacementGuard.decide(now: Date(), frontProcessID: processID, sameFocus: sameFocus)
    }

    private func showNothingToFix() {
        hud.show(.message(title: "Nothing to fix", detail: nil))
    }

    fileprivate func insertReplacement(_ text: String, initialDecision: ReplacementDecision?) async -> InsertOutcome {
        guard case .replace(let count)? = initialDecision,
              case .replace? = replacementDecision(), !FocusInspector.read().isSecure else {
            await inserter.copy(text)
            return .notConsumed
        }
        await inserter.deleteBackward(count)
        return await inserter.insert(text)
    }

    fileprivate func copyReplacement(_ text: String) async {
        await inserter.copy(text)
    }

    /// Pastes `text` at the cursor of the app that had focus before BugVoice,
    /// or copies it only when that field is secure.
    func paste(_ text: String) {
        guard !isBusy, model.command?.isActive != true, !text.isEmpty else { return }
        if FocusInspector.read().isSecure {
            Task {
                await inserter.copy(text)
                hud.show(.secureFieldCopied)
            }
            return
        }
        Task { _ = await inserter.insert(text) }
    }

    /// History row action: hides BugVoice so focus returns to the previous
    /// app, waits for that activation, then pastes with the secure check.
    func pasteAgain(_ text: String) {
        NSApp.hide(nil)
        Task {
            await Self.waitUntilAnotherAppIsFrontmost(timeout: .seconds(1))
            // Activation lands before the target's key window restores focus.
            try? await Task.sleep(for: .milliseconds(60))
            paste(text)
        }
    }

    private static func waitUntilAnotherAppIsFrontmost(timeout: Duration) async {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let deadline = ContinuousClock.now + timeout
        while NSWorkspace.shared.frontmostApplication?.processIdentifier == ownPID,
              ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func copy(_ text: String) {
        Task { await inserter.copy(text) }
    }
}

@MainActor
private final class RecordingPasteInsertionTarget: InsertionTarget {
    private let inserter: PasteboardInserter
    private let onInserted: @MainActor @Sendable (String) -> Void
    private let onInsertedFailure: @MainActor @Sendable () -> Void

    init(inserter: PasteboardInserter, onInserted: @escaping @MainActor @Sendable (String) -> Void, onFailure: @escaping @MainActor @Sendable () -> Void) {
        self.inserter = inserter
        self.onInserted = onInserted
        onInsertedFailure = onFailure
    }

    func insert(_ text: String) async -> InsertOutcome {
        inserter.onWillPostPaste = onInserted
        let outcome = await inserter.insert(text)
        inserter.onWillPostPaste = nil
        if outcome != .pasted { onInsertedFailure() }
        return outcome
    }

    func copy(_ text: String) async { await inserter.copy(text) }
}

@MainActor
private final class ReplacementInsertionTarget: InsertionTarget {
    private unowned let controller: DictationController
    private let initialDecision: ReplacementDecision?

    init(controller: DictationController, initialDecision: ReplacementDecision?) {
        self.controller = controller
        self.initialDecision = initialDecision
    }

    func insert(_ text: String) async -> InsertOutcome {
        await controller.insertReplacement(text, initialDecision: initialDecision)
    }

    func copy(_ text: String) async { await controller.copyReplacement(text) }
}
