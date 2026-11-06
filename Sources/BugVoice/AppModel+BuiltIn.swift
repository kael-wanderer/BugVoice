import AppKit
import BugVoiceMac
import Foundation
import VoiceCore

/// Built-in cleanup models: which are on disk, downloading one, and deleting one.
extension AppModel {
    /// A model counts as installed when its final file has the catalog size.
    /// Its hash was checked when the download finished. Run at launch and
    /// after each download or delete; never polled.
    func refreshBuiltInInstalled() {
        let dir = paths.cleanupModels
        builtInInstalled = Set(BuiltInCatalog.models.filter { model in
            let file = BuiltInDownloadPlan.finalURL(for: model, in: dir)
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value
            return size == model.bytes
        }.map(\.id))
    }

    /// True while the setup window is on screen.
    var onboardingWindowIsOpen: Bool {
        NSApp.windows.contains { $0.identifier == AppWindow.onboarding && $0.isVisible }
    }

    /// The model that is downloading now, if any. One download at a time.
    var builtInDownloadingID: String? { builtInDownloadTask?.id }

    /// Starts downloading `model` and returns the task, whose value is true
    /// when the model is installed. Nil when another download is running.
    @discardableResult
    func downloadBuiltIn(_ model: BuiltInModel) -> Task<Bool, Never>? {
        if let current = builtInDownloadTask {
            return current.id == model.id ? current.task : nil
        }
        builtInDownloadErrors[model.id] = nil
        builtInLoadFailures[model.id] = nil
        builtInDownloads[model.id] = 0
        builtInDownloadStart = nil
        let dir = paths.cleanupModels
        let id = model.id
        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in self?.noteBuiltInProgress(id, fraction) }
        }
        let task = Task { [weak self] () -> Bool in
            do {
                _ = try await BuiltInDownloader().download(model, into: dir, progress: report)
                self?.finishBuiltInDownload(id, error: nil)
                return true
            } catch {
                self?.finishBuiltInDownload(id, error: error)
                return false
            }
        }
        builtInDownloadTask = (id, task)
        return task
    }

    /// Stops the download. The partial file stays, so the next Download resumes.
    func cancelBuiltInDownload(_ id: String) {
        guard let current = builtInDownloadTask, current.id == id else { return }
        current.task.cancel()
    }

    /// Stops the server if it uses the model, then deletes the file and any
    /// partial download. Dictation and Notes stop using it first.
    func deleteBuiltIn(_ model: BuiltInModel) async {
        // Let a cancelled download stop writing before its files go.
        if let current = builtInDownloadTask, current.id == model.id {
            current.task.cancel()
            _ = await current.task.value
        }
        BuiltInChoices.forget(model.id, in: &settings.models)
        await builtInServer.release(modelID: model.id)
        let dir = paths.cleanupModels
        let fm = FileManager.default
        for url in [BuiltInDownloadPlan.finalURL(for: model, in: dir), BuiltInDownloadPlan.partialURL(for: model, in: dir)]
        where fm.fileExists(atPath: url.path) {
            do {
                try fm.removeItem(at: url)
            } catch {
                // The error text can hold the file's path: log only its domain and code.
                let ns = error as NSError
                Log.app.error("could not delete built-in \(model.id, privacy: .public): \(ns.domain, privacy: .public) \(ns.code, privacy: .public)")
                saveError = "Could not delete \(model.name)."
            }
        }
        builtInDownloadErrors[model.id] = nil
        builtInLoadFailures[model.id] = nil
        refreshBuiltInInstalled()
    }

    /// The server's report on each start: records or clears the readiness failure.
    func noteBuiltInLoad(_ id: String, error: Error?) {
        guard let error else {
            builtInLoadFailures[id] = nil
            return
        }
        guard let message = BuiltInChoices.loadFailureMessage(error) else { return }
        builtInLoadFailures[id] = message
        // A missing or truncated file shows as "not downloaded" rather than a load failure.
        refreshBuiltInInstalled()
    }

    private func noteBuiltInProgress(_ id: String, _ fraction: Double) {
        // A late update after the download ended must not bring the row back.
        guard builtInDownloadTask?.id == id, let old = builtInDownloads[id] else { return }
        if builtInDownloadStart == nil { builtInDownloadStart = (Date(), fraction) }
        // Redraw at most once per 0.1%.
        if Int(fraction * 1000) != Int(old * 1000) { builtInDownloads[id] = fraction }
    }

    private func finishBuiltInDownload(_ id: String, error: Error?) {
        builtInDownloadTask = nil
        builtInDownloads[id] = nil
        builtInDownloadStart = nil
        if let error, !BuiltInDownloadError.isCancellation(error) {
            builtInDownloadErrors[id] = BuiltInDownloadError.message(for: error)
            Log.app.error("built-in download failed for \(id, privacy: .public)")
        }
        refreshBuiltInInstalled()
        if error == nil { preloadBuiltInModel(releaseUnused: false) }
    }
}
