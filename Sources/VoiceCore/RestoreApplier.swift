import Foundation

public protocol FileMoving: Sendable {
    func moveItem(at source: URL, to destination: URL) throws
}

public struct SystemFileMoving: FileMoving {
    public init() {}
    public func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }
}

public enum RestoreApplier {
    public struct Outcome: Equatable, Sendable {
        public var backupCreatedAt: Date
        public var safetyCopy: URL
    }

    public static func pendingDirectory(for root: URL) -> URL {
        root.deletingLastPathComponent().appendingPathComponent("BugVoice Restore Pending", isDirectory: true)
    }

    public static func stage(archive: URL, root: URL, writer: BackupWriter,
                             meetingActive: Bool, uploadActive: Bool = false,
                             availableBytes: Int64) async throws -> BackupManifest {
        guard !meetingActive else { throw BackupError.meetingActive }
        guard !uploadActive else { throw BackupError.uploadActive }
        let manifest = try await writer.readManifest(archive)
        let needed = manifest.totalBytes + manifest.totalBytes / 10
        guard availableBytes >= needed else { throw BackupError.notEnoughSpace(bytes: needed - availableBytes) }
        let pending = pendingDirectory(for: root)
        let manager = FileManager.default
        try checkRecoveryData(in: pending)
        if manager.fileExists(atPath: pending.path) { try manager.removeItem(at: pending) }
        do {
            try await writer.extract(archive, into: pending)
            // A symlink would move into the library and point it at another folder.
            guard !containsSymlink(pending) else { throw BackupError.notABackup }
            let problems = manifest.problems(in: pending.appendingPathComponent("data"))
            guard problems.isEmpty else { throw BackupError.damaged(count: problems.count) }
            try Task.checkCancellation()
            try Data().write(to: pending.appendingPathComponent("ready"))
            return manifest
        } catch {
            try? manager.removeItem(at: pending)
            throw error
        }
    }

    public static func safetyCopies(in root: URL) -> [URL] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return folders.filter {
            $0.lastPathComponent.hasPrefix(BackupNaming.safetyCopyPrefix) &&
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.map { URL(fileURLWithPath: $0.path, isDirectory: true) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func containsSymlink(_ directory: URL) -> Bool {
        guard let items = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return false }
        for case let url as URL in items where (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return true
        }
        return false
    }

    private static func checkRecoveryData(in pending: URL) throws {
        if FileManager.default.fileExists(atPath: pending.appendingPathComponent("rollback-failed").path) {
            throw BackupError.failed("Restore did not finish: recovery data was kept in \(pending.path) and the restore safety copy. Recover it before trying again.")
        }
    }

    public static func applyPending(root: URL, now: Date, timeZone: TimeZone,
                                    mover: any FileMoving = SystemFileMoving()) throws -> Outcome? {
        let manager = FileManager.default
        let pending = pendingDirectory(for: root)
        guard manager.fileExists(atPath: pending.path) else { return nil }
        try checkRecoveryData(in: pending)
        guard manager.fileExists(atPath: pending.appendingPathComponent("ready").path) else {
            try manager.removeItem(at: pending)
            return nil
        }
        let manifest = try BackupManifest.decode(Data(contentsOf: pending.appendingPathComponent("backup.json")))
        let baseName = BackupNaming.safetyCopyName(at: now, timeZone: timeZone)
        var safety = root.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 1
        while manager.fileExists(atPath: safety.path) {
            suffix += 1
            safety = root.appendingPathComponent("\(baseName) (\(suffix))", isDirectory: true)
        }
        var moves: [(source: URL, destination: URL)] = []
        do {
            try manager.createDirectory(at: safety, withIntermediateDirectories: true)
            let names = BackupPlan.rootFiles + BackupPlan.rootFolders
            for (sourceRoot, destinationRoot) in [(root, safety), (pending.appendingPathComponent("data"), root)] {
                for name in names {
                    let source = sourceRoot.appendingPathComponent(name)
                    guard manager.fileExists(atPath: source.path) else { continue }
                    let destination = destinationRoot.appendingPathComponent(name)
                    try mover.moveItem(at: source, to: destination)
                    moves.append((source, destination))
                }
            }
            // Commit before fallible cleanup so the next launch cannot replay emptied data.
            try manager.removeItem(at: pending.appendingPathComponent("ready"))
        } catch {
            var rollbackFailed = false
            for move in moves.reversed() {
                do { try mover.moveItem(at: move.destination, to: move.source) }
                catch { rollbackFailed = true }
            }
            // A failed rollback may leave the only copy of library data in either directory.
            if !rollbackFailed {
                if (try? manager.contentsOfDirectory(atPath: safety.path).isEmpty) == true { try? manager.removeItem(at: safety) }
                try? manager.removeItem(at: pending)
            } else {
                // Prevent an automatic retry against a partially restored library.
                try? Data().write(to: pending.appendingPathComponent("rollback-failed"))
            }
            throw BackupError.failed("Restore did not finish: \(error.localizedDescription)")
        }
        // The restore is committed; cleanup that fails leaves a stale index or an
        // extra folder, never a wrong library, so it does not fail the restore.
        try? manager.removeItem(at: root.appendingPathComponent("SearchIndex"))
        for old in safetyCopies(in: root) where old.lastPathComponent != safety.lastPathComponent { try? manager.removeItem(at: old) }
        try? manager.removeItem(at: pending)
        return Outcome(backupCreatedAt: manifest.createdAt, safetyCopy: safety)
    }
}
