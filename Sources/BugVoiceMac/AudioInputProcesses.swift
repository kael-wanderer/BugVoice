import AppKit
import ApplicationServices
import CoreAudio
import Foundation
import VoiceCore

/// Reads which processes use audio input, for meeting detection.
public enum AudioInputProcesses {
    /// Every process Core Audio lists, with its input flag. Browser processes
    /// that use input carry their browser's window titles (needs Accessibility).
    /// Throws when Core Audio cannot list processes.
    public static func current() throws -> [AudioInputProcess] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size)
        guard status == noErr else { throw MeetingAudioCaptureError.coreAudio(operation: "list audio processes", status: status) }
        var objects = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: Int(size) / MemoryLayout<AudioObjectID>.size)
        status = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects)
        guard status == noErr else { throw MeetingAudioCaptureError.coreAudio(operation: "read audio processes", status: status) }

        var titleCache: [String: [String]] = [:]
        return objects.compactMap { object in
            guard let pid = pid(of: object), let bundleID = bundleID(of: object) else { return nil }
            let running = isRunningInput(object)
            var titles: [String] = []
            if running, let app = MeetingDetector.appBundleID(for: bundleID), MeetingDetector.browsers[app] != nil {
                if let cached = titleCache[app] {
                    titles = cached
                } else {
                    titles = windowTitles(bundleID: app)
                    titleCache[app] = titles
                }
            }
            return AudioInputProcess(pid: pid, bundleID: bundleID, isRunningInput: running, windowTitles: titles)
        }
    }

    /// Titles of the app's windows through Accessibility; empty without permission.
    public static func windowTitles(bundleID: String) -> [String] {
        guard AXIsProcessTrusted() else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).flatMap { app -> [String] in
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.25)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { return [] }
            return windows.compactMap { window in
                var title: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success else { return nil }
                return title as? String
            }
        }
    }

    private static func pid(of object: AudioObjectID) -> Int32? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func bundleID(of object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        guard status == noErr, let string = value?.takeRetainedValue() as String?, !string.isEmpty else { return nil }
        return string
    }

    private static func isRunningInput(_ object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr && value != 0
    }
}
