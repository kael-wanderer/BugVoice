import BugVoiceMac
import Foundation
import VoiceCore

/// One recording's display-only passes. Final transcription stays in the pipelines.
@MainActor
final class LivePreviewController {
    private let recorder: AudioRecorder
    private let transcriber: any Transcriber
    private let hud: HUDController
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?

    init(recorder: AudioRecorder, transcriber: any Transcriber, hud: HUDController) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.hud = hud
    }

    func start(enabled: Bool, language: @escaping @MainActor () -> SpeechLanguage, prompt: String) {
        stop()
        hud.setPreview(nil)
        guard enabled else { return }
        let id = generation
        task = Task { [weak self] in
            var lastReturnedAt: Date?
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, self.generation == id, self.recorder.isRunning else { return }
                // Awaiting the pass inside this loop guarantees one pass at a time.
                guard LivePreviewCadence.shouldStart(recorded: self.recorder.recordedDuration,
                    running: false, lastReturnedAt: lastReturnedAt, now: Date()) else { continue }
                let clip = self.recorder.recentSamples(seconds: LivePreviewCadence.window)
                guard clip.rms >= 0.003 else {
                    lastReturnedAt = Date()
                    continue
                }
                do {
                    let transcript = try await self.transcriber.transcribe(clip,
                        options: TranscriptionOptions(language: language(), prompt: prompt, priority: .preview))
                    guard !Task.isCancelled, self.generation == id, self.recorder.isRunning else { return }
                    if let text = LivePreviewText.display(transcript.text) { self.hud.setPreview(text) }
                } catch {
                    // Preview is optional: errors never reach diagnostics or history.
                }
                lastReturnedAt = Date()
            }
        }
    }

    /// Invalidates in-flight results but keeps the last card through processing.
    func stop() {
        generation &+= 1
        task?.cancel()
        task = nil
    }
}
