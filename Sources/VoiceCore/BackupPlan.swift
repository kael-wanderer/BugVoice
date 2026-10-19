import Foundation

public struct BackupPlan: Equatable, Sendable {
    public var files: [String]
    public var skippedMeetings: [String]
    public var totalBytes: Int64

    public init(files: [String], skippedMeetings: [String], totalBytes: Int64) {
        self.files = files
        self.skippedMeetings = skippedMeetings
        self.totalBytes = totalBytes
    }

    public static let rootFiles = [
        "settings.json", "dictionary.json", "history.jsonl", "insights.json", "library.json", "projects.json", "suggestions.json", "voices.json"
    ]
    public static let rootFolders = ["Meetings", "Notes"]

    public static func make(root: URL) throws -> BackupPlan {
        let manager = FileManager.default
        var plan = BackupPlan(files: [], skippedMeetings: [], totalBytes: 0)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]

        func include(_ url: URL, path: String) throws {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { return }
            plan.files.append(path)
            plan.totalBytes += Int64(values.fileSize ?? 0)
        }

        func includeFolder(_ folder: URL, prefix: String, meeting: Bool) throws {
            let folder = folder.resolvingSymlinksInPath()
            var enumerationError: Error?
            guard let enumerator = manager.enumerator(
                at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles],
                errorHandler: { _, error in enumerationError = error; return false }
            ) else { return }
            for case let url as URL in enumerator {
                if url.lastPathComponent.hasPrefix(".") {
                    enumerator.skipDescendants()
                    continue
                }
                if meeting && (url.lastPathComponent == "checkpoint.json" || url.pathExtension == "pcm") { continue }
                let relative = url.resolvingSymlinksInPath().pathComponents.dropFirst(folder.pathComponents.count).joined(separator: "/")
                try include(url, path: prefix + "/" + relative)
            }
            if let enumerationError { throw enumerationError }
        }

        guard manager.fileExists(atPath: root.path) else { return plan }
        for name in rootFiles {
            let url = root.appendingPathComponent(name)
            if manager.fileExists(atPath: url.path) { try include(url, path: name) }
        }
        let notes = root.appendingPathComponent("Notes", isDirectory: true)
        if manager.fileExists(atPath: notes.path) {
            try includeFolder(notes, prefix: "Notes", meeting: false)
        }
        let meetings = root.appendingPathComponent("Meetings", isDirectory: true)
        if manager.fileExists(atPath: meetings.path) {
            let folders = try manager.contentsOfDirectory(
                at: meetings, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )
            for folder in folders {
                guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                let manifest = folder.appendingPathComponent("meeting.json")
                let state = (try? Data(contentsOf: manifest)).flatMap { try? JSONDecoder().decode(MeetingStatus.self, from: $0) }
                guard !manager.fileExists(atPath: folder.appendingPathComponent(".upload-cancelled").path),
                      let state, state.state == .ready || state.state == .failed else {
                    plan.skippedMeetings.append(folder.lastPathComponent)
                    continue
                }
                try includeFolder(folder, prefix: "Meetings/" + folder.lastPathComponent, meeting: true)
            }
        }
        plan.files.sort()
        plan.skippedMeetings.sort()
        return plan
    }

    private struct MeetingStatus: Decodable {
        var state: MeetingState
    }
}
