import Foundation
import VoiceCore

public struct ProjectScanResult: Equatable, Sendable {
    public var words: [ProjectWord]
    public var fileCount: Int
    public var stoppedEarly: Bool

    public init(words: [ProjectWord], fileCount: Int, stoppedEarly: Bool) {
        self.words = words
        self.fileCount = fileCount
        self.stoppedEarly = stoppedEarly
    }
}

public enum ProjectScanError: Error, Equatable {
    case folderNotFound, noCodeFiles
}

public enum ProjectScanner {
    public static let maxFiles = 5_000
    public static let maxFileBytes = 256 * 1024
    public static let skippedFolders: Set<String> = ["node_modules", ".build", "build", "dist", "DerivedData", "Pods", "vendor", "target", "venv", ".venv"]
    private static let gitTimeout: DispatchTimeInterval = .seconds(5)

    public static func listFiles(in folder: URL) async -> [String] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        if let gitFiles = gitListFiles(in: folder) { return Array(gitFiles.prefix(maxFiles)) }
        return walkFiles(in: folder)
    }

    public static func scan(folder: URL, hidden: Set<String>, timeLimit: Duration = .seconds(30)) async throws -> ProjectScanResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectScanError.folderNotFound
        }
        let paths = await listFiles(in: folder)
        let codePaths = paths.filter(ProjectWordExtractor.shouldRead(path:))
        guard !codePaths.isEmpty else { throw ProjectScanError.noCodeFiles }

        let started = ContinuousClock.now
        var sourceFiles: [ProjectSourceFile] = []
        var processed = 0
        var stoppedEarly = false
        for path in paths {
            if ContinuousClock.now - started >= timeLimit {
                stoppedEarly = true
                break
            }
            processed += 1
            guard !ProjectWordExtractor.isSecretLooking(path: path) else { continue }
            if ProjectWordExtractor.shouldRead(path: path) {
                let url = folder.appendingPathComponent(path)
                sourceFiles.append(ProjectSourceFile(path: path, contents: readSourceFile(url)))
            } else {
                sourceFiles.append(ProjectSourceFile(path: path, contents: nil))
            }
        }
        let words = ProjectWordExtractor.extract(files: sourceFiles, hidden: hidden)
        return ProjectScanResult(words: words, fileCount: processed, stoppedEarly: stoppedEarly)
    }

    private static func readSourceFile(_ url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= maxFileBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        if data.prefix(8 * 1024).contains(0) { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func gitListFiles(in folder: URL) -> [String]? {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("bv-git-files-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temp.path, contents: nil),
              let output = try? FileHandle(forWritingTo: temp) else { return nil }
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: temp)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path, "ls-files", "-z"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + gitTimeout) == .timedOut {
            process.terminate()
            process.waitUntilExit()
            return nil
        }
        try? output.close()
        guard process.terminationStatus == 0,
              let data = try? Data(contentsOf: temp), let text = String(data: data, encoding: .utf8) else { return nil }
        return filteredPaths(text.split(separator: "\0").map(String.init))
    }

    private static func walkFiles(in folder: URL) -> [String] {
        var result: [String] = []
        let fm = FileManager.default
        var pending = [folder.standardizedFileURL]
        while let directory = pending.popLast(), result.count < maxFiles {
            guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey], options: []) else { continue }
            for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard result.count < maxFiles else { break }
                let name = url.lastPathComponent
                guard !name.hasPrefix("."), let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]), values.isSymbolicLink != true else { continue }
                if values.isDirectory == true {
                    guard !skippedFolders.contains(name) else { continue }
                    pending.append(url)
                } else if values.isRegularFile == true {
                    result.append(String(url.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count + 1)))
                }
            }
        }
        return result.sorted()
    }

    private static func filteredPaths(_ paths: [String]) -> [String] {
        paths.filter { path in
            let directories = path.split(separator: "/").dropLast().map(String.init)
            return !directories.contains(where: { $0.hasPrefix(".") || skippedFolders.contains($0) })
        }.sorted()
    }
}
