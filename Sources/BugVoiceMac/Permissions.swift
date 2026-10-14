import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

public enum PermissionKind: CaseIterable, Sendable {
    case microphone, accessibility, inputMonitoring
}

public enum Permissions {
    public static func isGranted(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility: AXIsProcessTrusted()
        case .inputMonitoring: CGPreflightListenEventAccess()
        }
    }

    public static var allGranted: Bool { PermissionKind.allCases.allSatisfy(isGranted) }

    public static func request(_ kind: PermissionKind) async {
        switch kind {
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .accessibility:
            // Literal value of kAXTrustedCheckOptionPrompt, which Swift 6
            // rejects as a mutable C global.
            let key = "AXTrustedCheckOptionPrompt"
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        }
    }

    @MainActor
    public static func openSettings(_ kind: PermissionKind) {
        let anchor = switch kind {
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
