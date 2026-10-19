import Foundation

public struct BackupWriter: Sendable {
    private let runner: any ProcessRunner

    public init(runner: any ProcessRunner = FoundationProcessRunner()) {
        self.runner = runner
    }

    public func write(plan: BackupPlan, root: URL, to destination: URL, createdAt: Date,
                      appVersion: String, build: String, counts: BackupManifest.Counts,
                      progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> Int64 {
        let rootPath = root.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path
        guard destinationPath != rootPath, !destinationPath.hasPrefix(rootPath + "/") else {
            throw BackupError.destinationInsideLibrary
        }
        let manager = FileManager.default
        let staging = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: root, create: true)
        let partial = URL(fileURLWithPath: destination.path + ".partial")
        defer {
            try? manager.removeItem(at: staging)
            try? manager.removeItem(at: partial)
        }
        let dataDirectory = staging.appendingPathComponent("data", isDirectory: true)
        try manager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        var files: [BackupManifest.File] = []
        for path in plan.files {
            try Task.checkCancellation()
            let copied = dataDirectory.appendingPathComponent(path)
            try manager.createDirectory(at: copied.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: root.appendingPathComponent(path), to: copied)
            let size = try manager.attributesOfItem(atPath: copied.path)[.size] as? NSNumber
            files.append(.init(path: path, size: size?.int64Value ?? 0))
            progress(files.count, plan.files.count)
        }
        try Task.checkCancellation()
        let manifest = BackupManifest(format: 1, createdAt: createdAt, appVersion: appVersion,
                                      build: build, counts: counts, files: files)
        try manifest.encoded().write(to: staging.appendingPathComponent("backup.json"))
        let result = try await runner.run(executable: "/usr/bin/ditto",
                                          arguments: ["-c", "-k", "--norsrc", "--noextattr", "--noacl", staging.path, partial.path],
                                          stdin: "", workingDirectory: nil, timeout: 3600)
        guard result.exitCode == 0 else {
            let firstLine = result.stderr.components(separatedBy: .newlines).first ?? ""
            throw BackupError.failed("Could not write the backup: \(firstLine)")
        }
        try Task.checkCancellation()
        if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
        try manager.moveItem(at: partial, to: destination)
        let attributes = try manager.attributesOfItem(atPath: destination.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    public func readManifest(_ archive: URL) async throws -> BackupManifest {
        let result = try await runner.run(executable: "/usr/bin/unzip", arguments: ["-p", archive.path, "backup.json"],
                                          stdin: "", workingDirectory: nil, timeout: 60)
        guard result.exitCode == 0, !result.stdout.isEmpty else { throw BackupError.notABackup }
        return try BackupManifest.decode(Data(result.stdout.utf8))
    }

    public func extract(_ archive: URL, into directory: URL) async throws {
        let result = try await runner.run(executable: "/usr/bin/ditto", arguments: ["-x", "-k", archive.path, directory.path],
                                          stdin: "", workingDirectory: nil, timeout: 3600)
        guard result.exitCode == 0 else { throw BackupError.failed("Could not open the backup.") }
    }
}
