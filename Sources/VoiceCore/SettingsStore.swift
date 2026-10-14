import Foundation

public struct SettingsStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Never throws: a missing file gives defaults; an unreadable one is moved
    /// aside as `settings.json.corrupt-<unix time>` so the next save does not
    /// destroy what the user had.
    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: url) else { return AppSettings() }
        if let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        let aside = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.moveItem(at: url, to: aside)
        return AppSettings()
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }
}
