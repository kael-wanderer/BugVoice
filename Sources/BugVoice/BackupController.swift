import AppKit
import BugVoiceMac
import Foundation
import Observation
import VoiceCore

@MainActor
@Observable
final class BackupController {
    enum Activity: Equatable {
        case idle
        case backingUp(done: Int, total: Int)
        case done(String, file: URL, note: String?)
        case failed(String)
    }

    var activity: Activity = .idle
    var lastBackup: (date: Date, bytes: Int64)?
    var nextBackup: Date?
    var folderMissing = false
    var safetyCopy: (url: URL, date: Date, bytes: Int64)?
    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private var writing = false
    @ObservationIgnored private var restoring = false
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private var writeTask: Task<(Int64, Int), Error>?
    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var reportedAutomaticFailure = false
    @ObservationIgnored private var pendingRelaunch = false

    init(model: AppModel) { self.model = model }

    var backupFolder: URL? {
        guard let bookmark = model.settings.backup.folderBookmark else { return nil }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale)
            if stale { model.settings.backup.folderBookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }
            return url
        } catch { return nil }
    }

    func setBackupFolder(_ url: URL) {
        do {
            model.settings.backup.folderBookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch { model.saveError = "Could not save the backup folder: \(error.localizedDescription)" }
    }

    func backUpNow(to destination: URL) async { await write(to: destination, automatic: false) }

    func cancel() {
        cancelled = true
        writeTask?.cancel()
    }

    private func write(to destination: URL, automatic: Bool) async {
        guard !writing, !restoring else { return }
        writing = true
        cancelled = false
        activity = .backingUp(done: 0, total: 0)
        defer { writing = false; writeTask = nil }
        do {
            guard await model.notesController.flushAll() else {
                throw BackupError.failed("Could not save notes before backing up. Resolve the note changes and try again.")
            }
            await model.meetings?.flushNotes()
            if cancelled { throw CancellationError() }
            let root = model.paths.root
            let createdAt = Date.now
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            let counts = BackupManifest.Counts(notes: model.notesController.notes.count, meetings: 0,
                                              dictations: model.history.count, dictionaryWords: model.dictionary.words.count,
                                              folders: model.library.folders.count, tags: model.tagRows.count)
            let task = Task.detached(priority: automatic ? .utility : .userInitiated) { [self, counts] () throws -> (Int64, Int) in
                try Task.checkCancellation()
                let plan = try BackupPlan.make(root: root)
                var counts = counts
                counts.meetings = Set(plan.files.compactMap { path -> String? in
                    let parts = path.split(separator: "/")
                    return parts.count > 2 && parts[0] == "Meetings" ? String(parts[1]) : nil
                }).count
                let bytes = try await BackupWriter().write(plan: plan, root: root, to: destination,
                    createdAt: createdAt, appVersion: appVersion, build: build, counts: counts) { done, total in
                        Task { @MainActor [weak self] in
                            guard let self, self.writing, !self.cancelled,
                                  case .backingUp = self.activity else { return }
                            self.activity = .backingUp(done: done, total: total)
                        }
                    }
                return (bytes, plan.skippedMeetings.count)
            }
            writeTask = task
            let (bytes, skipped) = try await task.value
            let note: String? = skipped == 0 ? nil : skipped == 1
                ? "1 meeting was still recording and was left out."
                : "\(skipped) meetings were still recording and were left out."
            activity = .done("Backed up \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) to \(destination.deletingLastPathComponent().lastPathComponent).", file: destination, note: note)
            if automatic {
                let folder = destination.deletingLastPathComponent()
                let keep = model.settings.backup.keep
                try await Task.detached(priority: .utility) {
                    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
                    for name in BackupSchedule.filesToDelete(names, keep: keep, timeZone: .current) {
                        try FileManager.default.removeItem(at: folder.appendingPathComponent(name))
                    }
                }.value
            }
            await refreshFolder()
        } catch is CancellationError {
            activity = .idle
        } catch {
            let message = error.localizedDescription
            activity = .failed(message)
            Log.app.error("\(message, privacy: .public)")
            if automatic, !reportedAutomaticFailure {
                reportedAutomaticFailure = true
                model.saveError = message
            }
        }
    }

    func inspect(_ archive: URL) async -> Result<BackupManifest, BackupError> {
        do { return .success(try await Task.detached { try await BackupWriter().readManifest(archive) }.value) }
        catch { return .failure(error as? BackupError ?? .failed(error.localizedDescription)) }
    }

    func restoreAndRelaunch(_ archive: URL) async -> BackupError? {
        guard !writing, !restoring else { return .failed("A backup or restore is already running.") }
        guard model.meetings?.isActive != true, model.uploads?.isBusy != true else { return .meetingActive }
        restoring = true
        defer { restoring = false }
        do {
            guard await model.notesController.flushAll() else {
                return .failed("Could not save notes before restoring. Resolve the note changes and try again.")
            }
            await model.meetings?.flushNotes()
            guard model.meetings?.isActive != true, model.uploads?.isBusy != true else { return .meetingActive }
            let root = model.paths.root
            _ = try await Task.detached {
                let values = try root.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                return try await RestoreApplier.stage(archive: archive, root: root, writer: BackupWriter(),
                    meetingActive: false, availableBytes: values.volumeAvailableCapacityForImportantUsage ?? 0)
            }.value
            // The next instance waits for this process to exit before replacing files.
            // Workspace must finish launching it before terminating this instance.
            guard await model.notesController.flushAll() else {
                try? FileManager.default.removeItem(at: RestoreApplier.pendingDirectory(for: root))
                return .failed("Could not save notes before restoring. Resolve the note changes and try again.")
            }
            await model.meetings?.flushNotes()
            guard model.meetings?.isActive != true, model.uploads?.isBusy != true else {
                try? FileManager.default.removeItem(at: RestoreApplier.pendingDirectory(for: root))
                return .meetingActive
            }
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            config.arguments = ["--restore-after-process", String(ProcessInfo.processInfo.processIdentifier)]
            if let screen = ProcessInfo.processInfo.environment["BUGVOICE_DEV_SCREEN"] {
                config.environment = ["BUGVOICE_DEV_SCREEN": screen]
            }
            return await withCheckedContinuation { continuation in
                NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
                    if let error {
                        try? FileManager.default.removeItem(at: RestoreApplier.pendingDirectory(for: root))
                        continuation.resume(returning: .failed("Could not relaunch BugVoice: \(error.localizedDescription)"))
                    } else {
                        continuation.resume(returning: nil)
                        DispatchQueue.main.async {
                            self.pendingRelaunch = true
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
        } catch { return error as? BackupError ?? .failed(error.localizedDescription) }
    }

    /// Disarm the handoff when the old instance cannot finish quitting.
    func cancelPendingRelaunch() {
        guard pendingRelaunch else { return }
        pendingRelaunch = false
        let pending = RestoreApplier.pendingDirectory(for: model.paths.root)
        do {
            // The waiting instance watches this marker, so remove it first.
            let ready = pending.appendingPathComponent("ready")
            if FileManager.default.fileExists(atPath: ready.path) {
                try FileManager.default.removeItem(at: ready)
            }
            try? FileManager.default.removeItem(at: pending)
            model.saveError = "Restore was cancelled because BugVoice could not quit. Try restoring again."
        } catch {
            model.saveError = "Could not cancel the pending restore: \(error.localizedDescription)"
        }
    }

    func startSchedule() {
        guard scheduleTask == nil else { return }
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkSchedule()
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            }
        }
        Task { await refreshSafetyCopy() }
    }

    /// Settings changes trigger a check without cancelling an in-flight write.
    func settingsChanged() {
        guard scheduleTask != nil else { return }
        Task { await checkSchedule() }
    }

    private func checkSchedule() async {
        let settings = model.settings.backup
        await refreshFolder()
        guard settings == model.settings.backup else { return }
        guard model.settings.backup.frequency != .off, !folderMissing,
              let folder = backupFolder, !writing, !restoring,
              model.meetings?.isActive != true, model.uploads?.isBusy != true,
              BackupSchedule.isDue(model.settings.backup.frequency, newest: lastBackup?.date, now: .now) else { return }
        do {
            let names = try await Task.detached(priority: .utility) { try FileManager.default.contentsOfDirectory(atPath: folder.path) }.value
            guard settings == model.settings.backup else { return }
            let name = BackupNaming.fileName(at: .now, timeZone: .current, taken: Set(names))
            await write(to: folder.appendingPathComponent(name), automatic: true)
        } catch {
            Log.app.error("\(error.localizedDescription, privacy: .public)")
            if !reportedAutomaticFailure { reportedAutomaticFailure = true; model.saveError = error.localizedDescription }
        }
    }

    private func refreshFolder() async {
        let settings = model.settings.backup
        guard let folder = backupFolder else {
            folderMissing = model.settings.backup.frequency != .off
            lastBackup = nil; nextBackup = nil
            return
        }
        let frequency = model.settings.backup.frequency
        let result = await Task.detached(priority: .utility) { () -> (Bool, Date?, Int64) in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else { return (true, nil, 0) }
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            let newest = names.compactMap { name -> (String, Date)? in
                BackupNaming.date(fromFileName: name, timeZone: .current).map { (name, $0) }
            }.max { $0.1 < $1.1 }
            let size = newest.flatMap { try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent($0.0).path)[.size] as? NSNumber }?.int64Value ?? 0
            return (false, newest?.1, size)
        }.value
        guard settings == model.settings.backup else { return }
        folderMissing = result.0
        lastBackup = result.1.map { ($0, result.2) }
        nextBackup = frequency == .off || folderMissing ? nil : result.1?.addingTimeInterval(frequency == .daily ? 86_400 : 604_800) ?? .now
    }

    private func refreshSafetyCopy() async {
        let root = model.paths.root
        safetyCopy = await Task.detached(priority: .utility) {
            guard let url = RestoreApplier.safetyCopies(in: root).last else { return nil as (url: URL, date: Date, bytes: Int64)? }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            var bytes: Int64 = 0
            if let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
                while let file = files.nextObject() as? URL {
                    if let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
                }
            }
            return (url, attributes?[.creationDate] as? Date ?? .now, bytes)
        }.value
    }

    func deleteSafetyCopy() {
        guard let safetyCopy else { return }
        do { try FileManager.default.removeItem(at: safetyCopy.url); self.safetyCopy = nil }
        catch { model.saveError = "Could not delete the safety copy: \(error.localizedDescription)" }
    }

    static func applyPendingRestore(root: URL) -> String? {
        do {
            guard let outcome = try RestoreApplier.applyPending(root: root, now: .now, timeZone: .current) else { return nil }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium; formatter.timeStyle = .short
            let message = "Restored the backup from \(formatter.string(from: outcome.backupCreatedAt))."
            Log.app.notice("\(message, privacy: .public)")
            return message
        } catch {
            Log.app.error("\(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }
}
