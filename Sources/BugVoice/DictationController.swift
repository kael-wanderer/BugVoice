import AppKit
import BugVoiceMac
import Carbon
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
    private let hud = HUDController()
    private let inserter = PasteboardInserter()
    private var detector = HoldGestureDetector()
    private var hotkey: HotkeyMonitor!
    private var startFocus = FocusSnapshot.unknown
    private var notesCapture: NotesDictationCapture?
    private var startedAt = Date()
    private var limitTask: Task<Void, Never>?
    private var runCounter = 0
    /// The run whose stage updates may still reach the HUD; nil once its
    /// final state is shown.
    private var stagedRun: Int?
    private(set) var isBusy = false
    var recordingLevel: Float { recorder.level }

    init(model: AppModel) {
        self.model = model
        hud.levelSource = { [recorder] in recorder.level }
        hotkey = HotkeyMonitor(key: model.settings.hotkey) { [weak self] input in
            self?.receive(input)
        }
        hotkey.onTapLost = { [weak self] in self?.tapLost() }
    }

    /// Call once settings are loaded.
    func start() {
        applySettings()
        model.hotkeyActive = hotkey.start()
        GlobalShortcuts.shared.register(keyCode: UInt32(kVK_ANSI_V), modifiers: GlobalShortcuts.controlOption) { [weak self] in
            self?.pasteLast()
        }
        GlobalShortcuts.shared.register(keyCode: UInt32(kVK_ANSI_B), modifiers: GlobalShortcuts.controlOption) { [weak self] in
            self?.model.openMainWindow(.dictation)
        }
    }

    func applySettings() {
        detector.handsFreeEnabled = model.settings.handsFreeEnabled
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
        guard !isBusy else { return }
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
        guard !isBusy else { return }
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
            guard let self, !self.isBusy else { return }
            for action in self.detector.tick(now: ProcessInfo.processInfo.systemUptime) { self.perform(action) }
        }
    }

    private func perform(_ action: GestureAction) {
        switch action {
        case .startHold: begin(handsFree: false)
        case .startHandsFree: begin(handsFree: true)
        case .stop: finish()
        case .cancel: cancel()
        }
    }

    // MARK: Recording

    private func begin(handsFree: Bool, notesOnly: Bool = false) {
        guard !recorder.isRunning else { return }
        let micCapture = notesOnly ? model.captureSelectedNoteForMic() : nil
        guard !notesOnly || micCapture != nil else { return }
        if let notReady = speechNotReadyState() {
            detector.reset()
            hud.show(notReady)
            return
        }
        startFocus = FocusInspector.read()
        notesCapture = notesOnly ? micCapture : model.captureNotesDictation(startFocus: startFocus)
        startedAt = Date()
        do {
            try recorder.start(deviceUID: model.settings.speech.microphoneUID)
        } catch {
            notesCapture = nil
            detector.reset()
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
        hud.show(.listening(handsFree: handsFree, app: startFocus.appName, startedAt: startedAt, limit: handsFree ? limit : nil))
        limitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled, let self else { return }
            self.detector.reset()
            self.finish()
        }
    }

    /// The HUD warning to show instead of recording while the on-device
    /// speech model is not ready (spec §7). Nil when dictation can start.
    private func speechNotReadyState() -> HUDState? {
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
        limitTask?.cancel()
        detector.reset()
        _ = recorder.stop()
        model.isListening = false
        notesCapture = nil
        model.notesIsListening = false
        model.notesRecordingStartedAt = nil
        hud.hide()
    }

    private func finish() {
        limitTask?.cancel()
        model.isListening = recorder.isRunning
        guard recorder.isRunning else { return }
        let clip = recorder.stop()
        model.isListening = false
        detector.reset()
        if model.settings.soundsEnabled { NSSound(named: "Pop")?.play() }
        let capturedNotesRun = notesCapture
        notesCapture = nil
        model.notesIsListening = false
        model.notesRecordingStartedAt = nil
        if capturedNotesRun == nil {
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
        process(clip, focus: startFocus, startedAt: startedAt, notesCapture: capturedNotesRun)
    }

    // MARK: Pipeline

    private func process(
        _ clip: AudioClip,
        focus: FocusSnapshot,
        startedAt: Date,
        notesCapture: NotesDictationCapture? = nil
    ) {
        isBusy = true
        runCounter += 1
        let run = runCounter
        stagedRun = run
        let insertion: any InsertionTarget
        if let notesCapture {
            insertion = NotesEditorInsertion(controller: model.notesController, capture: notesCapture)
        } else {
            insertion = inserter
        }
        let pipeline = model.makePipeline(insertion: insertion)
        let language = Self.languageLabel(model.settings.speech.language)
        let modelName = model.settings.textModel.shortName
        Task { [self] in
            let result = await pipeline.run(
                clip: clip,
                startFocus: focus,
                startedAt: startedAt,
                mode: notesCapture == nil ? .ordinary : .notes
            ) { stage in
                Task { @MainActor in
                    self.showStage(stage, run: run, language: language, modelName: modelName, app: focus.appName)
                }
            }
            stagedRun = nil
            if result.outcome == .cancelled {
                hud.hide()
            } else {
                if let state = HUDState.from(result) { hud.show(state) } else { hud.hide() }
                if notesCapture == nil { await model.record(result) }
            }
            isBusy = false
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

    private static func languageLabel(_ language: SpeechLanguage) -> String {
        switch language {
        case .auto: "Auto"
        case .en: "English"
        case .vi: "Vietnamese"
        }
    }

    // MARK: Menu actions

    func retryLast() {
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

    /// Pastes `text` at the cursor of the app that had focus before BugVoice,
    /// or copies it only when that field is secure.
    func paste(_ text: String) {
        guard !isBusy, !text.isEmpty else { return }
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
