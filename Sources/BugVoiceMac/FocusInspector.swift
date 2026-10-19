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
    public static func focusedElement() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        return element(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute)
    }

    /// Read only after the element passes the secure-focus policy.
    @MainActor
    public static func value(of element: AXUIElement) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.25)
        let secure = SecureFocusPolicy.isSecure(
            axTrusted: true, focusedElementReadable: true,
            role: read(element, kAXRoleAttribute), subrole: read(element, kAXSubroleAttribute),
            secureInput: SecureInputMonitor.state,
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        guard !secure, let value = string(element, kAXValueAttribute),
              value.count <= CorrectionRegion.maxValueLength else { return nil }
        return value
    }

    public static func isSameElement(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool {
        guard let a, let b else { return false }
        return CFEqual(a, b)
    }

    @MainActor
    public static func read() -> FocusSnapshot {
        let app = NSWorkspace.shared.frontmostApplication
        var snap = FocusSnapshot(appName: app?.localizedName, bundleID: app?.bundleIdentifier)
        let frontPID = app?.processIdentifier
        let secureInput = SecureInputMonitor.state
        guard AXIsProcessTrusted() else {
            // Fail closed: without Accessibility nothing can be verified.
            snap.isSecure = true
            return snap
        }
        if let frontPID {
            let appElement = AXUIElementCreateApplication(frontPID)
            AXUIElementSetMessagingTimeout(appElement, 0.25)
            if let window = element(appElement, kAXFocusedWindowAttribute) {
                AXUIElementSetMessagingTimeout(window, 0.25)
                snap.windowTitle = string(window, kAXTitleAttribute)
            }
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        guard let element = element(system, kAXFocusedUIElementAttribute) else {
            snap.isSecure = SecureFocusPolicy.isSecure(
                axTrusted: true, focusedElementReadable: false, role: .failed, subrole: .failed,
                secureInput: secureInput, frontmostPID: frontPID)
            return snap
        }
        AXUIElementSetMessagingTimeout(element, 0.25)

        let roleRead = read(element, kAXRoleAttribute)
        let subroleRead = read(element, kAXSubroleAttribute)
        snap.role = roleRead.value
        snap.isSecure = SecureFocusPolicy.isSecure(
            axTrusted: true, focusedElementReadable: true, role: roleRead, subrole: subroleRead,
            secureInput: secureInput, frontmostPID: frontPID)

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

    /// Reads a string attribute and keeps the AX error class, so a timeout is
    /// not mistaken for "attribute absent".
    static func read(_ element: AXUIElement, _ attribute: String) -> AttributeRead {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, attribute as CFString, &value) {
        case .success:
            if let string = value as? String { return .value(string) }
            return .absent
        case .noValue, .attributeUnsupported:
            return .absent
        default:
            return .failed
        }
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
