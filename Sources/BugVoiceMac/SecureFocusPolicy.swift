import Foundation

/// Result of reading one Accessibility attribute.
public enum AttributeRead: Sendable, Equatable {
    case value(String)
    /// The element has no such attribute or it is empty (`.noValue`, `.attributeUnsupported`).
    case absent
    /// Any other AX error (timeout, invalid element, ...). Unknown, not "not secure".
    case failed

    var value: String? {
        if case .value(let string) = self { return string }
        return nil
    }
}

public enum SecureInputState: Sendable, Equatable {
    case off
    case owner(pid_t)
    /// Secure input is on but its owner could not be read.
    case ownerUnknown
}

/// Decides whether the focus must be treated as a secure field. Fails closed:
/// only a successful read showing a non-secure role and subrole, or an
/// unreadable focus while no app holds Secure Event Input, yields false.
public enum SecureFocusPolicy {
    public static func isSecure(
        axTrusted: Bool,
        focusedElementReadable: Bool,
        role: AttributeRead,
        subrole: AttributeRead,
        secureInput: SecureInputState,
        frontmostPID: pid_t?
    ) -> Bool {
        switch secureInput {
        case .off: break
        case .ownerUnknown: return true
        case .owner(let pid): if pid == frontmostPID { return true }
        }
        guard axTrusted else { return true }
        // Electron apps such as VS Code expose no focused element. A password
        // field there still turns on Secure Event Input, so with it off the
        // focus is treated as plain text.
        guard focusedElementReadable else { return secureInput != .off }
        if role == .failed || subrole == .failed { return true }
        return role == .value("AXSecureTextField") || subrole == .value("AXSecureTextField")
    }
}
