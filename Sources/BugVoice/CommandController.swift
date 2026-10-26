import AppKit
import ApplicationServices
import BugVoiceMac
import Foundation
import VoiceCore

@MainActor
final class CommandController {
    private unowned let model: AppModel
    private let recorder = AudioRecorder()
    private let capture = SelectionCapture()
    private var monitor: HotkeyMonitor?
    private var detector = HoldGestureDetector()
    private enum Phase { case idle, capturing, recording, processing, delivering }
    private var phase: Phase = .idle
    var isActive: Bool { phase != .idle }
    private var runID = UUID()
    private var task: Task<Void, Never>?
    private var limitTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?
    private var releasedDuringCapture = false
    private var drainingTail = false
    private var drainTask: Task<Void, Never>?
    private var startFocus = FocusSnapshot.unknown
    private var startElement: AXUIElement?
    private var startPID: Int32 = 0
    private var selection: String?
    private var startedAt = Date()
    private var cycler: LanguageKeyCycler?
    private var hud: HUDController? { model.dictation?.hud }
    private var preview: LivePreviewController?

    init(model: AppModel) { self.model = model }
    func start() { applySettings() }

    func applySettings() {
        let key = model.settings.effectiveCommandKey.hotkeyKey
        if monitor?.key != key {
            cancel()
            monitor?.stop()
            monitor = nil
        }
        guard let key else { return }
        if monitor == nil {
            let monitor = HotkeyMonitor(key: key) { [weak self] input in self?.receive(input) }
            monitor.onKeyDown = { [weak self] code, _, marker in
                guard marker != FixLast.syntheticEventMarker, code == 53, self?.phase == .processing else { return }
                self?.cancel()
            }
            monitor.onTapLost = { [weak self] in self?.cancel() }
            self.monitor = monitor
        }
        detector.handsFreeEnabled = false
        monitor?.languageKey = model.settings.speech.languageKey
        _ = monitor?.start()
    }

