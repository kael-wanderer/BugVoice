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
    private var startedAt = Date()
    private var limitTask: Task<Void, Never>?
    private var runCounter = 0
    /// The run whose stage updates may still reach the HUD; nil once its
    /// final state is shown.
    private var stagedRun: Int?
    private(set) var isBusy = false

    init(model: AppModel) {
        self.model = model
        hud.levelSource = { [recorder] in recorder.level }
        hotkey = HotkeyMonitor(key: model.settings.hotkey) { [weak self] input in
            self?.receive(input)
        }
        hotkey.onTapLost = { [weak model] in model?.hotkeyActive = false }
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

    private func begin(handsFree: Bool) {
        guard !recorder.isRunning else { return }
        if let notReady = speechNotReadyState() {
            detector.reset()
            hud.show(notReady)
            return
        }
        startFocus = FocusInspector.read()
        startedAt = Date()
        do {
            try recorder.start(deviceUID: model.settings.speech.microphoneUID)
        } catch {
            detector.reset()
            hud.show(.failure(
                title: "Microphone unavailable",
                detail: Permissions.isGranted(.microphone) ? "check the input device" : "allow Microphone in Permissions"
            ))
            return
        }
        if model.settings.soundsEnabled { NSSound(named: "Tink")?.play() }
        let limit = handsFree ? TimeInterval(model.settings.handsFreeLimitMinutes * 60) : nil
        hud.show(.listening(handsFree: handsFree, app: startFocus.appName, startedAt: startedAt, limit: limit))
        if let limit {
            limitTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(limit))
                guard !Task.isCancelled, let self else { return }
                self.detector.reset()
                self.finish()
            }
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
            Task { await model.prepareSpeech() }
            return .warning(title: "Model loading", detail: "the last load failed, retrying")
        }
    }

    /// Option used as a modifier (e.g. ⌥E): nothing is pasted or logged.
    private func cancel() {
        limitTask?.cancel()
        _ = recorder.stop()
        hud.hide()
    }

    private func finish() {
        limitTask?.cancel()
        guard recorder.isRunning else { return }
        let clip = recorder.stop()
        detector.reset()
        if model.settings.soundsEnabled { NSSound(named: "Pop")?.play() }
        if clip.duration >= 0.3 {
            do {
                try WAVEncoder.encode(clip).write(to: model.paths.lastRecording, options: .atomic)
            } catch {
                model.saveError = "Could not save last.wav: \(error.localizedDescription)"
            }
        }
        process(clip, focus: startFocus, startedAt: startedAt)
    }

    // MARK: Pipeline

    private func process(_ clip: AudioClip, focus: FocusSnapshot, startedAt: Date) {
        isBusy = true
        runCounter += 1
        let run = runCounter
        stagedRun = run
        let pipeline = model.makePipeline(insertion: inserter)
        let language = Self.languageLabel(model.settings.speech.language)
        let modelName = model.settings.textModel.shortName
        Task { [self] in
            let result = await pipeline.run(clip: clip, startFocus: focus, startedAt: startedAt) { stage in
                Task { @MainActor in
                    self.showStage(stage, run: run, language: language, modelName: modelName, app: focus.appName)
                }
            }
            stagedRun = nil
            if Self.isCancellation(result) {
                hud.hide()
            } else {
                if let state = HUDState.from(result) { hud.show(state) } else { hud.hide() }
                await model.record(result)
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

    /// A transcription cut short by cancellation is not a failure to report.
    private static func isCancellation(_ result: DictationResult) -> Bool {
        result.outcome == .transcriptionFailed
            && result.errorMessage == String(describing: CancellationError())
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
        guard !isBusy, let text = model.lastResult?.finalText, !text.isEmpty else { return }
        Task { _ = await inserter.insert(text) }
    }
}
