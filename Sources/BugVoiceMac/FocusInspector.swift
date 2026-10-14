import AppKit
import ApplicationServices
import VoiceCore

public struct FocusInspector: FocusProvider {
    public init() {}

    public func snapshot() async -> FocusSnapshot {
        await MainActor.run { Self.read() }
    }

    static let contextLimit = 2_000

    @MainActor
    public static func read() -> FocusSnapshot {
        let app = NSWorkspace.shared.frontmostApplication
        var snap = FocusSnapshot(appName: app?.localizedName, bundleID: app?.bundleIdentifier)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        guard let element = element(system, kAXFocusedUIElementAttribute) else { return snap }
        AXUIElementSetMessagingTimeout(element, 0.25)

        let role = string(element, kAXRoleAttribute)
        let subrole = string(element, kAXSubroleAttribute)
        snap.role = role
        snap.isSecure = subrole == kAXSecureTextFieldSubrole as String || role == "AXSecureTextField"

        let label = [kAXDescriptionAttribute, kAXTitleAttribute, kAXRoleDescriptionAttribute, kAXHelpAttribute]
            .compactMap { string(element, $0) }
            .joined(separator: " ")
            .lowercased()
        snap.isTerminalPanel = label.contains("terminal")

        if !snap.isSecure, let value = string(element, kAXValueAttribute), let range = selectedRange(element) {
            let utf16 = value.utf16
            let start = max(0, min(range.location, utf16.count))
            let end = max(start, min(range.location + range.length, utf16.count))
            let startIndex = utf16.index(utf16.startIndex, offsetBy: start)
            let endIndex = utf16.index(utf16.startIndex, offsetBy: end)
            snap.beforeText = String(String(value[..<startIndex]).suffix(contextLimit))
            snap.selectedText = String(value[startIndex..<endIndex])
            snap.afterText = String(String(value[endIndex...]).prefix(contextLimit))
        }
        snap.url = url(near: element)
        return snap
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    /// Browsers expose the page URL on an ancestor `AXWebArea`.
    static func url(near start: AXUIElement) -> String? {
        var current: AXUIElement? = start
        for _ in 0..<30 {
            guard let element = current else { return nil }
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &value) == .success, let url = value as? URL {
                return url.absoluteString
            }
            current = self.element(element, kAXParentAttribute)
        }
        return nil
    }
}
