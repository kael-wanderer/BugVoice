import Foundation

/// What had keyboard focus, read through Accessibility by the app layer.
public struct FocusSnapshot: Sendable, Equatable {
    public var appName: String?
    public var bundleID: String?
    public var role: String?
    public var isSecure: Bool
    /// Heuristic: the focused element describes itself as a terminal
    /// (VS Code / Cursor integrated terminal).
    public var isTerminalPanel: Bool
    /// Browser page URL when one could be read.
    public var url: String?
    public var beforeText: String?
    public var selectedText: String?
    public var afterText: String?

    public init(
        appName: String? = nil,
        bundleID: String? = nil,
        role: String? = nil,
        isSecure: Bool = false,
        isTerminalPanel: Bool = false,
        url: String? = nil,
        beforeText: String? = nil,
        selectedText: String? = nil,
        afterText: String? = nil
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.role = role
        self.isSecure = isSecure
        self.isTerminalPanel = isTerminalPanel
        self.url = url
        self.beforeText = beforeText
        self.selectedText = selectedText
        self.afterText = afterText
    }

    public static let unknown = FocusSnapshot()
}
