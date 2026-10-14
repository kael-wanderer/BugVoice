import AppKit
import Carbon

/// While any app holds Secure Event Input, the event tap sees no key events,
/// so the hotkey cannot work. The menu shows which app holds it.
public enum SecureInputMonitor {
    public static var isActive: Bool { IsSecureEventInputEnabled() }

    public static var state: SecureInputState {
        guard isActive else { return .off }
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = session["kCGSSessionSecureInputPID"] as? pid_t
        else { return .ownerUnknown }
        return .owner(pid)
    }

    public static var owningAppName: String? {
        guard isActive,
              let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = session["kCGSSessionSecureInputPID"] as? pid_t
        else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }
}
