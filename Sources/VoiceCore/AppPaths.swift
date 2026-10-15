import Foundation

public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func standard() -> AppPaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(root: base.appendingPathComponent("BugVoice", isDirectory: true))
    }

    public var settings: URL { root.appendingPathComponent("settings.json") }
    /// API keys, owner-only. See `CredentialStore`.
    public var credentials: URL { root.appendingPathComponent("credentials.json") }
    /// Dictionary words and snippets.
    public var dictionary: URL { root.appendingPathComponent("dictionary.json") }
    /// The old word list. Read once to migrate into `dictionary.json`.
    public var vocabulary: URL { root.appendingPathComponent("vocabulary.txt") }
    public var history: URL { root.appendingPathComponent("history.jsonl") }
    /// Daily usage totals for the Insights page. Numbers only.
    public var insights: URL { root.appendingPathComponent("insights.json") }
    public var lastRecording: URL { root.appendingPathComponent("last.wav") }
    public var models: URL { root.appendingPathComponent("models", isDirectory: true) }
    /// Reserved for sub-project 2.
    public var meetings: URL { root.appendingPathComponent("Meetings", isDirectory: true) }
    /// Notes stored as Markdown files.
    public var notes: URL { root.appendingPathComponent("Notes", isDirectory: true) }

    public func ensureExists() throws {
        for dir in [root, models, meetings, notes] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
