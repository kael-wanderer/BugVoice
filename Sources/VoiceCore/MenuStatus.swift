import Foundation

/// Speech model state as the menu popover sees it.
public enum MenuSpeechState: Equatable, Sendable { case ready, downloading(Double), loading, failed }
/// Meeting state as the menu popover sees it.
public enum MenuMeetingState: Equatable, Sendable { case idle, recording, paused, transcribing }
/// Color family of the status card.
public enum MenuTone: Equatable, Sendable { case good, warning, recording }
/// What the status card's button does.
public enum MenuStatusAction: Equatable, Sendable { case fixPermissions, retrySpeech, fixHotkey }

/// The one status the menu popover shows, with its copy.
public enum MenuStatus: Equatable, Sendable {
    case needsPermissions([String]), secureInput(app: String), listening
    case speechDownloading(percent: Int), speechLoading, speechFailed, hotkeyInactive
    case meetingRecording, meetingPaused, ready

    /// Picks the highest-priority status, in the order of the native menu.
    public static func resolve(missingPermissions: [String], secureInputApp: String?, listening: Bool,
                               speech: MenuSpeechState, hotkeyActive: Bool, meeting: MenuMeetingState) -> MenuStatus {
        if !missingPermissions.isEmpty { return .needsPermissions(missingPermissions) }
        if let app = secureInputApp { return .secureInput(app: app) }
        if listening { return .listening }
        switch speech {
        case .downloading(let fraction): return .speechDownloading(percent: Int(fraction * 100))
        case .loading: return .speechLoading
        case .failed: return .speechFailed
        case .ready: break
        }
        if !hotkeyActive { return .hotkeyInactive }
        switch meeting {
        case .recording: return .meetingRecording
        case .paused: return .meetingPaused
        case .idle, .transcribing: return .ready
        }
    }

    public var tone: MenuTone {
        switch self {
        case .ready: return .good
        case .listening, .meetingRecording, .meetingPaused: return .recording
        default: return .warning
        }
    }

    public var title: String {
        switch self {
        case .needsPermissions: return "Needs permissions"
        case .secureInput: return "Secure input is on"
        case .listening: return "Listening…"
        case .speechDownloading: return "Speech model downloading"
        case .speechLoading: return "Speech model loading"
        case .speechFailed: return "Speech model failed to load"
        case .hotkeyInactive: return "Hotkey not active"
        case .meetingRecording: return "Recording a meeting"
        case .meetingPaused: return "Meeting paused"
        case .ready: return "Ready to dictate"
        }
    }

    public func detail(hotkey: String) -> String? {
        switch self {
        case .needsPermissions(let names):
            switch names.count {
            case 0: return nil
            case 1: return "\(names[0]) is off"
            default: return "\(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1]) are off"
            }
        case .secureInput(let app): return "\(app) · hotkey paused"
        case .speechDownloading(let percent): return "\(percent)%"
        case .meetingRecording: return "Dictation still works · hold \(hotkey)"
        case .ready: return "Hold \(hotkey) to speak · release to paste"
        default: return nil
        }
    }

    public var action: MenuStatusAction? {
        switch self {
        case .needsPermissions: return .fixPermissions
        case .speechFailed: return .retrySpeech
        case .hotkeyInactive: return .fixHotkey
        default: return nil
        }
    }

    public var actionTitle: String? {
        switch action {
        case .fixPermissions, .fixHotkey: return "Fix…"
        case .retrySpeech: return "Retry"
        case nil: return nil
        }
    }
}
