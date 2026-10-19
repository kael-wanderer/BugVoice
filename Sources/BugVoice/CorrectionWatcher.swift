import ApplicationServices
import BugVoiceMac
import Foundation
import VoiceCore

@MainActor
final class CorrectionWatcher {
    private unowned let model: AppModel
    private var task: Task<Void, Never>?
    private var watch: CorrectionWatch?
    private var app: String?

    init(model: AppModel) { self.model = model }

    func start(pasted: String, focus: FocusSnapshot, app: String?) {
        stop()
        guard model.settings.speech.learnFromCorrections, !focus.isSecure,
              focus.beforeText != nil, focus.afterText != nil,
              let element = FocusInspector.focusedElement() else { return }
        self.app = app
        watch = CorrectionWatch(pasted: pasted, before: focus.beforeText ?? "", after: focus.afterText ?? "")
        // Seed immediately so a fast edit followed by a clear preserves the last read.
        guard observe(element) else { stop(); return }
        task = Task { [weak self] in
            for _ in 0..<60 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                guard FocusInspector.isSameElement(element, FocusInspector.focusedElement()),
                      self.observe(element) else { self.stop(); return }
            }
            self?.stop()
        }
    }

    private func observe(_ element: AXUIElement) -> Bool {
        watch?.observe(value: FocusInspector.value(of: element)) ?? false
    }

    /// Ends the watch without recording: the pasted text was replaced by
    /// BugVoice itself (Paste raw, Redo, Retry), so a diff would be noise.
    func cancel() {
        task?.cancel()
        task = nil
        watch = nil
        app = nil
    }

    func stop() {
        task?.cancel()
        task = nil
        let result = watch?.result() ?? []
        watch = nil
        model.recordCorrections(result, app: app)
        app = nil
    }
}
