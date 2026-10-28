import Foundation

/// How a readiness row reads: fine, still getting ready, needs a fix, or
/// turned off on purpose.
public enum ReadinessTone: Equatable, Sendable { case ok, waiting, problem, off }

/// What a readiness row's button does.
public enum ReadinessAction: Equatable, Sendable { case openPermissions, retryHotkey, retrySpeech, checkCleanup, openModels }

/// The dictation cleanup model as the readiness card sees it.
public enum CleanupCheck: Equatable, Sendable {
    /// Cleanup is set to None: raw text is pasted.
    case off
    /// The connection has not been checked this session.
    case unchecked(name: String)
    case reachable(name: String)
    case failed(name: String, message: String)
    /// Apple Intelligence or a coding CLI: nothing to reach over the network.
    case local(name: String)
    /// The chosen model cannot be used, with the reason.
    case unavailable(String)
}

public struct ReadinessRow: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case permissions, hotkey, speech, cleanup }
    public var kind: Kind
    public var title: String
    public var detail: String
    public var tone: ReadinessTone
    public var action: ReadinessAction?
    public var actionTitle: String?
    public var id: String { kind.rawValue }
}

/// The four things dictation needs, in the order they are checked.
public enum Readiness {
    public static func rows(missingPermissions: [String], hotkeyActive: Bool, hotkey: String,
                            speech: MenuSpeechState, onDeviceModel: String?, serverURL: String?,
                            cleanup: CleanupCheck) -> [ReadinessRow] {
        [permissions(missingPermissions), hotkeyRow(active: hotkeyActive, hotkey: hotkey),
         speechRow(speech, onDeviceModel: onDeviceModel, serverURL: serverURL), cleanupRow(cleanup)]
    }

    /// Ready when nothing needs a fix or is still loading. Cleanup off counts as ready.
    public static func isReady(_ rows: [ReadinessRow]) -> Bool {
        rows.allSatisfy { $0.tone == .ok || $0.tone == .off }
    }

    public static func summary(_ rows: [ReadinessRow]) -> String {
        if isReady(rows) { return "Ready to dictate" }
        let problems = rows.filter { $0.tone == .problem }.count
        if problems == 0 { return "Getting ready" }
        return problems == 1 ? "1 item needs attention" : "\(problems) items need attention"
    }

    static func permissions(_ missing: [String]) -> ReadinessRow {
        guard !missing.isEmpty else {
            return ReadinessRow(kind: .permissions, title: "Permissions",
                                detail: "Microphone, Accessibility and Input Monitoring are on", tone: .ok)
        }
        let names = missing.count == 1
            ? missing[0]
            : missing.dropLast().joined(separator: ", ") + " and " + missing[missing.count - 1]
        return ReadinessRow(kind: .permissions, title: "Permissions",
                            detail: "\(names) \(missing.count == 1 ? "is" : "are") off", tone: .problem,
                            action: .openPermissions, actionTitle: "Open permissions")
    }

    static func hotkeyRow(active: Bool, hotkey: String) -> ReadinessRow {
        active
            ? ReadinessRow(kind: .hotkey, title: "Hotkey", detail: "Hold \(hotkey) to speak", tone: .ok)
            : ReadinessRow(kind: .hotkey, title: "Hotkey", detail: "\(hotkey) is not being watched", tone: .problem,
                           action: .retryHotkey, actionTitle: "Try again")
    }

    static func speechRow(_ speech: MenuSpeechState, onDeviceModel: String?, serverURL: String?) -> ReadinessRow {
        guard let onDeviceModel else {
            return ReadinessRow(kind: .speech, title: "Speech model",
                                detail: "Speech server at \(serverURL ?? "no address")", tone: .ok)
        }
        switch speech {
        case .ready:
            return ReadinessRow(kind: .speech, title: "Speech model", detail: "\(onDeviceModel) on this Mac", tone: .ok)
        case .downloading(let fraction):
            return ReadinessRow(kind: .speech, title: "Speech model",
                                detail: "Downloading \(onDeviceModel), \(Int(fraction * 100))%", tone: .waiting)
        case .loading:
            return ReadinessRow(kind: .speech, title: "Speech model", detail: "Loading \(onDeviceModel)", tone: .waiting)
        case .failed:
            return ReadinessRow(kind: .speech, title: "Speech model", detail: "\(onDeviceModel) failed to load",
                                tone: .problem, action: .retrySpeech, actionTitle: "Retry")
        }
    }

    static func cleanupRow(_ cleanup: CleanupCheck) -> ReadinessRow {
        switch cleanup {
        case .off:
            return ReadinessRow(kind: .cleanup, title: "Cleanup model", detail: "Off, raw text is pasted", tone: .off,
                                action: .openModels, actionTitle: "Choose a model")
        case .unchecked(let name):
            return ReadinessRow(kind: .cleanup, title: "Cleanup model", detail: "\(name), not checked yet", tone: .waiting,
                                action: .checkCleanup, actionTitle: "Check")
        case .reachable(let name):
            return ReadinessRow(kind: .cleanup, title: "Cleanup model", detail: "\(name), server reachable", tone: .ok)
        case .failed(let name, let message):
            return ReadinessRow(kind: .cleanup, title: "Cleanup model", detail: "\(name): \(message)", tone: .problem,
                                action: .checkCleanup, actionTitle: "Check again")
        case .local(let name):
            return ReadinessRow(kind: .cleanup, title: "Cleanup model", detail: name, tone: .ok)
        case .unavailable(let reason):
            return ReadinessRow(kind: .cleanup, title: "Cleanup model", detail: reason, tone: .problem,
                                action: .openModels, actionTitle: "Open Models")
        }
    }
}
