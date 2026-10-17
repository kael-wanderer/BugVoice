import Foundation

/// One agent tool call for Settings › Agents. Never carries arguments or results.
public struct MCPActivityEntry: Equatable, Sendable {
    public var time: Date
    public var client: String
    public var tool: String
    /// The error sentence; nil when the call succeeded.
    public var error: String?

    public init(time: Date, client: String, tool: String, error: String?) {
        self.time = time
        self.client = client
        self.tool = tool
        self.error = error
    }
}

/// The last calls since launch, newest first. Kept in memory only.
public struct MCPActivity: Sendable {
    public static let limit = 20

    public private(set) var entries: [MCPActivityEntry] = []

    public init() {}

    public mutating func record(_ e: MCPActivityEntry) {
        entries.insert(e, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }
}