    private func receive(_ input: KeyInput) {
        guard phase != .processing, phase != .delivering else { return }
        if phase == .idle, model.dictation?.isBusy == true || model.dictation?.isRecording == true {
            detector.reset()
            return
        }
        if case .hotkeyDown(let at) = input {
            let due = at + detector.holdThreshold
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, due - ProcessInfo.processInfo.systemUptime) + 0.005))
                guard let self, self.phase == .idle,
                      self.model.dictation?.isBusy != true, self.model.dictation?.isRecording != true else { return }
                for action in self.detector.tick(now: ProcessInfo.processInfo.systemUptime) { self.perform(action) }
            }
        }
        for action in detector.handle(input) { perform(action) }
    }

    private func perform(_ action: GestureAction) {
        switch action {
        case .startHold: begin()
        case .stop:
            if phase == .capturing { releasedDuringCapture = true } else { finish() }
        case .cancel: cancel()
        case .languageTap: cycleLanguage()
        case .startHandsFree: break
        }
    }

    private func begin() {
        guard !isActive, model.dictation?.isBusy != true, model.dictation?.isRecording != true else { return }
        model.correctionWatcher.stop()
        startFocus = FocusInspector.read()
        guard !startFocus.isSecure else {
            detector.reset()
            hud?.show(.message(title: "Secure field — command not run", detail: nil))
            return
        }
        // The note editor already has its own AI bar.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            detector.reset()
            return
        }
        if let warning = model.dictation?.speechNotReadyState() {
            detector.reset()
            hud?.show(warning)
            return
        }
        startElement = FocusInspector.focusedElement()
        startPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        model.dictation?.clearReplacementRecord()
        phase = .capturing
        releasedDuringCapture = false
        runID = UUID()
        let id = runID
        task = Task { [self] in
            let selected = await capture.capture(axSelection: startFocus.selectedText)
            guard !Task.isCancelled, runID == id else { return }
            selection = selected
            guard (selected?.count ?? 0) <= CommandPrompt.maxSelection else {
                phase = .idle
                detector.reset()
                showFailure(.selectionTooLong)
                return
            }
            guard !FocusInspector.read().isSecure else {
                phase = .idle
                detector.reset()
                hud?.show(.message(title: "Secure field — command not run", detail: nil))
                return
            }
            cycler = LanguageKeyCycler(
                start: LanguageResolver(settings: model.settings.speech).language(for: startFocus),
                languages: model.settings.speech.dictationLanguages
            )
            startedAt = Date()
            do {
                try recorder.start(deviceUID: model.settings.speech.microphoneUID)
            } catch {
                phase = .idle
                detector.reset()
                hud?.show(.failure(title: "Microphone unavailable", detail: "check the input device"))
                return
            }
            phase = .recording
            model.isListening = true
            hud?.levelSource = { [recorder] in recorder.level }
            if model.settings.soundsEnabled { NSSound(named: "Tink")?.play() }
            showListening(changed: false)
            if let hud {
                if preview == nil {
                    preview = LivePreviewController(recorder: recorder, transcriber: model.previewWhisper, hud: hud)
                }
                preview?.start(enabled: LivePreviewPolicy.isEnabled(settings: model.settings,
                    secureField: startFocus.isSecure, meetingRecording: model.meetings?.isRecording == true,
                    modelReady: model.previewModelReady),
                    language: { [weak self] in self?.cycler?.current ?? .auto },
                    prompt: model.settings.speech.useVocabularyHints ? model.vocabulary.whisperPrompt() : "")
            }
            limitTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.model.settings.handsFreeLimitMinutes * 60))
                guard !Task.isCancelled, self.runID == id else { return }
                self.finish()
            }
            if releasedDuringCapture { finish() }
        }
    }

    private func showListening(changed: Bool) {
        guard let cycler else { return }
        let language = cycler.current.shortCode
        hud?.show(.commandListening(selectionCharacters: selection?.count, app: startFocus.appName,
            startedAt: startedAt, language: language, languageChanged: changed))
    }

    private func cycleLanguage() {
        guard phase == .recording, var cycler else { return }
        cycler.tap()
        self.cycler = cycler
        showListening(changed: true)
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, self.phase == .recording else { return }
            self.showListening(changed: false)
        }
    }

    private func finish() {
        guard phase == .recording, !drainingTail else { return }
        let tail = recorder.releaseTail
        guard tail > 0 else { return finishNow() }
        drainingTail = true
        drainTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(tail))
            guard !Task.isCancelled, let self else { return }
            self.drainingTail = false
            self.finishNow()
        }
    }

    private func finishNow() {
        preview?.stop()
        guard phase == .recording else { return }
        let clip = recorder.stop()
        model.isListening = false
        detector.reset()
        limitTask?.cancel()
        flashTask?.cancel()
        phase = .processing
        if model.settings.soundsEnabled { NSSound(named: "Pop")?.play() }
        let id = runID
        let focus = startFocus
        let selected = selection
        let languageChoice = cycler?.changed == true ? cycler?.current : nil
        let language = cycler?.current.displayName ?? "Auto"
        let pipeline = model.makeCommandPipeline()
        let name = model.plan(for: .dictation).shortName
        task = Task { [self] in
            let result = await pipeline.run(clip: clip, selection: selected, startFocus: focus, startedAt: startedAt,
                languageChoice: languageChoice) { stage in
                Task { @MainActor [weak self] in
                    guard let self, self.runID == id, self.phase == .processing else { return }
                    switch stage {
                    case .transcribing: self.hud?.show(.transcribing(language: language))
                    case .cleaning: self.hud?.show(.rewriting(model: name, app: focus.appName))
                    case .inserting: break
                    }
                }
            }
            guard !Task.isCancelled, runID == id else { return }
            // Invalidate queued stage callbacks before showing a final state.
            runID = UUID()
            phase = .delivering
            switch result {
            case .cancelled:
                log(outcome: "cancelled")
                hud?.hide()
            case .nothingHeard:
                log(outcome: "nothingHeard")
                hud?.show(.nothingHeard)
            case .failed(let failure):
                log(outcome: "failed_\(failure)")
                showFailure(failure)
            case .ready(var ready):
                model.recordProjectMatch(ready.projectName, app: focus.appName)
                guard let dictation = model.dictation else { phase = .idle; return }
                let now = FocusInspector.read()
                let sameElement = startPID == NSWorkspace.shared.frontmostApplication?.processIdentifier
                    && FocusInspector.isSameElement(startElement, FocusInspector.focusedElement())
                let decision = CommandPaste.decide(start: focus, now: now, sameElement: sameElement, style: ready.style)
                let mark = Date()
                switch decision {
                case .secure:
                    await dictation.inserter.copy(ready.finalText)
                    ready.outcome = .copiedSecureField
                    hud?.show(.secureFieldCopied)
                case .copy(let reason):
                    await dictation.inserter.copy(ready.finalText)
                    ready.outcome = .copiedNotConsumed
                    hud?.show(.message(title: "Copied — press ⌘V", detail: reason))
                case .paste:
                    dictation.inserter.onWillPostPaste = { [weak dictation] text in
                        dictation?.recordOrdinaryInsertion(text, focus: focus)
                    }
                    let outcome = await dictation.inserter.insert(ready.finalText)
                    dictation.inserter.onWillPostPaste = nil
                    ready.outcome = outcome == .pasted ? .inserted : .copiedNotConsumed
                    if outcome == .pasted {
                        hud?.show(.message(title: selected == nil ? "Written" : "Rewritten · ⌘Z to undo",
                            detail: "\(InsightsDelta.wordCount(ready.finalText)) words"))
                    } else {
                        dictation.clearReplacementRecord()
                        hud?.show(.message(title: "Copied — press ⌘V", detail: "paste not picked up"))
                    }
                }
                ready.timings.insert = Date().timeIntervalSince(mark)
                log(outcome: ready.outcome.rawValue, characters: ready.finalText.count,
                    words: InsightsDelta.wordCount(ready.finalText), transcribe: ready.timings.transcribe, clean: ready.timings.clean)
                await model.record(ready)
            }
            phase = .idle
            cycler = nil
            hud?.levelSource = { [weak model] in model?.dictation?.recordingLevel ?? 0 }
        }
    }

    private func log(outcome: String, characters: Int = 0, words: Int = 0, transcribe: Double = 0, clean: Double = 0) {
        let summary = "command outcome=\(outcome) app=\(startFocus.appName ?? "Unknown") chars=\(characters) words=\(words) stt=\(String(format: "%.2f", transcribe))s model=\(String(format: "%.2f", clean))s"
        Log.dictation.info("\(summary, privacy: .public)")
    }

    private func showFailure(_ failure: CommandFailure) {
        hud?.show(.message(title: failure.title, detail: failure.detail))
    }

    private func cancel() {
        drainTask?.cancel()
        drainingTail = false
        preview?.stop()
        let wasActive = isActive
        if wasActive { log(outcome: "cancelled") }
        runID = UUID()
        task?.cancel()
        limitTask?.cancel()
        flashTask?.cancel()
        if recorder.isRunning { _ = recorder.stop() }
        detector.reset()
        phase = .idle
        cycler = nil
        if wasActive {
            model.isListening = false
            hud?.hide()
            hud?.levelSource = { [weak model] in model?.dictation?.recordingLevel ?? 0 }
        }
    }
}
